#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${1:-.env}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE not found"
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

common_vars=(
  MATOMO_IMAGE
  MARIADB_IMAGE
  CRON_IMAGE
  DB_ROOT_PASS
  DB_NAME
  DB_USER
  DB_PASS
  DB_PREFIX
  VOL_DB_PATH
  VOL_MATOMO_DATA
  MATOMO_HOST
  BACKUP_DIR
  BACKUP_RETENTION_DAYS
  DISK_WARN_THRESHOLD
  DISK_CRIT_THRESHOLD
  MATOMO_API_TOKEN
  RCLONE_REMOTE
  RCLONE_DEST_PATH
)

required_vars=("${common_vars[@]}")

missing=0

for var_name in "${required_vars[@]}"; do
  value="${!var_name:-}"
  if [[ -z "${value// }" ]]; then
    echo "ERROR: missing or empty variable: ${var_name}"
    missing=1
    continue
  fi

  if [[ "$value" == *"CHANGE_ME"* ]]; then
    echo "ERROR: placeholder detected for ${var_name}"
    missing=1
  fi

done

for numeric_var in BACKUP_RETENTION_DAYS DISK_WARN_THRESHOLD DISK_CRIT_THRESHOLD; do
  if ! [[ "${!numeric_var:-}" =~ ^[0-9]+$ ]]; then
    echo "ERROR: ${numeric_var} must be an integer"
    missing=1
  fi
done

if [[ "${BACKUP_RETENTION_DAYS:-0}" -lt 1 ]]; then
  echo "ERROR: BACKUP_RETENTION_DAYS must be >= 1"
  missing=1
fi

if [[ "${DISK_WARN_THRESHOLD:-0}" -ge "${DISK_CRIT_THRESHOLD:-0}" ]]; then
  echo "ERROR: DISK_WARN_THRESHOLD must be less than DISK_CRIT_THRESHOLD"
  missing=1
fi

if [[ "$missing" -ne 0 ]]; then
  echo "Environment validation failed"
  exit 1
fi

echo "Environment validation passed"
