#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${BASE_DIR:-/opt/socia-students}"
THEHIVE_KEYSPACE_PREFIX="${THEHIVE_KEYSPACE_PREFIX:-thehive}"
THEHIVE_INDEX_PREFIX="${THEHIVE_INDEX_PREFIX:-thehive}"
CASSANDRA_CONTAINER="${CASSANDRA_CONTAINER:-socia-cassandra}"
ELASTICSEARCH_CONTAINER="${ELASTICSEARCH_CONTAINER:-socia-elasticsearch}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Ejecuta como root: sudo $0 contenedor1"
  exit 1
fi

KEEP_SHARED_DATA=0
INSTANCE="${1:-}"
if [[ "${2:-}" == "--keep-shared-data" ]]; then
  KEEP_SHARED_DATA=1
elif [[ "${2:-}" == "--purge-shared-data" ]]; then
  KEEP_SHARED_DATA=0
elif [[ -n "${2:-}" ]]; then
  echo "Opcion no soportada: ${2}"
  echo "Uso: sudo $0 contenedor1 [--keep-shared-data]"
  exit 1
fi

if [[ -z "${INSTANCE}" || ! "${INSTANCE}" =~ ^[a-z0-9][a-z0-9-]*$ || $# -gt 2 ]]; then
  echo "Uso: sudo $0 contenedor1 [--keep-shared-data]"
  exit 1
fi

INSTANCE_DIR="${BASE_DIR}/${INSTANCE}"

systemctl disable --now "thehive-consumer-${INSTANCE}.service" >/dev/null 2>&1 || true
systemctl disable --now "graylog-alert-consumer-${INSTANCE}.service" >/dev/null 2>&1 || true
rm -f "/etc/systemd/system/thehive-consumer-${INSTANCE}.service"
rm -f "/etc/systemd/system/graylog-alert-consumer-${INSTANCE}.service"
systemctl daemon-reload

if [[ -f "${INSTANCE_DIR}/docker-compose.yml" ]]; then
  docker compose -f "${INSTANCE_DIR}/docker-compose.yml" down -v
  rm -rf "${INSTANCE_DIR}"
elif [[ -d "${INSTANCE_DIR}" ]]; then
  rm -rf "${INSTANCE_DIR}"
else
  echo "No existe ${INSTANCE_DIR}; se limpiaran servicios y datos compartidos si existen."
fi

if [[ "${KEEP_SHARED_DATA}" -eq 0 ]]; then
  instance_cql="${INSTANCE//-/_}"
  keyspace="${THEHIVE_KEYSPACE_PREFIX}_${instance_cql}"
  index="${THEHIVE_INDEX_PREFIX}-${INSTANCE}"
  echo "Purgando datos compartidos: keyspace ${keyspace}, indices ${index}*"
  docker exec "${CASSANDRA_CONTAINER}" cqlsh -e "DROP KEYSPACE IF EXISTS ${keyspace};" 127.0.0.1 9042 >/dev/null
  docker exec "${ELASTICSEARCH_CONTAINER}" curl -fsS -X DELETE "http://127.0.0.1:9200/${index}*" >/dev/null 2>&1 || true
else
  echo "Datos compartidos conservados por --keep-shared-data."
fi

echo "Instancia eliminada: ${INSTANCE}"
