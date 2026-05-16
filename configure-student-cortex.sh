#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/socia-thehive}"
STUDENTS_DIR="${STUDENTS_DIR:-/opt/socia-students}"
START_INDEX="${START_INDEX:-1}"
END_INDEX="${END_INDEX:-20}"
START_PORT="${START_PORT:-9101}"
CORTEX_URL="${CORTEX_URL:-http://127.0.0.1:9001}"
CORTEX_INTERNAL_URL="${CORTEX_INTERNAL_URL:-http://cortex:9001}"
CORTEX_ADMIN_USER="${CORTEX_ADMIN_USER:-admin}"
CORTEX_ADMIN_PASSWORD="${CORTEX_ADMIN_PASSWORD:-secret}"
CORTEX_ORG="${CORTEX_ORG:-cortex}"
THEHIVE_ADMIN_EMAIL="${THEHIVE_ADMIN_EMAIL:-admin@thehive.local}"
THEHIVE_ADMIN_PASSWORD="${THEHIVE_ADMIN_PASSWORD:-secret}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Ejecuta este script como root: sudo ./configure-student-cortex.sh"
  exit 1
fi

if [[ -f "${INSTALL_DIR}/install.sh" ]]; then
  CORTEX_ADMIN_USER="$(sed -n 's/^CORTEX_ADMIN_USER="${CORTEX_ADMIN_USER:-\([^}]*\)}"/\1/p' "${INSTALL_DIR}/install.sh" || true)"
  CORTEX_ADMIN_USER="${CORTEX_ADMIN_USER:-admin}"
  CORTEX_ADMIN_PASSWORD="$(sed -n 's/^CORTEX_ADMIN_PASSWORD="${CORTEX_ADMIN_PASSWORD:-\([^}]*\)}"/\1/p' "${INSTALL_DIR}/install.sh" || true)"
  CORTEX_ADMIN_PASSWORD="${CORTEX_ADMIN_PASSWORD:-secret}"
  CORTEX_ORG="$(sed -n 's/^CORTEX_ORG="${CORTEX_ORG:-\([^}]*\)}"/\1/p' "${INSTALL_DIR}/install.sh" || true)"
  CORTEX_ORG="${CORTEX_ORG:-cortex}"
  THEHIVE_ADMIN_EMAIL="$(sed -n 's/^THEHIVE_ADMIN_EMAIL="${THEHIVE_ADMIN_EMAIL:-\([^}]*\)}"/\1/p' "${INSTALL_DIR}/install.sh" || true)"
  THEHIVE_ADMIN_EMAIL="${THEHIVE_ADMIN_EMAIL:-admin@thehive.local}"
  THEHIVE_ADMIN_PASSWORD="$(sed -n 's/^THEHIVE_ADMIN_PASSWORD="${THEHIVE_ADMIN_PASSWORD:-\([^}]*\)}"/\1/p' "${INSTALL_DIR}/install.sh" || true)"
  THEHIVE_ADMIN_PASSWORD="${THEHIVE_ADMIN_PASSWORD:-secret}"
fi

extract_api_key() {
  local response="$1"
  local key
  key="$(printf '%s' "${response}" | jq -er '.key // .apiKey // .apikey // .password // .value // empty' 2>/dev/null || true)"
  if [[ -n "${key}" ]]; then
    printf '%s' "${key}"
  else
    printf '%s' "${response}" | tr -d '\r\n'
  fi
}

set_env_var() {
  local file="$1"
  local key="$2"
  local value="$3"
  local escaped_value
  escaped_value="${value//\\/\\\\}"
  escaped_value="${escaped_value//&/\\&}"
  escaped_value="${escaped_value//|/\\|}"
  touch "${file}"
  if grep -q "^${key}=" "${file}"; then
    sed -i "s|^${key}=.*|${key}=${escaped_value}|" "${file}"
  else
    printf '%s=%s\n' "${key}" "${value}" >>"${file}"
  fi
}

cortex_key_valid() {
  local key="$1"
  [[ -n "${key}" ]] || return 1
  [[ "$(curl -fsS -o /dev/null -w '%{http_code}' \
    -H "Authorization: Bearer ${key}" \
    "${CORTEX_URL}/api/user/current" || true)" == "200" ]]
}

ensure_cortex_user_key() {
  local index="$1"
  local login="thehive-contenedor${index}"
  local env_file="${STUDENTS_DIR}/contenedor${index}/.env"
  local key=""

  if [[ -f "${env_file}" ]]; then
    key="$(sed -n 's/^CORTEX_API_KEY=//p' "${env_file}" | head -n 1)"
  fi

  if cortex_key_valid "${key}"; then
    printf '%s' "${key}"
    return 0
  fi

  local user_status
  user_status="$(curl -fsS -o /dev/null -w '%{http_code}' \
    -u "${CORTEX_ADMIN_USER}:${CORTEX_ADMIN_PASSWORD}" \
    "${CORTEX_URL}/api/user/${login}" || true)"

  if [[ "${user_status}" != "200" ]]; then
    local secret_prefix password payload
    secret_prefix="$(sed -n 's/^CORTEX_SECRET=//p' "${INSTALL_DIR}/.env" 2>/dev/null | cut -c1-12)"
    password="${login}-${secret_prefix:-socia}"
    payload="$(jq -nc \
      --arg login "${login}" \
      --arg password "${password}" \
      --arg org "${CORTEX_ORG}" \
      '{login:$login,name:$login,roles:["read","analyze","orgadmin"],preferences:"{}",password:$password,organization:$org}')"
    curl -fsS -X POST "${CORTEX_URL}/api/user" \
      -u "${CORTEX_ADMIN_USER}:${CORTEX_ADMIN_PASSWORD}" \
      -H "Content-Type: application/json" \
      -d "${payload}" >/dev/null
  fi

  key="$(extract_api_key "$(curl -fsS -X POST \
    -u "${CORTEX_ADMIN_USER}:${CORTEX_ADMIN_PASSWORD}" \
    "${CORTEX_URL}/api/user/${login}/key/renew")")"

  if [[ -z "${key}" ]]; then
    echo "No pude obtener API key de Cortex para ${login}" >&2
    return 1
  fi

  set_env_var "${env_file}" "CORTEX_THEHIVE_USER" "${login}"
  set_env_var "${env_file}" "CORTEX_API_KEY" "${key}"
  chmod 0640 "${env_file}"
  printf '%s' "${key}"
}

cortex_payload() {
  local key="$1"
  jq -nc \
    --arg url "${CORTEX_INTERNAL_URL}" \
    --arg key "${key}" \
    '{
      statusCheckInterval: "1 minute",
      refreshDelay: "5 seconds",
      maxRetryOnError: 3,
      jobTimeout: "3 hours",
      servers: [{
        name: "Cortex",
        url: $url,
        includedTheHiveOrganisations: ["*"],
        excludedTheHiveOrganisations: [],
        auth: {type: "bearer", key: $key},
        default: true
      }]
    }'
}

echo "Configurando Cortex en instancias ${START_INDEX}-${END_INDEX} ..."
printf 'idx port cortex_user cortex_key thehive_config analyzers\n'

for index in $(seq "${START_INDEX}" "${END_INDEX}"); do
  port=$((START_PORT + index - START_INDEX))
  env_file="${STUDENTS_DIR}/contenedor${index}/.env"
  login="thehive-contenedor${index}"
  key="$(ensure_cortex_user_key "${index}")"
  payload="$(cortex_payload "${key}")"

  code="$(curl -fsS -o "/tmp/socia-cortex-config-${index}.out" -w '%{http_code}' \
    -X PUT "http://127.0.0.1:${port}/api/v1/admin/config/cortex" \
    -u "${THEHIVE_ADMIN_EMAIL}:${THEHIVE_ADMIN_PASSWORD}" \
    -H "X-Organisation: admin" \
    -H "Content-Type: application/json" \
    -d "${payload}" || true)"

  if [[ "${code}" != "204" ]]; then
    echo "No pude configurar Cortex en contenedor${index}. HTTP ${code}" >&2
    cat "/tmp/socia-cortex-config-${index}.out" >&2
    exit 1
  fi

  set_env_var "${env_file}" "CORTEX_THEHIVE_USER" "${login}"
  set_env_var "${env_file}" "CORTEX_API_KEY" "${key}"
  chmod 0640 "${env_file}"

  sleep 1
  api_key="$(sed -n 's/^THEHIVE_API_KEY=//p' "${STUDENTS_DIR}/contenedor${index}/graylog-alert-consumer/.env" | head -n 1)"
  analyzers="$(curl -fsS -H "Authorization: Bearer ${api_key}" \
    "http://127.0.0.1:${port}/api/connector/cortex/analyzer" |
    jq 'if type=="array" then length else -1 end')"
  printf '%02d %s %s ok %s %s\n' "${index}" "${port}" "${login}" "${code}" "${analyzers}"
done
