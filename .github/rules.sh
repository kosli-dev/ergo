#!/bin/sh
set -eu
exec python3 "$(cd "$(dirname "$0")" && pwd)/rules.py" "$@"
