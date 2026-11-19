# swadb sidecar — self-contained binary

PyInstaller onedir bundle of the swadb server for embedding into desktop
apps (fable-ide's Theia electron app bundles it under
`resources/swadb-sidecar/`). No Python required on the user's machine;
the embedding model (all-MiniLM-L6-v2) ships inside, so memory works
fully offline out of the box.

## Contract (consumed by fable-ide)

- Release asset name: `swadb-sidecar-v<version>-<os>-<arch>.tar.gz`
  (`.zip` on Windows). `<os>` uses Node `process.platform` values
  (`linux` | `darwin` | `win32`); `<arch>` is `x64` | `arm64`.
- Archive contains one top-level dir `swadb-sidecar/` with the launcher
  `swadb-sidecar/swadb` (`swadb.exe` on Windows). The bundled model cache
  lives at `swadb-sidecar/_internal/hf-cache/hub`.
- Behavior: `<bin> --db <path> init` exits 0; `<bin> --db <path> serve
  --host H --port P` serves the HTTP API (default 8420) and the embedded
  MCP SSE server (8421); `memory add` / `memory search` work offline.

## Build

```bash
# Linux: install CPU-only torch FIRST — the default PyPI wheel bundles
# the CUDA stack (~2.5 GB of nvidia_* libs), which collect_all("torch")
# would drag into the bundle and blow past GitHub's 2 GiB release-asset
# limit. (Mac wheels are CPU/MPS-only; Windows PyPI wheels are CPU.)
pip install torch --index-url https://download.pytorch.org/whl/cpu

pip install -e ..            # swadb + runtime deps in the build env
bash build-sidecar.sh        # prepares hf cache, runs PyInstaller, tars
```

This repository runs no GitHub Actions, so nothing builds or uploads the
sidecar on release tags. Run the steps above from `sidecar/` on each
release platform (PyInstaller does not cross-compile). The removed
`sidecar.yml` covered linux-x64 (built on Ubuntu 22.04 for an old glibc
baseline), darwin-arm64, darwin-x64, and win32-x64.

- **Before `build-sidecar.sh`**: `python -m pip check` must pass, and
  `python -c "import swadb; print(swadb.__version__)"` must equal the
  release tag without its leading `v`.
- **Intel Mac (darwin-x64)**: replace `pip install -e ..` with
  `pip install -e .. -c constraints-macos-x86_64.txt` (the legacy ML
  stack; PyTorch ships no newer Intel-Mac wheels).
- **Windows (git-bash)**: the contract asks for a `.zip`, but
  `build-sidecar.sh` writes a `.tar.gz`. Zip the bundle instead:
  `(cd dist && 7z a ../swadb-sidecar-v<version>-win32-x64.zip swadb-sidecar)`.

Hermetic smoke test of the finished bundle, with every online and cache
path poisoned (the bundle must be self-sufficient):

```bash
(
  set -e
  export HF_HUB_OFFLINE=1 HF_HOME=/nonexistent TRANSFORMERS_OFFLINE=1 SWADB_EMBED_DEVICE=cpu
  BIN=dist/swadb-sidecar/swadb; [ -x "$BIN" ] || BIN=dist/swadb-sidecar/swadb.exe
  test -f dist/swadb-sidecar/_internal/swadb/static/index.html
  test -d dist/swadb-sidecar/_internal/hf-cache/hub
  D=$(mktemp -d)
  "$BIN" --db "$D/t.db" init
  "$BIN" --db "$D/t.db" memory add "hermetic smoke test observation"
  "$BIN" --db "$D/t.db" memory search "hermetic" | grep -qi "smoke"
  "$BIN" --db "$D/t.db" serve --host 127.0.0.1 --port 18420 &
  SERVER_PID=$!
  for _ in $(seq 1 30); do curl -sf http://127.0.0.1:18420/api/health && break; sleep 1; done
  curl -sf http://127.0.0.1:18420/api/health | grep -q '"status": "ok"'
  kill $SERVER_PID
  echo "smoke test passed"
)
```

GitHub caps release assets at 2 GiB; the removed workflow rejected any
archive over 1900 MB (usually a CUDA torch in the bundle). Attach each
platform's archive (`.tar.gz`, or `.zip` on Windows) to the release
created in [Checks and Releases](../docs/DEVELOPMENT.md#checks-and-releases):

```bash
gh release upload vX.Y.Z swadb-sidecar-v<version>-<os>-<arch>.tar.gz --clobber
```

Builds are unsigned in v1: macOS Gatekeeper quarantines downloaded
unsigned binaries (`xattr -dr com.apple.quarantine` or distribution
inside a signed app bundle sidesteps it).

## Scope decisions (v1)

- **onedir, not onefile** — onefile would re-extract >1 GB (torch) on
  every cold start.
- **hnswlib: bundled** (built with `HNSWLIB_NO_NATIVE=1` for portability)
  — ANN acceleration works out of the box.
- **sqlcipher3, pdfminer.six: omitted** — at-rest encryption and PDF
  ingestion remain pip-install-only features.
- **Reranker cross-encoder: omitted** (~90 MB, `reranker_enabled`
  defaults false, retrieval degrades gracefully). Enabling the reranker
  against the sidecar offline is a no-op.
- **No sklearn/scipy exclusion** — sentence-transformers pulls them in;
  excluding (~190 MB) is untested against frozen encode paths. Revisit.
- **Python skills in packaged mode** need a system `python3`/`python` on
  PATH (`swadb/pyexec.py`); without one they return a readable error.
  Bash skills are unaffected.
- **`SWADB_EMBED_DEVICE`** forces the torch device for the embedding
  model (unset = auto). The smoke test above sets `cpu`, as the removed
  CI did everywhere: GitHub's hosted arm64 macOS runners expose an MPS
  pool so small that loading the model OOMs. End users on real Macs get
  MPS/auto by default.

## Size / startup (Linux x64, CPU torch)

~1.1–1.3 GB unpacked, ~350–450 MB tar.gz (torch dominates; the model
cache is ~88 MB). Cold start 2–6 s (torch import). A future
onnxruntime-based embedding path could drop ~700 MB.
