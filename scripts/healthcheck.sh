#!/usr/bin/env bash
set -euo pipefail
base="${1:-http://127.0.0.1:8000}"
curl --fail --silent --show-error --connect-timeout 3 --max-time 8 "${base%/}/readyz"
printf '\n'
