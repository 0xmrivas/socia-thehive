#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${BASE_DIR:-/opt/socia-students}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Ejecuta como root: sudo $0 contenedor1"
  exit 1
fi

INSTANCE="${1:-}"
if [[ -z "${INSTANCE}" || ! "${INSTANCE}" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  echo "Uso: sudo $0 contenedor1"
  exit 1
fi

INSTANCE_DIR="${BASE_DIR}/${INSTANCE}"
if [[ ! -d "${INSTANCE_DIR}" ]]; then
  echo "No existe ${INSTANCE_DIR}"
  exit 1
fi

systemctl disable --now "thehive-consumer-${INSTANCE}.service" >/dev/null 2>&1 || true
rm -f "/etc/systemd/system/thehive-consumer-${INSTANCE}.service"
systemctl daemon-reload

docker compose -f "${INSTANCE_DIR}/docker-compose.yml" down -v
rm -rf "${INSTANCE_DIR}"

echo "Instancia eliminada: ${INSTANCE}"
