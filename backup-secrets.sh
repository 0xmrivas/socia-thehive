#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/socia-thehive}"
STUDENTS_DIR="${STUDENTS_DIR:-/opt/socia-students}"
OUTPUT_DIR="${OUTPUT_DIR:-${INSTALL_DIR}/secret-backup}"
THEHIVE_URL="${THEHIVE_URL:-http://127.0.0.1:9000}"
THEHIVE_ADMIN_EMAIL="${THEHIVE_ADMIN_EMAIL:-admin@thehive.local}"
THEHIVE_ADMIN_PASSWORD="${THEHIVE_ADMIN_PASSWORD:-secret}"
CORTEX_URL="${CORTEX_URL:-http://127.0.0.1:9001}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Ejecuta este script como root: sudo ./backup-secrets.sh"
  exit 1
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Falta el comando requerido: $1"
    exit 1
  fi
}

copy_if_exists() {
  local src="$1"
  local dst="$2"
  if [[ -f "${src}" ]]; then
    install -m 0600 "${src}" "${dst}"
  fi
}

get_cortex_key() {
  local key=""
  if [[ -f "${INSTALL_DIR}/.env" ]]; then
    key="$(sed -n 's/^CORTEX_API_KEY=//p' "${INSTALL_DIR}/.env" | head -n 1)"
  fi
  if [[ -z "${key}" && -d "${STUDENTS_DIR}" ]]; then
    key="$(find "${STUDENTS_DIR}" -maxdepth 2 -name .env -print0 2>/dev/null \
      | xargs -0 -r sed -n 's/^CORTEX_API_KEY=//p' \
      | head -n 1)"
  fi
  printf '%s' "${key}"
}

fetch_thehive_config() {
  local path="$1"
  local dst="$2"
  local cookie_jar code
  cookie_jar="$(mktemp)"
  trap 'rm -f "${cookie_jar}"' RETURN

  code="$(curl -sS -o "${OUTPUT_DIR}/tmp-login.json" -w '%{http_code}' \
    -c "${cookie_jar}" \
    -X POST "${THEHIVE_URL}/api/v1/login" \
    -H "Content-Type: application/json" \
    -d "{\"user\":\"${THEHIVE_ADMIN_EMAIL}\",\"password\":\"${THEHIVE_ADMIN_PASSWORD}\"}" || true)"
  if [[ "${code}" != "200" ]]; then
    rm -f "${OUTPUT_DIR}/tmp-login.json"
    echo "No se pudo iniciar sesión en TheHive para exportar ${path}; se omite."
    return 0
  fi
  rm -f "${OUTPUT_DIR}/tmp-login.json"

  code="$(curl -sS -o "${dst}" -w '%{http_code}' -b "${cookie_jar}" "${THEHIVE_URL}${path}" || true)"
  if [[ "${code}" == "200" ]]; then
    chmod 0600 "${dst}"
  else
    rm -f "${dst}"
    echo "No se pudo exportar ${path}; HTTP ${code}."
  fi
}

fetch_cortex_config() {
  local path="$1"
  local dst="$2"
  local cortex_key code
  cortex_key="$(get_cortex_key)"
  if [[ -z "${cortex_key}" ]]; then
    echo "No hay CORTEX_API_KEY disponible; se omite ${path}."
    return 0
  fi

  code="$(curl -sS -o "${dst}" -w '%{http_code}' \
    -H "Authorization: Bearer ${cortex_key}" \
    "${CORTEX_URL}${path}" || true)"
  if [[ "${code}" == "200" ]]; then
    chmod 0600 "${dst}"
  else
    rm -f "${dst}"
    echo "No se pudo exportar Cortex ${path}; HTTP ${code}."
  fi
}

require_cmd curl
require_cmd jq
require_cmd tar

umask 077
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_dir="${OUTPUT_DIR}/${timestamp}"
archive="${OUTPUT_DIR}/socia-secrets-${timestamp}.tgz"

install -d -m 0700 "${backup_dir}/env" "${backup_dir}/thehive" "${backup_dir}/cortex" "${backup_dir}/students"

copy_if_exists "${INSTALL_DIR}/.env" "${backup_dir}/env/base.env"
copy_if_exists "${INSTALL_DIR}/consumer/.env" "${backup_dir}/env/consumer.env"
copy_if_exists "${INSTALL_DIR}/graylog-alert-consumer/.env" "${backup_dir}/env/graylog-alert-consumer.env"

if [[ -d "${STUDENTS_DIR}" ]]; then
  while IFS= read -r -d '' file; do
    rel="${file#"${STUDENTS_DIR}/"}"
    dst="${backup_dir}/students/${rel}"
    install -d -m 0700 "$(dirname "${dst}")"
    install -m 0600 "${file}" "${dst}"
  done < <(find "${STUDENTS_DIR}" -maxdepth 3 -type f \( -name .env -o -path '*/graylog-alert-consumer/.env' \) -print0)
fi

fetch_thehive_config "/api/v1/admin/config/misp" "${backup_dir}/thehive/misp-config.json"
fetch_thehive_config "/api/v1/admin/config/cortex" "${backup_dir}/thehive/cortex-config.json"
fetch_cortex_config "/api/analyzerconfig" "${backup_dir}/cortex/analyzerconfig.json"
fetch_cortex_config "/api/organization/analyzer" "${backup_dir}/cortex/enabled-analyzers.json"

jq -n \
  --arg createdAt "${timestamp}" \
  --arg installDir "${INSTALL_DIR}" \
  --arg studentsDir "${STUDENTS_DIR}" \
  --arg thehiveUrl "${THEHIVE_URL}" \
  --arg cortexUrl "${CORTEX_URL}" \
  '{
    createdAt: $createdAt,
    installDir: $installDir,
    studentsDir: $studentsDir,
    thehiveUrl: $thehiveUrl,
    cortexUrl: $cortexUrl,
    note: "Contiene secretos reales. Guardar cifrado y fuera del repositorio."
  }' >"${backup_dir}/manifest.json"
chmod 0600 "${backup_dir}/manifest.json"

tar -C "${OUTPUT_DIR}" -czf "${archive}" "${timestamp}"
chmod 0600 "${archive}"

echo "Backup de secretos creado:"
echo "${archive}"
echo "Directorio:"
echo "${backup_dir}"
