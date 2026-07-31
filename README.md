# Yandex Music on system Electron

A `PKGBUILD` for Arch/Manjaro: Yandex Music running on the **system `electron42`**
instead of the Electron bundled in the official deb. The build is clean, tracked
by `pacman`, runs under native Wayland and has a proper window shadow.

The package is named **`yandex-music-system-electron`** and is independent of the
AUR package `yandex-music` it once derived from: AUR helpers will not offer
"updates" for it. Thanks to `provides`/`conflicts` it cleanly replaces an
installed `yandex-music` and satisfies dependencies on it.

> Russian version: [`ПРОЧТИ.md`](ПРОЧТИ.md).

## What it is based on

- **Application code** — the official Yandex deb; only `app.asar` is taken from it.
- **Runtime** — the system `electron42` (the `extra` repo). The Electron bundled
  in the deb is not used: it is older and, in a Wayland session, draws no shadow
  for a frameless window (CSD shadows for frameless windows only arrived in
  Electron 41). On `electron42` the shadow is present.
- **Unpacking** — `bsdtar` (libarchive), without `alien`, `dpkg` or `rpm`.

## Package layout and purpose of each part

`PKGBUILD` builds the package as follows:

- **Version is resolved dynamically from the `latest-linux.yml` feed.** On every
  rebuild `makepkg` fetches the current deb and `pkgver()` picks up its number —
  no manual version editing needed.
- **Integrity check** — sha512 from the same feed.
- **`/opt/yandex-music/app.asar`** (and `app.asar.unpacked`, if present) — the
  application code.
- **`/opt/yandex-music/assets`** (`icon.ico`, `icons/icon_*.png`) — tray icons;
  the app looks them up at `process.resourcesPath/assets`.
- **`/opt/yandex-music/package.json`** — turns the directory into an application
  so Electron natively reads from it:
  - the **name** `YandexMusic` → the `~/.config/YandexMusic` profile (cookies and
    session);
  - the **version** → a valid semver (the app checks it at startup).
- **`/opt/yandex-music/launcher.js`** (the application directory's `main`) — a thin
  shim. Before loading `app.asar` it overrides two paths:
  - `process.resourcesPath` → `/opt/yandex-music` — so the tray icons are found
    (otherwise the path points at Electron's own directory);
  - `app.getAppPath()` → `app.asar` — so the web content in `app/` inside the asar
    is found.
- **`/usr/bin/yandex-music`** — a wrapper that runs `electron42 /opt/yandex-music`.
  No Wayland flag is needed: native mode is enabled by autodetection.
- **The `.desktop` entry and the application icons** under `hicolor`.

## What works

- A clean build on the system Electron, tracked by `pacman` (≈300 MB smaller — the
  duplicated bundled Electron is gone).
- Native Wayland and the window shadow.
- The system tray icon and its context menu.
- Playback (stream through ALSA, verified at 176.4 kHz).
- MPRIS — control from the media player in the system tray.

## Install

```
cd ~/projects/yandex-music-pkg   # the directory with PKGBUILD
makepkg -si
```

## Update

Everything is done by `./update.sh`:

- `./update.sh check` — compare the installed version against the feed. Exit
  code 10 means an update is available.
- `./update.sh` — if a new version is out: `makepkg -si` (the fresh deb comes
  from the feed, `makepkg` itself rewrites `pkgver` in `PKGBUILD`), verify the
  installed version, commit `Update <version>`.
- `./update.sh rollback [version]` — roll back to a previously built local
  package. Built `.pkg.tar.zst` files are deliberately kept in the directory:
  an older version cannot be rebuilt, the feed only serves the latest one.
- `./update.sh notify` — a quiet check with a `notify-send` desktop
  notification; exits silently when the network is unavailable.

### Update notifications

A user systemd timer runs the check daily (units in `~/.config/systemd/user/`):

```
systemctl --user enable --now yandex-music-update-check.timer
```

When a new version is released a desktop notification shows up; then just enter
the directory and run `./update.sh`.

> The build is always "latest": the feed points at the newest version, so this
> `PKGBUILD` cannot build a specific older version.

---

Debugging history, the reasoning behind the decisions, and the pitfalls (window
shadow, the tray-icon path, profile and session, version and semver, file
conflicts on install) are in [`ОТЛАДКА.md`](ОТЛАДКА.md) (in Russian).
