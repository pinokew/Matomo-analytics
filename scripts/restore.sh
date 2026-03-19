#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${ENV_FILE:-.env}"
FORCE=false
BACKUP_FILE=""

usage() {
  echo "Usage: $0 [--force] <backup-file.sql.gz|backup-file.sql>"
}

require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $cmd"
    exit 1
  fi
}

for arg in "$@"; do
  case "$arg" in
    --force)
      FORCE=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -z "$BACKUP_FILE" ]]; then
        BACKUP_FILE="$arg"
      else
        echo "ERROR: unexpected argument: $arg"
        usage
        exit 1
      fi
      ;;
  esac
done

if [[ -z "$BACKUP_FILE" ]]; then
  usage
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: env file not found: $ENV_FILE"
  exit 1
fi

if [[ ! -f "$BACKUP_FILE" ]]; then
  echo "ERROR: backup file not found: $BACKUP_FILE"
  exit 1
fi

source "$ENV_FILE"

required_vars=(
  DB_NAME
  DB_ROOT_PASS
)

for var_name in "${required_vars[@]}"; do
  if [[ -z "${!var_name:-}" ]]; then
    echo "ERROR: required variable is empty: $var_name"
    exit 1
  fi
done

require_command docker
require_command gzip

if ! docker compose ps matomo-db >/dev/null 2>&1; then
  echo "ERROR: could not access service 'matomo-db' via docker compose"
  echo "Hint: run this script from repository root where docker-compose.yaml and .env are available"
  exit 1
fi

if [[ "$FORCE" != true ]]; then
  if [[ ! -t 0 ]]; then
    echo "ERROR: non-interactive mode requires --force"
    exit 1
  fi

  echo "WARNING: restore will overwrite data in DB '$DB_NAME'."
  read -r -p "Type YES to continue: " confirm
  if [[ "$confirm" != "YES" ]]; then
    echo "[restore] canceled"
    exit 1
  fi
fi

echo "[restore] ENV loaded from: $ENV_FILE"
echo "[restore] source backup: $BACKUP_FILE"
echo "[restore] target database: $DB_NAME"

echo "[restore] importing dump..."
if [[ "$BACKUP_FILE" == *.sql.gz ]]; then
  gzip -dc "$BACKUP_FILE" | docker compose exec -T -e MYSQL_PWD="$DB_ROOT_PASS" matomo-db mariadb -uroot "$DB_NAME"
elif [[ "$BACKUP_FILE" == *.sql ]]; then
  cat "$BACKUP_FILE" | docker compose exec -T -e MYSQL_PWD="$DB_ROOT_PASS" matomo-db mariadb -uroot "$DB_NAME"
else
  echo "ERROR: unsupported backup format. Use .sql or .sql.gz"
  exit 1
fi

echo "[restore] running post-restore sanity query..."
docker compose exec -T -e MYSQL_PWD="$DB_ROOT_PASS" matomo-db mariadb -uroot -e "USE ${DB_NAME}; SHOW TABLES;" >/dev/null

echo "[restore] completed successfully"
