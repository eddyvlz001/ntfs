#!/usr/bin/env bash
set -euo pipefail

# Installs macFUSE (legacy kext path, Intel only) + ntfs-3g.
# On Apple Silicon, macFUSE falls back to a System Extension and loses the
# speed advantage this project is built around — this app targets Intel Macs.

if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew no está instalado. Instálalo desde https://brew.sh primero." >&2
    exit 1
fi

if [[ "$(uname -m)" != "x86_64" ]]; then
    echo "Advertencia: este Mac no es Intel (x86_64). macFUSE usará System Extension" >&2
    echo "en lugar del kext clásico, y el rendimiento será menor al esperado." >&2
fi

echo "Instalando macFUSE..."
brew install --cask macfuse

echo "Instalando ntfs-3g..."
brew install gromgit/fuse/ntfs-3g-mac

cat <<'EOF'

Siguiente paso manual (Apple lo exige para cualquier kext/extensión de sistema):
  1. Abre Ajustes del Sistema > Privacidad y Seguridad.
  2. Permite el software del desarrollador "Benjamin Fleischer" (macFUSE).
  3. Reinicia si el sistema lo solicita.

Después de esto, compila y abre NTFSMate.app.
EOF
