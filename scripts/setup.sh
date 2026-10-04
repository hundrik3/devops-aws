#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="${PORTFOLIO_TOOLS_DIR:-/workspace/tools}"
mkdir -p "$TOOLS/bin"
if [ ! -x "$TOOLS/bin/terraform" ] || ! "$TOOLS/bin/terraform" version -json | python3 -c 'import json,sys; assert json.load(sys.stdin)["terraform_version"] == "1.13.5"'; then
  python3 - "$TOOLS/bin" <<'PYTHON'
import hashlib, io, pathlib, sys, urllib.request, zipfile
version = '1.13.5'
filename = f'terraform_{version}_linux_amd64.zip'
base = f'https://releases.hashicorp.com/terraform/{version}/'
artifact = urllib.request.urlopen(base + filename, timeout=60).read()
sums = urllib.request.urlopen(base + f'terraform_{version}_SHA256SUMS', timeout=30).read().decode()
expected = next(line.split()[0] for line in sums.splitlines() if line.endswith(filename))
assert hashlib.sha256(artifact).hexdigest() == expected, 'Terraform checksum mismatch'
with zipfile.ZipFile(io.BytesIO(artifact)) as archive:
    target = pathlib.Path(archive.extract('terraform', sys.argv[1]))
    target.chmod(0o755)
PYTHON
fi
python3 -m venv "$ROOT/.venv"
"$ROOT/.venv/bin/python" -m pip install --disable-pip-version-check -r "$ROOT/requirements.lock"
"$TOOLS/bin/terraform" -chdir="$ROOT/infra" init -backend=false -input=false -lockfile=readonly
printf 'Activate: source %s/.venv/bin/activate; export PATH=%s/bin:$PATH
' "$ROOT" "$TOOLS"
