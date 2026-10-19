#!/usr/bin/env bash
set -euo pipefail

echo "^($(sed 's/\./\\./g' | paste -sd'|' -))\$"
