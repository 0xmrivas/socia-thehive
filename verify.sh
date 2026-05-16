#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/socia-thehive}"
THEHIVE_URL="${THEHIVE_URL:-http://127.0.0.1:9000}"
KAFKA_BOOTSTRAP_SERVERS="${KAFKA_BOOTSTRAP_SERVERS:-172.17.33.153:9092}"
KAFKA_TOPIC="${KAFKA_TOPIC:-ioc-events}"

if [[ -f "${INSTALL_DIR}/consumer/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${INSTALL_DIR}/consumer/.env"
  set +a
fi

THEHIVE_URL="${THEHIVE_URL%/}"
TEST_TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
SOURCE_REF="900001-${TEST_TIMESTAMP}"

OK=0
FAIL=0

print_result() {
  local name="$1"
  local status="$2"
  if [[ "${status}" == "ok" ]]; then
    printf '✅ %s\n' "${name}"
    OK=$((OK + 1))
  else
    printf '❌ %s\n' "${name}"
    FAIL=$((FAIL + 1))
  fi
}

check_containers() {
  local missing=0
  for container in socia-cassandra socia-elasticsearch socia-thehive; do
    if [[ "$(docker inspect -f '{{.State.Running}}' "${container}" 2>/dev/null || true)" != "true" ]]; then
      missing=1
    fi
  done
  [[ "${missing}" -eq 0 ]]
}

check_status() {
  local code
  code="$(curl -ksS -o /dev/null -w '%{http_code}' "${THEHIVE_URL}/api/status" || true)"
  [[ "${code}" == "200" ]]
}

check_service() {
  systemctl is-active --quiet thehive-consumer.service
}

send_kafka_message() {
  local payload
  payload="$(jq -nc --arg timestamp "${TEST_TIMESTAMP}" --arg source_ref "${SOURCE_REF}" '{
    timestamp: $timestamp,
    rule: {
      id: "900001",
      description: "SOCIA verify Wazuh test alert",
      level: 12,
      mitre: {id: ["T1059"], tactic: ["Execution"]}
    },
    agent: {name: "socia-verify", ip: "127.0.0.1"},
    data: {srcip: "203.0.113.10"},
    full_log: ("SOCIA verification alert " + $source_ref)
  }')"

  if command -v kcat >/dev/null 2>&1; then
    printf '%s\n' "${payload}" | kcat -P -b "${KAFKA_BOOTSTRAP_SERVERS}" -t "${KAFKA_TOPIC}"
    return
  fi

  if command -v kafka-console-producer >/dev/null 2>&1; then
    printf '%s\n' "${payload}" | kafka-console-producer --bootstrap-server "${KAFKA_BOOTSTRAP_SERVERS}" --topic "${KAFKA_TOPIC}" >/dev/null
    return
  fi

  if docker ps --format '{{.Names}}' | grep -Eq 'kafka|broker'; then
    local kafka_container
    kafka_container="$(docker ps --format '{{.Names}}' | grep -E 'kafka|broker' | head -1)"
    printf '%s\n' "${payload}" | docker exec -i "${kafka_container}" kafka-console-producer --bootstrap-server "${KAFKA_BOOTSTRAP_SERVERS}" --topic "${KAFKA_TOPIC}" >/dev/null
    return
  fi

  return 1
}

check_alert_created() {
  sleep 10
  if [[ -z "${THEHIVE_API_KEY:-}" ]]; then
    return 1
  fi

  local response
  response="$(curl -ksS "${THEHIVE_URL}/api/v1/query" \
    -H "Authorization: Bearer ${THEHIVE_API_KEY}" \
    ${THEHIVE_ORG:+-H "X-Organisation: ${THEHIVE_ORG}"} \
    -H "Content-Type: application/json" \
    -d "[{\"_name\":\"listAlert\"},{\"_name\":\"filter\",\"_eq\":{\"sourceRef\":\"${SOURCE_REF}\"}}]" || true)"

  printf '%s' "${response}" | jq -e 'length > 0' >/dev/null 2>&1
}

check_containers && print_result "Contenedores Docker Cassandra, Elasticsearch y TheHive corriendo" ok || print_result "Contenedores Docker Cassandra, Elasticsearch y TheHive corriendo" fail
check_status && print_result "TheHive responde HTTP 200 en /api/status" ok || print_result "TheHive responde HTTP 200 en /api/status" fail
check_service && print_result "Servicio systemd thehive-consumer activo" ok || print_result "Servicio systemd thehive-consumer activo" fail
send_kafka_message && print_result "Mensaje de prueba enviado a Kafka topic ${KAFKA_TOPIC}" ok || print_result "Mensaje de prueba enviado a Kafka topic ${KAFKA_TOPIC}" fail
check_alert_created && print_result "Alerta de prueba creada en TheHive" ok || print_result "Alerta de prueba creada en TheHive" fail

printf '\nResumen: %s OK, %s fallos\n' "${OK}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
