#!/usr/bin/env bash
# Build the self-contained swadb sidecar (Linux/macOS). Run it once on
# each release platform: PyInstaller does not cross-compile.
#
# Prereqs: a Python env with swadb installed (pip install -e ..) and its
# runtime deps present. Produces:
#   dist/swadb-sidecar/                      (onedir bundle)
#   swadb-sidecar-v<version>-<os>-<arch>.tar.gz
set -euo pipefail
cd "$(dirname "$0")"

python -m pip install --quiet pyinstaller pyinstaller-hooks-contrib
HNSWLIB_NO_NATIVE=1 python -m pip install --quiet --no-cache-dir "hnswlib>=0.8.0"

python prepare_hf_cache.py
python -m PyInstaller --clean --noconfirm swadb-sidecar.spec

VERSION=$(python -c 'import swadb; print(swadb.__version__)')
case "$(uname -s)" in
    Linux)  OS=linux ;;
    Darwin) OS=darwin ;;
    *)      OS=win32 ;;   # git-bash on Windows
esac
case "$(uname -m)" in
    arm64|aarch64) ARCH=arm64 ;;
    *)             ARCH=x64 ;;
esac
ARCHIVE="swadb-sidecar-v${VERSION}-${OS}-${ARCH}.tar.gz"

tar -C dist -czf "$ARCHIVE" swadb-sidecar
du -sh dist/swadb-sidecar "$ARCHIVE"
echo "built $ARCHIVE"
