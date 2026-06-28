# Maintainer: elph
#
# Сборка Яндекс Музыки поверх СИСТЕМНОГО electron42 (без встроенного Electron).
# Источник — официальный deb Яндекса. Версия определяется динамически по фиду
# latest-linux.yml: на каждой пересборке makepkg тянет актуальный deb, pkgver()
# подхватывает его номер, пакет обновляется штатно через pacman.
#
# Запуск — тонкая обёртка `electron42 /opt/yandex-music/app.asar` (нативный
# Wayland включается автоопределением, без явного флага).

pkgname=yandex-music
pkgver=5.108.3
pkgrel=1
pkgdesc="Яндекс Музыка на системном Electron"
arch=('x86_64')
url="https://music.yandex.ru/"
license=('custom')
depends=('electron42')
makedepends=('curl' 'libarchive' 'openssl' 'coreutils')
options=('!strip' '!emptydirs')
source=()

_feed="https://desktop.app.music.yandex.net/stable/latest-linux.yml"
_base="https://desktop.app.music.yandex.net/stable"

pkgver() {
    # prepare() уже записал актуальную версию; читаем её.
    cat "$srcdir/.pkgver" 2>/dev/null || echo "$pkgver"
}

prepare() {
    local feed ver path sha url got
    feed=$(curl -fsSL "$_feed")

    ver=$(printf '%s\n'  "$feed" | awk '/^version:/{print $2; exit}')
    path=$(printf '%s\n' "$feed" | awk '/^path:/{print $2; exit}')
    # Верхнеуровневый sha512 (folded-скаляр ">-", значение на следующей строке).
    sha=$(printf '%s\n'  "$feed" | awk '/^sha512: >-/{getline v; sub(/^[[:space:]]+/,"",v); print v; exit}')

    if [ -z "$ver" ] || [ -z "$path" ] || [ -z "$sha" ]; then
        echo "Не удалось разобрать фид latest-linux.yml"
        return 1
    fi

    ver=${ver//-/.}
    printf '%s\n' "$ver" > "$srcdir/.pkgver"

    url="$_base/$path"
    if [ ! -f "$srcdir/$path" ]; then
        echo "Скачивание $path ..."
        curl -fL "$url" -o "$srcdir/$path"
    fi

    # Проверка целостности по контрольной сумме из самого фида (base64-sha512).
    got=$(openssl dgst -sha512 -binary "$srcdir/$path" | base64 -w0)
    if [ "$got" != "$sha" ]; then
        echo "Контрольная сумма не совпала:"
        echo "  ожидалось: $sha"
        echo "  получено:  $got"
        return 1
    fi

    # Распаковка deb (ar -> data.tar.*) средствами libarchive, без alien/dpkg.
    rm -rf "$srcdir/extract"
    mkdir -p "$srcdir/extract"
    bsdtar -C "$srcdir/extract" -xf "$srcdir/$path"
    bsdtar -C "$srcdir/extract" -xf "$srcdir"/extract/data.tar.*
}

package() {
    local asar root s ic lic

    asar=$(find "$srcdir/extract" -type f -path '*/resources/app.asar' | head -1)
    if [ -z "$asar" ]; then
        echo "app.asar не найден в распакованном deb"
        return 1
    fi
    root=$(dirname "$(dirname "$asar")")   # каталог приложения (родитель resources/)

    install -dm755 "$pkgdir/opt/yandex-music"
    install -Dm644 "$asar" "$pkgdir/opt/yandex-music/app.asar"

    # Нативные модули, если они вынесены из asar, обязаны ехать рядом.
    if [ -d "$root/resources/app.asar.unpacked" ]; then
        cp -a "$root/resources/app.asar.unpacked" "$pkgdir/opt/yandex-music/"
    fi

    # Внешние ресурсы (icon.ico и icons/icon_*.png для трея). Код приложения
    # ищет их по process.resourcesPath/assets; при запуске обёрткой
    # resourcesPath = /opt/yandex-music, поэтому assets кладём именно сюда.
    if [ -d "$root/resources/assets" ]; then
        cp -a "$root/resources/assets" "$pkgdir/opt/yandex-music/"
    fi

    # Обёртка: системный Electron, без флага Wayland (автоопределение).
    install -Dm755 /dev/stdin "$pkgdir/usr/bin/yandex-music" <<'EOF'
#!/bin/sh
exec electron42 /opt/yandex-music/app.asar "$@"
EOF

    # Собственный ярлык — полностью под контролем.
    install -Dm644 /dev/stdin "$pkgdir/usr/share/applications/yandex-music.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Yandex Music
Name[ru]=Яндекс Музыка
GenericName=Music Player
GenericName[ru]=Музыкальный проигрыватель
Comment=Personal recommendations, mixes for any occasion and the latest musical releases
Comment[ru]=Персональные рекомендации, миксы на любой случай и последние музыкальные новинки
Exec=yandex-music %U
Icon=yandex-music
Terminal=false
Categories=AudioVideo;Audio;Player;
MimeType=x-scheme-handler/yandexmusic;
StartupWMClass=YandexMusic
Keywords=music;yandex;музыка;яндекс;
EOF

    # Иконки — из ассетов приложения, под именем yandex-music.
    for s in 16 22 24 32 48; do
        ic="$root/resources/assets/icons/icon_${s}x${s}.png"
        [ -f "$ic" ] && install -Dm644 "$ic" \
            "$pkgdir/usr/share/icons/hicolor/${s}x${s}/apps/yandex-music.png"
    done

    lic=$(find "$srcdir/extract" -maxdepth 5 -name 'LICENSE.electron.txt' | head -1)
    [ -n "$lic" ] && install -Dm644 "$lic" \
        "$pkgdir/usr/share/licenses/yandex-music/LICENSE.electron.txt"
}
