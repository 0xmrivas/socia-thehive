#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${BASE_DIR:-/opt/socia-students}"
PREFIX="${PREFIX:-contenedor}"
START_INDEX="${START_INDEX:-1}"
KEEP_SHARED_DATA="${KEEP_SHARED_DATA:-0}"

usage() {
  cat <<'EOF_USAGE'
Uso:
  sudo ./delete-many.sh 5
  sudo ./delete-many.sh --all
  sudo PREFIX=alumno START_INDEX=1 ./delete-many.sh 5
  sudo KEEP_SHARED_DATA=1 ./delete-many.sh 5

Variables opcionales:
  BASE_DIR=/opt/socia-students
  PREFIX=contenedor
  START_INDEX=1
  KEEP_SHARED_DATA=0
  CASSANDRA_CONTAINER=socia-cassandra
  ELASTICSEARCH_CONTAINER=socia-elasticsearch

Por defecto borra contenedores, volumenes, ficheros, keyspace Cassandra e indices Elasticsearch
de cada instancia. Usa KEEP_SHARED_DATA=1 solo si quieres conservar esos datos compartidos.

Ejemplo:
  sudo ./delete-many.sh 5

Borra:
  contenedor1
  contenedor2
  contenedor3
  contenedor4
  contenedor5
EOF_USAGE
}

die() {
  echo "Error: $*" >&2
  exit 1
}

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "ejecuta como root: sudo $0 <cantidad|--all>"
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

discover_instances() {
  local instance
  if [[ ! -d "${BASE_DIR}" ]]; then
    return 0
  fi

  while IFS= read -r instance; do
    [[ -n "${instance}" ]] || continue
    validate_instance "${instance}"
    printf '%s\n' "${instance}"
  done < <(
    find "${BASE_DIR}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' |
      grep -E "^${PREFIX}[0-9]+$" |
      sort -V
  )
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -ne 1 ]]; then
    usage
    exit 0
  fi

  need_root
  validate_number "START_INDEX" "${START_INDEX}"

  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  local delete_args=()
  if [[ "${KEEP_SHARED_DATA}" == "1" || "${KEEP_SHARED_DATA}" == "true" ]]; then
    delete_args+=(--keep-shared-data)
  fi

  local planned=()
  local i count instance
  if [[ "$1" == "--all" ]]; then
    mapfile -t planned < <(discover_instances)
  else
    validate_number "cantidad" "$1"
    count="$1"
    (( count > 0 )) || die "cantidad debe ser mayor que 0"
    for ((i = 0; i < count; i++)); do
      instance="${PREFIX}$((START_INDEX + i))"
      validate_instance "${instance}"
      planned+=("${instance}")
    done
  fi

  if [[ "${#planned[@]}" -eq 0 ]]; then
    echo "No hay instancias que borrar para PREFIX=${PREFIX} en ${BASE_DIR}."
    exit 0
  fi

  echo "Instancias a eliminar:"
  for instance in "${planned[@]}"; do
    printf '  %s\n' "${instance}"
  done

  echo
  echo "Eliminando instancias..."
  for instance in "${planned[@]}"; do
    echo
    echo "==> ${instance}"
    "${script_dir}/delete-instance.sh" "${instance}" "${delete_args[@]}"
  done

  echo
  echo "Instancias eliminadas: ${#planned[@]}"
}

main "$@"
