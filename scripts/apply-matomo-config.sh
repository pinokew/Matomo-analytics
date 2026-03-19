#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${1:-.env}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: env file not found: $ENV_FILE"
  exit 1
fi

set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $cmd"
    exit 1
  fi
}

require_command docker

if ! docker compose ps matomo-app >/dev/null 2>&1; then
  echo "ERROR: could not access service 'matomo-app' via docker compose"
  echo "Hint: run this script from repository root where docker-compose.yaml exists"
  exit 1
fi

MATOMO_CFG_FORCE_SSL="${MATOMO_CFG_FORCE_SSL:-1}"
MATOMO_CFG_LOGIN_ALLOW_SIGNUP="${MATOMO_CFG_LOGIN_ALLOW_SIGNUP:-0}"
MATOMO_CFG_LOGIN_ALLOW_RESET_PASSWORD="${MATOMO_CFG_LOGIN_ALLOW_RESET_PASSWORD:-0}"
MATOMO_CFG_ENABLE_BROWSER_ARCHIVING_TRIGGERING="${MATOMO_CFG_ENABLE_BROWSER_ARCHIVING_TRIGGERING:-0}"
MATOMO_CFG_IGNORE_VISITS_DO_NOT_TRACK="${MATOMO_CFG_IGNORE_VISITS_DO_NOT_TRACK:-1}"
MATOMO_CFG_ENABLE_LOGIN_OIDC="${MATOMO_CFG_ENABLE_LOGIN_OIDC:-1}"
MATOMO_CFG_OIDC_ALLOW_SIGNUP="${MATOMO_CFG_OIDC_ALLOW_SIGNUP:-0}"
MATOMO_CFG_OIDC_AUTO_LINKING="${MATOMO_CFG_OIDC_AUTO_LINKING:-1}"
MATOMO_CFG_OIDC_USERINFO_ID="${MATOMO_CFG_OIDC_USERINFO_ID:-email}"
MATOMO_CFG_SMTP_HOST="${MATOMO_CFG_SMTP_HOST:-smtp.office365.com}"
MATOMO_CFG_SMTP_PORT="${MATOMO_CFG_SMTP_PORT:-587}"
MATOMO_CFG_SMTP_TRANSPORT="${MATOMO_CFG_SMTP_TRANSPORT:-smtp}"
MATOMO_CFG_SMTP_TYPE="${MATOMO_CFG_SMTP_TYPE:-Login}"
MATOMO_CFG_SMTP_ENCRYPTION="${MATOMO_CFG_SMTP_ENCRYPTION:-tls}"
MATOMO_CFG_SMTP_FROM_NAME="${MATOMO_CFG_SMTP_FROM_NAME:-Matomo Analytics}"
MATOMO_CFG_SMTP_FROM_ADDRESS="${MATOMO_CFG_SMTP_FROM_ADDRESS:-${SMTP_USER:-}}"

sql_escape() {
  local value="$1"
  value="${value//\'/\'\'}"
  echo "$value"
}

set_plugin_setting() {
  local plugin_name="$1"
  local setting_name="$2"
  local setting_value="$3"

  local plugin_escaped
  local setting_escaped
  local value_escaped
  plugin_escaped="$(sql_escape "$plugin_name")"
  setting_escaped="$(sql_escape "$setting_name")"
  value_escaped="$(sql_escape "$setting_value")"

  echo "[matomo-config] setting plugin ${plugin_name}.${setting_name}=${setting_value}"
  docker compose exec -T matomo-db mariadb -u"${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" -e "
UPDATE ${DB_PREFIX}plugin_setting
SET setting_value = '${value_escaped}'
WHERE plugin_name = '${plugin_escaped}'
  AND setting_name = '${setting_escaped}'
  AND user_login = '';

INSERT INTO ${DB_PREFIX}plugin_setting (plugin_name, setting_name, setting_value, json_encoded, user_login)
SELECT '${plugin_escaped}', '${setting_escaped}', '${value_escaped}', 0, ''
FROM DUAL
WHERE NOT EXISTS (
  SELECT 1
  FROM ${DB_PREFIX}plugin_setting
  WHERE plugin_name = '${plugin_escaped}'
    AND setting_name = '${setting_escaped}'
    AND user_login = ''
);
" >/dev/null
}

set_config() {
  local section="$1"
  local key="$2"
  local value="$3"
  local secret="${4:-0}"

  if [[ "$secret" == "1" ]]; then
    echo "[matomo-config] setting [${section}] ${key}=***"
  else
    echo "[matomo-config] setting [${section}] ${key}=${value}"
  fi
  docker compose exec -T matomo-app php /var/www/html/console config:set \
    --section="$section" \
    --key="$key" \
    --value="$value" >/dev/null
}

set_config "General" "force_ssl" "$MATOMO_CFG_FORCE_SSL"
set_config "General" "login_allow_signup" "$MATOMO_CFG_LOGIN_ALLOW_SIGNUP"
set_config "General" "login_allow_reset_password" "$MATOMO_CFG_LOGIN_ALLOW_RESET_PASSWORD"
set_config "General" "enable_browser_archiving_triggering" "$MATOMO_CFG_ENABLE_BROWSER_ARCHIVING_TRIGGERING"
set_config "Tracker" "ignore_visits_do_not_track" "$MATOMO_CFG_IGNORE_VISITS_DO_NOT_TRACK"

if [[ -n "${SMTP_USER:-}" && -n "${SMTP_PASS:-}" ]]; then
  set_config "mail" "transport" "$MATOMO_CFG_SMTP_TRANSPORT"
  set_config "mail" "host" "$MATOMO_CFG_SMTP_HOST"
  set_config "mail" "port" "$MATOMO_CFG_SMTP_PORT"
  set_config "mail" "type" "$MATOMO_CFG_SMTP_TYPE"
  set_config "mail" "encryption" "$MATOMO_CFG_SMTP_ENCRYPTION"
  set_config "mail" "username" "$SMTP_USER"
  set_config "mail" "password" "$SMTP_PASS" "1"

  if [[ -n "$MATOMO_CFG_SMTP_FROM_ADDRESS" ]]; then
    set_config "General" "noreply_email_address" "$MATOMO_CFG_SMTP_FROM_ADDRESS"
  fi
  set_config "General" "noreply_email_name" "$MATOMO_CFG_SMTP_FROM_NAME"
else
  echo "[matomo-config] SMTP_USER/SMTP_PASS not set, skipping SMTP mail configuration"
fi

if [[ "$MATOMO_CFG_ENABLE_LOGIN_OIDC" == "1" ]]; then
  if docker compose exec -T matomo-app sh -lc '[ -d /var/www/html/plugins/LoginOIDC ]'; then
    echo "[matomo-config] activating LoginOIDC plugin"
    docker compose exec -T matomo-app php /var/www/html/console plugin:activate LoginOIDC >/dev/null || true

    set_plugin_setting "LoginOIDC" "allowSignup" "$MATOMO_CFG_OIDC_ALLOW_SIGNUP"
    set_plugin_setting "LoginOIDC" "autoLinking" "$MATOMO_CFG_OIDC_AUTO_LINKING"
    set_plugin_setting "LoginOIDC" "userinfoId" "$MATOMO_CFG_OIDC_USERINFO_ID"
  else
    echo "[matomo-config] LoginOIDC plugin directory not found, skipping activation"
  fi
fi

echo "[matomo-config] done"
