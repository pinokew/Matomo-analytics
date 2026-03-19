#!/usr/bin/env bash
set -euo pipefail

COMPOSE_FILE="${1:-docker-compose.yaml}"

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "ERROR: compose file not found: $COMPOSE_FILE"
  exit 1
fi

if grep -En '^\s*ports:\s*$' "$COMPOSE_FILE" >/dev/null; then
  echo "ERROR: ports section detected in $COMPOSE_FILE. Public port publishing is not allowed."
  grep -En '^\s*ports:\s*$|^\s*-\s*"?[0-9.:]+:[0-9]+"?\s*$' "$COMPOSE_FILE" || true
  exit 1
fi

echo "Ports policy check passed"
