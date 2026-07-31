#!/usr/bin/env bash
# Обновление пакета yandex-music-system-electron из официального фида Яндекса.
#
#   ./update.sh            — проверить, собрать, установить, закоммитить
#   ./update.sh check      — только проверить наличие новой версии
#   ./update.sh notify     — тихая проверка с уведомлением на рабочий стол (для systemd-таймера)
#   ./update.sh rollback   — показать локальные сборки для отката
#   ./update.sh rollback <версия> — установить указанную локальную сборку

set -euo pipefail
cd "$(dirname "$0")"

FEED="https://desktop.app.music.yandex.net/stable/latest-linux.yml"
PKGNAME="yandex-music-system-electron"

latest_version() {
    # В фиде версия иногда содержит дефис (пререлизный суффикс) — приводим к
    # виду, который использует PKGBUILD.
    curl -fsSL "$FEED" | awk '/^version:/{gsub(/-/,".",$2); print $2; exit}'
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
    cur=$(current_version); new=$(latest_version)
    echo "Установленная версия: $cur"
    echo "Версия в фиде:        $new"
    if [[ $(vercmp "$new" "$cur") -gt 0 ]]; then
        echo "Доступно обновление. Запустите: ./update.sh"
        exit 10
    else
        echo "Обновление не требуется."
    fi
    ;;

notify)
    # Для systemd-таймера: молча выйти при недоступности сети,
    # показать уведомление только если вышла новая версия.
    cur=$(current_version)
    new=$(latest_version) || exit 0
    [[ -n "$new" ]] || exit 0
    if [[ $(vercmp "$new" "$cur") -gt 0 ]]; then
        notify-send -a "Яндекс Музыка" -i yandex-music -u critical \
            "Вышло обновление Яндекс Музыки $new" \
            "Установлена версия $cur. Для обновления запустите: $(pwd)/update.sh"
    fi
    ;;

update)
    cur=$(current_version); new=$(latest_version)
    if [[ $(vercmp "$new" "$cur") -le 0 ]]; then
        echo "Уже актуальная версия: $cur"
        exit 0
    fi
    echo "Обновление $cur -> $new"
    # Версию в PKGBUILD правит сам makepkg: pkgver() читает номер из фида.
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
    pkgfile=$(ls -1 "${PKGNAME}-${ver}"-*-x86_64.pkg.tar.zst 2>/dev/null | head -1) || true
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
