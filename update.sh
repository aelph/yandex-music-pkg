#!/usr/bin/env bash
# Обновление пакета yandex-music-system-electron из официального фида Яндекса.
#
#   ./update.sh            — проверить, собрать, установить, закоммитить
#   ./update.sh check      — только проверить наличие новой версии
#   ./update.sh notify     — тихая проверка с уведомлением на рабочий стол (для systemd-таймера)
#   ./update.sh rollback   — показать локальные сборки для отката
#   ./update.sh rollback <версия> — установить указанную локальную сборку
#
# Код возврата 11 у check и update — новая версия опубликована битой (см. release_ok).

set -euo pipefail
cd "$(dirname "$0")"

FEED="https://desktop.app.music.yandex.net/stable/latest-linux.yml"
PKGNAME="yandex-music-system-electron"

# Защита от битых релизов, общая для update.sh в yandex-music-pkg, max-bin и claude-desktop.
# 20.10.2026 Яндекс опубликовал Яндекс Музыку 5.124.1, чей deb весил 96 байт: в ar-архиве лежал только пустой индекс «__.SYMDEF SORTED», без control.tar и data.tar. Фид указывал именно этот размер и контрольную сумму именно этого файла, поэтому проверка суммы релиз пропустила, а сборка упала на распаковке.
# Настоящие сборки всех трёх программ весят десятки и сотни мегабайт, поэтому размер пакета из метаданных источника сверяется с порогом в 1 МиБ. Релиз меньше порога или без указанного размера считается битым: check и update сообщают о нём и выходят с кодом 11, notify молчит до тех пор, пока издатель не перевыпустит пакет.
MIN_SIZE=$((1024 * 1024))

release_ok() {
    [[ "${1:-}" =~ ^[0-9]+$ ]] && (( $1 >= MIN_SIZE ))
}

broken_release() {
    echo "Версия $1 опубликована битой (размер пакета: ${2:-не указан} байт), обновление пропущено." >&2
    exit 11
}

latest_entry() {
    # Выводит «версия размер». В фиде версия иногда содержит дефис (пререлизный суффикс) — приводим к виду, который использует PKGBUILD. Размер есть только у элементов списка files, у верхнего уровня фида его нет.
    curl -fsSL "$FEED" | awk '
        /^version:/ { gsub(/-/, ".", $2); v = $2 }
        /^[[:space:]]+size:/ && s == "" { s = $2 }
        END { if (v != "") print v, s }'
}

current_version() {
    # Истина — установленная версия; если пакет не установлен, берём PKGBUILD.
    local q
    if q=$(pacman -Q "$PKGNAME" 2>/dev/null); then
        printf '%s\n' "$q" | awk '{sub(/-[0-9]+$/,"",$2); print $2}'
    else
        grep -oP '(?<=^pkgver=).*' PKGBUILD
    fi
}

cmd="${1:-update}"

case "$cmd" in
check)
    cur=$(current_version); entry=$(latest_entry)
    read -r new size <<<"$entry"
    echo "Установленная версия: $cur"
    echo "Версия в фиде:        $new"
    if [[ $(vercmp "$new" "$cur") -gt 0 ]]; then
        release_ok "$size" || broken_release "$new" "$size"
        echo "Доступно обновление. Запустите: ./update.sh"
        exit 10
    else
        echo "Обновление не требуется."
    fi
    ;;

notify)
    # Для systemd-таймера: молча выйти, если сеть так и не появилась,
    # показать уведомление только если вышла новая версия.
    # Persistent=true запускает пропущенную проверку сразу после загрузки,
    # когда сети может ещё не быть: повторять попытки до 5 минут.
    cur=$(current_version)
    entry=""
    for _ in {1..10}; do
        entry=$(latest_entry 2>/dev/null) && [[ -n "$entry" ]] && break
        entry=""
        sleep 30
    done
    [[ -n "$entry" ]] || exit 0
    read -r new size <<<"$entry"
    # О битом релизе не уведомляем: обновиться на него всё равно нельзя.
    if [[ $(vercmp "$new" "$cur") -gt 0 ]] && release_ok "$size"; then
        notify-send -a "Яндекс Музыка" -i yandex-music -u critical \
            "Вышло обновление Яндекс Музыки $new" \
            "Установлена версия $cur. Для обновления запустите: $(pwd)/update.sh"
    fi
    ;;

update)
    # Забрать коммиты с других машин, чтобы не создавать дублирующий «Update <версия>».
    git pull --ff-only
    cur=$(current_version); entry=$(latest_entry)
    read -r new size <<<"$entry"
    if [[ $(vercmp "$new" "$cur") -le 0 ]]; then
        echo "Уже актуальная версия: $cur"
        exit 0
    fi
    release_ok "$size" || broken_release "$new" "$size"
    echo "Обновление $cur -> $new"
    # Версию в PKGBUILD правит сам makepkg: pkgver() читает номер из фида.
    # Новая версия — первая её сборка, поэтому pkgrel сбрасывается в 1.
    # Если PKGBUILD этой версии уже подтянут с другой машины, pkgrel не трогаем.
    if [[ $(grep -oP '(?<=^pkgver=).*' PKGBUILD) != "$new" ]]; then
        sed -i 's/^pkgrel=.*/pkgrel=1/' PKGBUILD
    fi
    makepkg -si
    got=$(current_version)
    if [[ "$got" != "$new" ]]; then
        echo "Установлена версия $got, ожидалась $new." >&2
        exit 1
    fi
    if ! git diff --quiet -- PKGBUILD; then
        git add PKGBUILD
        git commit -m "Update $new"
    fi
    # Отправить коммит сразу, чтобы другие машины подтянули его, а не создали свой.
    git push -q || echo "Предупреждение: git push не удался, выполните его вручную." >&2
    echo "Готово: установлена версия $new."
    ;;

rollback)
    ver="${2:-}"
    if [[ -z "$ver" ]]; then
        echo "Локально доступные сборки:"
        ls -1 "${PKGNAME}"-*.pkg.tar.zst 2>/dev/null \
            | sed -E "s/^${PKGNAME}-(.+)-[0-9]+-x86_64.*/  \1/" \
            || echo "  (нет собранных пакетов)"
        echo
        echo "Откат: ./update.sh rollback <версия>"
        echo "Пересобрать старую версию нельзя: фид отдаёт только latest."
        exit 0
    fi
    pkgfile=$(ls -1 "${PKGNAME}-${ver}"-*-x86_64.pkg.tar.zst 2>/dev/null | sort -V | tail -1) || true
    if [[ -z "${pkgfile:-}" ]]; then
        echo "Сборка версии $ver не найдена." >&2
        exit 1
    fi
    sudo pacman -U "$pkgfile"
    ;;

*)
    echo "Использование: $0 [check|notify|update|rollback [версия]]" >&2
    exit 2
    ;;
esac
