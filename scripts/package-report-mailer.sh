#!/usr/bin/env bash
# Build a deterministic, dependency-free ZIP for the Python report mailer.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="${REPORT_MAILER_ZIP:-${ROOT}/dist/report-mailer.zip}"

command -v python3 >/dev/null 2>&1 || {
  printf 'error: python3 is required\n' >&2
  exit 1
}

ROOT="${ROOT}" OUTPUT="${OUTPUT}" python3 - <<'PY'
import os
import pathlib
import zipfile

root = pathlib.Path(os.environ["ROOT"])
output = pathlib.Path(os.environ["OUTPUT"])
files = {
    root / "backend/app/__init__.py": "app/__init__.py",
    root / "backend/app/reports/__init__.py": "app/reports/__init__.py",
    root / "backend/app/reports/mailer_handler.py": "app/reports/mailer_handler.py",
}
for source in files:
    if not source.is_file():
        raise SystemExit(f"error: required mailer source is missing: {source}")

output.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
    for source, destination in sorted(files.items(), key=lambda item: item[1]):
        info = zipfile.ZipInfo(destination, date_time=(1980, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = 0o100644 << 16
        archive.writestr(info, source.read_bytes())
PY

printf '%s\n' "${OUTPUT}"
