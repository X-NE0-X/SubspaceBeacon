#!/bin/bash
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
PY="$(command -v python3 || true)"
if [ -z "$PY" ]; then
  echo "python3 is required for LAN discovery." >&2
  exit 2
fi
exec "$PY" "$ROOT/discover.py" "$@"
