#!/bin/bash
# Builds dist/PokeNX2iOS.app: the SwiftUI tool, a source snapshot of nxnative at the branch with our changes
# (engine.tar.gz, from git archive: only committed files, no game data), and the Let's Go profile and mods (Resources/letsgo).
#
#   scripts/make_app.sh [path to the nxnative repository] [branch]
#   defaults: ../nxnative beside this tool's folder, branch unificado2
#
# REFRESH_LETSGO="<path to the Pokemon Lets GO folder>" also copies the current game.tsv and mods from there into Resources/letsgo first.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
NXNATIVE="${1:-$HERE/../nxnative}"
BRANCH="${2:-unificado2}"
APP="$HERE/dist/PokeNX2iOS.app"

[ -d "$NXNATIVE/.git" ] || { echo "No encuentro el repositorio nxnative en $NXNATIVE" >&2; exit 1; }
COMMIT="$(git -C "$NXNATIVE" rev-parse --verify "$BRANCH^{commit}")"

if [ -n "$(git -C "$NXNATIVE" status --porcelain --untracked-files=no)" ] && [ "$(git -C "$NXNATIVE" rev-parse --abbrev-ref HEAD)" = "$BRANCH" ]; then
    echo "Aviso: $BRANCH tiene cambios sin commit en $NXNATIVE; la app solo lleva lo que está en commit ($COMMIT)." >&2
fi

if [ -n "${REFRESH_LETSGO:-}" ]; then
    echo "Copiando perfil y mods desde $REFRESH_LETSGO"
    L="$HERE/Resources/letsgo"
    cp "$REFRESH_LETSGO/010003F003A34000_build/profile/010003F003A34000/game.tsv" "$L/profile/010003F003A34000/game.tsv"
    for m in pantalla_completa pwildbattles2; do
        rm -rf "$L/mod/$m"; mkdir -p "$L/mod/$m/exefs"
        cp "$REFRESH_LETSGO/mod/$m/"*.txt "$L/mod/$m/"
        cp "$REFRESH_LETSGO/mod/$m/exefs/"*.pchtxt "$L/mod/$m/exefs/"
    done
fi

echo "Compilando la app…"
# the build folder's path (it holds the user name) is mapped away so it is not written into the executable
SWIFT_FLAGS=(-c release --package-path "$HERE" -Xswiftc -file-prefix-map -Xswiftc "$HERE=.")
swift build "${SWIFT_FLAGS[@]}"
BIN="$(swift build "${SWIFT_FLAGS[@]}" --show-bin-path)/PokeNX2iOS"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PokeNX2iOS"
strip -S -x "$APP/Contents/MacOS/PokeNX2iOS"   # debug map entries name the object files by their full path
cp "$HERE/Resources/Info.plist" "$APP/Contents/Info.plist"
[ -f "$HERE/Resources/AppIcon.icns" ] && cp "$HERE/Resources/AppIcon.icns" "$APP/Contents/Resources/"
cp -R "$HERE/Resources/letsgo" "$APP/Contents/Resources/letsgo"
find "$APP/Contents/Resources/letsgo" -name '.DS_Store' -delete

echo "Empaquetando el motor nxnative $BRANCH ($COMMIT)…"
# Progress notes of other ports are left out (personal notes, not needed to build).
git -C "$NXNATIVE" archive --format=tar "$COMMIT" -- . ":(exclude)docs/*-progress.md" | gzip -6 > "$APP/Contents/Resources/engine.tar.gz"
echo "$COMMIT" > "$APP/Contents/Resources/engine.version"

# nothing in the app may name this Mac's user (home folder path or user name)
ME="$(id -un)"
if grep -rqaiF -e "$HOME" -e "$ME" "$APP" || tar -xzOf "$APP/Contents/Resources/engine.tar.gz" | grep -qaiF -e "$HOME" -e "$ME"; then
    echo "Error: la app contiene $HOME o el usuario $ME" >&2; exit 1
fi

codesign --force --deep --sign - "$APP"
echo "Listo: $APP ($(du -sh "$APP" | cut -f1))"
