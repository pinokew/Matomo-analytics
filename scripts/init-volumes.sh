#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${1:-.env}"
DRY_RUN="${2:-}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE not found"
  exit 1
fi

set -a
. "$ENV_FILE"
set +a

required_vars=(
  VOL_DB_PATH
  VOL_MATOMO_DATA
  BACKUP_DIR
)

for var_name in "${required_vars[@]}"; do
  value="${!var_name:-}"
  if [[ -z "$value" ]]; then
    echo "ERROR: missing variable in $ENV_FILE: $var_name"
    exit 1
  fi
done

guard_path() {
  local path="$1"
  if [[ "$path" == "/" || "$path" == "." || "$path" == ".." ]]; then
    echo "ERROR: unsafe path: $path"
    exit 1
  fi
}

run_cmd() {
  if [[ "$DRY_RUN" == "--dry-run" ]]; then
    echo "[dry-run] $*"
  else
    eval "$*"
  fi
}

ensure_dir() {
  local dir_path="$1"
  if [[ "$DRY_RUN" == "--dry-run" ]]; then
    echo "[dry-run] mkdir -p \"$dir_path\""
    return
  fi

  if mkdir -p "$dir_path" 2>/dev/null; then
    return
  fi

  if command -v docker >/dev/null 2>&1; then
    local parent_dir
    local base_name
    parent_dir="$(dirname "$dir_path")"
    base_name="$(basename "$dir_path")"
    docker run --rm -v "$parent_dir":/host alpine:3.20 sh -c "mkdir -p /host/$base_name"
    return
  fi

  echo "ERROR: cannot create directory: $dir_path"
  exit 1
}

guard_path "$VOL_DB_PATH"
guard_path "$VOL_MATOMO_DATA"
guard_path "$BACKUP_DIR"

echo "Preparing directories from $ENV_FILE"
ensure_dir "$VOL_DB_PATH"
ensure_dir "$VOL_MATOMO_DATA"
ensure_dir "$BACKUP_DIR"

echo "Initializing Matomo writable directories"
ensure_dir "$VOL_MATOMO_DATA/tmp/assets"
ensure_dir "$VOL_MATOMO_DATA/tmp/cache"
ensure_dir "$VOL_MATOMO_DATA/tmp/logs"
ensure_dir "$VOL_MATOMO_DATA/tmp/tcpdf"
ensure_dir "$VOL_MATOMO_DATA/tmp/templates_c"

if command -v docker >/dev/null 2>&1; then
  echo "Applying ownership via ephemeral containers (no sudo required)"
  run_cmd "docker run --rm -v \"$VOL_MATOMO_DATA:/target\" alpine:3.20 sh -c 'chown -R 33:33 /target && chmod -R u=rwX,go=rX /target/tmp'"
  run_cmd "docker run --rm -v \"$VOL_DB_PATH:/target\" alpine:3.20 sh -c 'chown -R 999:999 /target && chmod -R u=rwX,g=rX,o= /target'"
else
  echo "WARNING: docker is not available, skipping ownership fix"
fi

run_cmd "chmod 750 \"$BACKUP_DIR\""

echo "Volume initialization completed"
