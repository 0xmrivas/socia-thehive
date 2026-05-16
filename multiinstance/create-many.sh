#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${BASE_DIR:-/opt/socia-students}"
PREFIX="${PREFIX:-contenedor}"
START_INDEX="${START_INDEX:-1}"
START_PORT="${START_PORT:-9101}"
NO_CONSUMER="${NO_CONSUMER:-0}"

usage() {
  cat <<'EOF_USAGE'
Uso:
  sudo ./create-many.sh 5
  sudo PREFIX=alumno START_INDEX=1 START_PORT=9201 ./create-many.sh 5
  sudo NO_CONSUMER=1 ./create-many.sh 5

Variables opcionales:
  BASE_DIR=/opt/socia-students
  PREFIX=contenedor
  START_INDEX=1
  START_PORT=9101
  NO_CONSUMER=0

Ejemplo:
  sudo ./create-many.sh 5

Crea:
  contenedor1 -> puerto 9101
  contenedor2 -> puerto 9102
  contenedor3 -> puerto 9103
  contenedor4 -> puerto 9104
  contenedor5 -> puerto 9105
EOF_USAGE
}

die() {
  echo "Error: $*" >&2
  exit 1
}

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "ejecuta como root: sudo $0 <cantidad>"
  fi
}

validate_number() {
  local name="$1"
  local value="$2"
  [[ "${value}" =~ ^[0-9]+$ ]] || die "${name} debe ser numerico: ${value}"
}

validate_instance() {
  local instance="$1"
  [[ "${instance}" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "nombre de instancia invalido: ${instance}"
}

port_in_use() {
  local port="$1"
  ss -ltn "( sport = :${port} )" | tail -n +2 | grep -q .
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -ne 1 ]]; then
    usage
    exit 0
  fi

  need_root
  validate_number "cantidad" "$1"
  validate_number "START_INDEX" "${START_INDEX}"
  validate_number "START_PORT" "${START_PORT}"

  local count="$1"
  (( count > 0 )) || die "cantidad debe ser mayor que 0"

  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  local create_args=()
  if [[ "${NO_CONSUMER}" == "1" || "${NO_CONSUMER}" == "true" ]]; then
    create_args+=(--no-consumer)
  fi

  local planned=()
  local i instance port
  echo "Planificando ${count} instancia(s):"
  for ((i = 0; i < count; i++)); do
    instance="${PREFIX}$((START_INDEX + i))"
    port="$((START_PORT + i))"
    validate_instance "${instance}"
    [[ ! -e "${BASE_DIR}/${instance}" ]] || die "ya existe ${BASE_DIR}/${instance}"
    ! systemctl list-unit-files "thehive-consumer-${instance}.service" --no-legend 2>/dev/null | grep -q . || die "ya existe el servicio thehive-consumer-${instance}.service"
    ! port_in_use "${port}" || die "el puerto ${port} ya esta en uso"
    planned+=("${instance}:${port}")
    printf '  %-20s -> %s\n' "${instance}" "${port}"
  done

  echo
  echo "Creando instancias..."
  for item in "${planned[@]}"; do
    instance="${item%%:*}"
    port="${item##*:}"
    echo
    echo "==> ${instance} (${port})"
    "${script_dir}/create-instance.sh" "${instance}" "${port}" "${create_args[@]}"
  done

  echo
  echo "Instancias creadas:"
  for item in "${planned[@]}"; do
    instance="${item%%:*}"
    port="${item##*:}"
    printf '  http://%s:%s  usuario: socia-%s@thehive.local  password: %s\n' "$(hostname -I | awk '{print $1}')" "${port}" "${instance}" "${instance}"
  done
}

main "$@"
