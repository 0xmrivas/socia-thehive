#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEDULE_DIR="${SCHEDULE_DIR:-/etc/socia-thehive/scheduled-jobs}"
SYSTEMD_DIR="${SYSTEMD_DIR:-/etc/systemd/system}"
KEEP_SHARED_DATA="${KEEP_SHARED_DATA:-0}"

usage() {
  cat <<'EOF_USAGE'
Uso:
  sudo ./schedule-delete-many.sh 5 "2026-05-20 18:00"
  sudo PREFIX=alumno START_INDEX=21 ./schedule-delete-many.sh --all "tomorrow 20:00"

Variables opcionales:
  BASE_DIR=/opt/socia-students
  PREFIX=contenedor
  START_INDEX=1
  KEEP_SHARED_DATA=0
  SCHEDULE_DIR=/etc/socia-thehive/scheduled-jobs
  SYSTEMD_DIR=/etc/systemd/system

El script crea una unidad systemd persistente para ejecutar delete-many.sh en
la fecha y hora indicadas. El trabajo queda visible con:

  systemctl list-timers 'socia-delete-many-*'

Y puede cancelarse con:

  sudo systemctl stop socia-delete-many-<id>.timer
  sudo systemctl disable socia-delete-many-<id>.timer
EOF_USAGE
}

die() {
  echo "Error: $*" >&2
  exit 1
}

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "ejecuta como root: sudo $0 <cantidad|--all> <fecha-hora>"
  fi
}

validate_number() {
  local name="$1"
  local value="$2"
  [[ "${value}" =~ ^[0-9]+$ ]] || die "${name} debe ser numerico: ${value}"
}

validate_prefix() {
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

  local target="$1"
  shift
  local when="$1"
  shift

  if [[ "${target}" != "--all" ]]; then
    validate_number "cantidad" "${target}"
    (( target > 0 )) || die "cantidad debe ser mayor que 0"
  fi

  validate_prefix "${PREFIX:-contenedor}"
  validate_when "${when}"

  local normalized_when scheduled_epoch now_epoch
  normalized_when="$(normalize_when "${when}")"
  scheduled_epoch="$(future_epoch "${when}")"
  now_epoch="$(date '+%s')"
  (( scheduled_epoch > now_epoch )) || die "la fecha/hora debe ser futura: ${normalized_when}"

  local job_stamp job_id unit_name service_name timer_name job_dir env_file service_file timer_file
  job_stamp="$(date -d "${normalized_when}" '+%Y%m%d%H%M%S')"
  job_id="${job_stamp}-$(unit_suffix "${PREFIX:-contenedor}")-$RANDOM"
  if [[ "${target}" == "--all" ]]; then
    job_id="${job_id}-all"
  else
    job_id="${job_id}-n${target}"
  fi
  unit_name="socia-delete-many-${job_id}"
  service_name="${unit_name}.service"
  timer_name="${unit_name}.timer"

  mkdir -p "${SCHEDULE_DIR}" "${SYSTEMD_DIR}"
  job_dir="${SCHEDULE_DIR}/${unit_name}"
  mkdir -p "${job_dir}"

  env_file="${job_dir}/delete-many.env"
  service_file="${SYSTEMD_DIR}/${service_name}"
  timer_file="${SYSTEMD_DIR}/${timer_name}"

  write_env_file "${env_file}" \
    BASE_DIR PREFIX START_INDEX KEEP_SHARED_DATA \
    SOURCE_DIR CASSANDRA_CONTAINER ELASTICSEARCH_CONTAINER

  cat >"${service_file}" <<EOF_SERVICE
[Unit]
Description=SOCIA delete-many job (${target} a las ${normalized_when})
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
WorkingDirectory=${SCRIPT_DIR}
EnvironmentFile=${env_file}
ExecStart=${SCRIPT_DIR}/delete-many.sh ${target}
EOF_SERVICE

  cat >"${timer_file}" <<EOF_TIMER
[Unit]
Description=Programacion SOCIA delete-many (${target} a las ${normalized_when})

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
  echo "  Target:   ${target}"
  echo "  Estado:   systemctl status ${timer_name} --no-pager"
  echo "  Timer:    systemctl list-timers 'socia-delete-many-*'"
}

main "$@"
