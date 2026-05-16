#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="${BASE_DIR:-/opt/socia-students}"
SCHEDULE_DIR="${SCHEDULE_DIR:-/etc/socia-thehive/scheduled-jobs}"
SYSTEMD_DIR="${SYSTEMD_DIR:-/etc/systemd/system}"
NO_CONSUMER="${NO_CONSUMER:-0}"

usage() {
  cat <<'EOF_USAGE'
Uso:
  sudo ./schedule-create-many.sh 5 "2026-05-20 13:00"
  sudo PREFIX=alumno START_INDEX=21 START_PORT=9121 ./schedule-create-many.sh 3 "tomorrow 08:00"

Variables opcionales:
  BASE_DIR=/opt/socia-students
  PREFIX=contenedor
  START_INDEX=1
  START_PORT=9101
  NO_CONSUMER=0
  SCHEDULE_DIR=/etc/socia-thehive/scheduled-jobs
  SYSTEMD_DIR=/etc/systemd/system

El script crea una unidad systemd persistente para ejecutar create-many.sh en
la fecha y hora indicadas. El trabajo queda visible con:

  systemctl list-timers 'socia-create-many-*'

Y puede cancelarse con:

  sudo systemctl stop socia-create-many-<id>.timer
  sudo systemctl disable socia-create-many-<id>.timer
EOF_USAGE
}

die() {
  echo "Error: $*" >&2
  exit 1
}

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "ejecuta como root: sudo $0 <cantidad> <fecha-hora>"
  fi
}

validate_number() {
  local name="$1"
  local value="$2"
  [[ "${value}" =~ ^[0-9]+$ ]] || die "${name} debe ser numerico: ${value}"
}

validate_instance_prefix() {
  local value="$1"
  [[ "${value}" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "PREFIX invalido: ${value}"
}

validate_when() {
  local value="$1"
  date -d "${value}" '+%Y-%m-%d %H:%M:%S' >/dev/null
}

normalize_when() {
  date -d "$1" '+%Y-%m-%d %H:%M:%S'
}

future_epoch() {
  date -d "$1" '+%s'
}

unit_suffix() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-'
}

write_env_file() {
  local file="$1"
  shift
  : >"${file}"
  local key value
  for key in "$@"; do
    value="${!key-}"
    if [[ -n "${value}" ]]; then
      printf '%s=%q\n' "${key}" "${value}" >>"${file}"
    fi
  done
  chmod 0640 "${file}"
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -lt 2 ]]; then
    usage
    exit 0
  fi

  need_root

  local count="$1"
  shift
  local when="$1"
  shift

  validate_number "cantidad" "${count}"
  validate_instance_prefix "${PREFIX:-contenedor}"
  validate_when "${when}"

  local normalized_when scheduled_epoch now_epoch
  normalized_when="$(normalize_when "${when}")"
  scheduled_epoch="$(future_epoch "${when}")"
  now_epoch="$(date '+%s')"
  (( scheduled_epoch > now_epoch )) || die "la fecha/hora debe ser futura: ${normalized_when}"

  local job_stamp job_id unit_name service_name timer_name job_dir env_file service_file timer_file
  job_stamp="$(date -d "${normalized_when}" '+%Y%m%d%H%M%S')"
  job_id="${job_stamp}-c${count}-$(unit_suffix "${PREFIX:-contenedor}")-$RANDOM"
  unit_name="socia-create-many-${job_id}"
  service_name="${unit_name}.service"
  timer_name="${unit_name}.timer"

  mkdir -p "${SCHEDULE_DIR}" "${SYSTEMD_DIR}"
  job_dir="${SCHEDULE_DIR}/${unit_name}"
  mkdir -p "${job_dir}"

  env_file="${job_dir}/create-many.env"
  service_file="${SYSTEMD_DIR}/${service_name}"
  timer_file="${SYSTEMD_DIR}/${timer_name}"

  write_env_file "${env_file}" \
    BASE_DIR PREFIX START_INDEX START_PORT NO_CONSUMER \
    SOURCE_DIR KAFKA_BOOTSTRAP_SERVERS GRAYLOG_ALERT_KAFKA_TOPIC \
    ADMIN_USER ADMIN_PASSWORD ADMIN_API_KEY \
    MISP_URL MISP_API_KEY MISP_NAME MISP_PURPOSE MISP_INTERVAL MISP_ACCEPT_ANY_CERT \
    CORTEX_ENABLED CORTEX_COPY_FROM_URL CORTEX_URL CORTEX_HOST_URL CORTEX_NAME CORTEX_API_KEY \
    CORTEX_ANALYZERS CORTEX_CONFIGURE_ANALYZERS CORTEX_ADMIN_USER CORTEX_ADMIN_PASSWORD CORTEX_ORG \
    THEHIVE_HEAP SHARED_NETWORK CASSANDRA_CONTAINER ELASTICSEARCH_CONTAINER \
    THEHIVE_KEYSPACE_PREFIX THEHIVE_INDEX_PREFIX

  cat >"${service_file}" <<EOF_SERVICE
[Unit]
Description=SOCIA create-many job (${count} instancia(s) a las ${normalized_when})
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
WorkingDirectory=${SCRIPT_DIR}
EnvironmentFile=${env_file}
ExecStart=${SCRIPT_DIR}/create-many.sh ${count}
EOF_SERVICE

  cat >"${timer_file}" <<EOF_TIMER
[Unit]
Description=Programacion SOCIA create-many (${count} instancia(s) a las ${normalized_when})

[Timer]
OnCalendar=${normalized_when}
Persistent=true
Unit=${service_name}

[Install]
WantedBy=timers.target
EOF_TIMER

  systemctl daemon-reload
  systemctl enable --now "${timer_name}"

  echo "Tarea programada."
  echo "  Unidades: ${service_name} / ${timer_name}"
  echo "  Fecha:    ${normalized_when}"
  echo "  Count:    ${count}"
  echo "  Estado:   systemctl status ${timer_name} --no-pager"
  echo "  Timer:    systemctl list-timers 'socia-create-many-*'"
}

main "$@"
