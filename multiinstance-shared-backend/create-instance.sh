#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${BASE_DIR:-/opt/socia-students}"
SOURCE_DIR="${SOURCE_DIR:-/home/debian/socia-thehive}"
KAFKA_BOOTSTRAP_SERVERS="${KAFKA_BOOTSTRAP_SERVERS:-172.17.33.153:9092}"
GRAYLOG_ALERT_KAFKA_TOPIC="${GRAYLOG_ALERT_KAFKA_TOPIC:-graylog-alerts}"
ADMIN_USER="${ADMIN_USER:-admin@thehive.local}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-secret}"
ORG_NAME_DEFAULT="SOCIA"
ADMIN_API_KEY="${ADMIN_API_KEY:-}"
MISP_URL="${MISP_URL:-https://172.17.33.145}"
MISP_API_KEY="${MISP_API_KEY:-}"
MISP_NAME="${MISP_NAME:-MISP local}"
MISP_PURPOSE="${MISP_PURPOSE:-ImportAndExport}"
MISP_INTERVAL="${MISP_INTERVAL:-10 minutes}"
MISP_ACCEPT_ANY_CERT="${MISP_ACCEPT_ANY_CERT:-true}"
CORTEX_ENABLED="${CORTEX_ENABLED:-true}"
CORTEX_COPY_FROM_URL="${CORTEX_COPY_FROM_URL:-http://127.0.0.1:9000}"
CORTEX_URL="${CORTEX_URL:-http://cortex:9001}"
CORTEX_HOST_URL="${CORTEX_HOST_URL:-http://127.0.0.1:9001}"
CORTEX_NAME="${CORTEX_NAME:-Cortex}"
CORTEX_API_KEY="${CORTEX_API_KEY:-}"
CORTEX_ANALYZERS="${CORTEX_ANALYZERS:-}"
CORTEX_CONFIGURE_ANALYZERS="${CORTEX_CONFIGURE_ANALYZERS:-true}"
CORTEX_ADMIN_USER="${CORTEX_ADMIN_USER:-admin}"
CORTEX_ADMIN_PASSWORD="${CORTEX_ADMIN_PASSWORD:-secret}"
CORTEX_ORG="${CORTEX_ORG:-cortex}"

THEHIVE_HEAP="${THEHIVE_HEAP:-768m}"
SHARED_NETWORK="${SHARED_NETWORK:-socia-thehive}"
CASSANDRA_CONTAINER="${CASSANDRA_CONTAINER:-socia-cassandra}"
ELASTICSEARCH_CONTAINER="${ELASTICSEARCH_CONTAINER:-socia-elasticsearch}"
THEHIVE_KEYSPACE_PREFIX="${THEHIVE_KEYSPACE_PREFIX:-thehive}"
THEHIVE_INDEX_PREFIX="${THEHIVE_INDEX_PREFIX:-thehive}"

usage() {
  cat <<'EOF_USAGE'
Uso:
  sudo ./create-instance.sh contenedor1 9101
  sudo ./create-instance.sh contenedor2 9102 --no-consumer

Variables opcionales:
  BASE_DIR=/opt/socia-students
  KAFKA_BOOTSTRAP_SERVERS=172.17.33.153:9092
  ADMIN_USER=admin@thehive.local
  ADMIN_PASSWORD=secret
  ADMIN_API_KEY=<api-key-admin-existente>
  MISP_API_KEY=<api-key-misp>
  MISP_URL=https://172.17.33.145
  CORTEX_ENABLED=true
  CORTEX_COPY_FROM_URL=http://127.0.0.1:9000
  CORTEX_URL=http://cortex:9001
  CORTEX_HOST_URL=http://127.0.0.1:9001
  CORTEX_API_KEY=<api-key-cortex>
  CORTEX_ANALYZERS=AbuseIPDB_2_0,VirusTotal_GetReport_3_1
  CORTEX_ADMIN_USER=admin
  CORTEX_ADMIN_PASSWORD=secret
  THEHIVE_HEAP=768m
  SHARED_NETWORK=socia-thehive
  CASSANDRA_CONTAINER=socia-cassandra
  ELASTICSEARCH_CONTAINER=socia-elasticsearch
  THEHIVE_KEYSPACE_PREFIX=thehive
  THEHIVE_INDEX_PREFIX=thehive

Cada instancia usa Cassandra y Elasticsearch compartidos del despliegue base.
Se aisla con keyspace Cassandra, indice Elasticsearch y volumenes propios.
EOF_USAGE
}

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Ejecuta como root: sudo $0 ..."
    exit 1
  fi
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Falta el comando requerido: $1"
    exit 1
  fi
}

validate_instance() {
  local instance="$1"
  if [[ ! "${instance}" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    echo "Nombre de instancia invalido: ${instance}"
    echo "Usa solo minusculas, numeros y guiones. Ejemplo: contenedor1"
    exit 1
  fi
}

validate_port() {
  local port="$1"
  if [[ ! "${port}" =~ ^[0-9]+$ ]] || (( port < 1024 || port > 65535 )); then
    echo "Puerto invalido: ${port}"
    exit 1
  fi
  if ss -ltn "( sport = :${port} )" | tail -n +2 | grep -q .; then
    echo "El puerto ${port} ya esta en uso."
    exit 1
  fi
}

validate_cql_identifier() {
  local name="$1"
  local value="$2"
  if [[ ! "${value}" =~ ^[a-z][a-z0-9_]*$ ]]; then
    echo "${name} invalido para Cassandra: ${value}"
    echo "Debe empezar por letra minuscula y usar solo minusculas, numeros y guion bajo."
    exit 1
  fi
}

validate_es_index() {
  local value="$1"
  if [[ ! "${value}" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
    echo "Indice Elasticsearch invalido: ${value}"
    echo "Usa minusculas, numeros, guiones y guion bajo."
    exit 1
  fi
}

replace_tokens() {
  local src="$1"
  local dst="$2"
  sed \
    -e "s#__INSTANCE__#${INSTANCE}#g" \
    -e "s#__PORT__#${PORT}#g" \
    -e "s#__INSTANCE_DIR__#${INSTANCE_DIR}#g" \
    -e "s#__KAFKA_BOOTSTRAP_SERVERS__#${KAFKA_BOOTSTRAP_SERVERS}#g" \
    -e "s#__GRAYLOG_ALERT_KAFKA_TOPIC__#${GRAYLOG_ALERT_KAFKA_TOPIC}#g" \
    -e "s#__ORG_NAME__#${ORG_NAME}#g" \
    -e "s#__THEHIVE_API_KEY__#${THEHIVE_API_KEY:-change-me}#g" \
    -e "s#__THEHIVE_HEAP__#${THEHIVE_HEAP}#g" \
    -e "s#__THEHIVE_KEYSPACE__#${THEHIVE_KEYSPACE}#g" \
    -e "s#__THEHIVE_INDEX__#${THEHIVE_INDEX}#g" \
    -e "s#__COOKIE_NAME__#${COOKIE_NAME}#g" \
    "${src}" >"${dst}"
}

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
    "${CORTEX_HOST_URL}/api/user/current" || true)" == "200" ]]
}

ensure_instance_cortex_key() {
  local env_file="${INSTANCE_DIR}/.env"
  local login="thehive-${INSTANCE}"
  local key="${CORTEX_API_KEY}"

  if [[ -z "${key}" && -f "${env_file}" ]]; then
    key="$(sed -n 's/^CORTEX_API_KEY=//p' "${env_file}" | head -n 1)"
  fi
  if cortex_key_valid "${key}"; then
    set_env_var "${env_file}" "CORTEX_THEHIVE_USER" "${login}"
    set_env_var "${env_file}" "CORTEX_API_KEY" "${key}"
    printf '%s' "${key}"
    return 0
  fi

  local user_status
  user_status="$(curl -fsS -o /dev/null -w '%{http_code}' \
    -u "${CORTEX_ADMIN_USER}:${CORTEX_ADMIN_PASSWORD}" \
    "${CORTEX_HOST_URL}/api/user/${login}" || true)"

  if [[ "${user_status}" != "200" ]]; then
    local secret_prefix password payload
    secret_prefix="$(sed -n 's/^CORTEX_SECRET=//p' /opt/socia-thehive/.env 2>/dev/null | cut -c1-12)"
    password="${login}-${secret_prefix:-socia}"
    payload="$(jq -nc \
      --arg login "${login}" \
      --arg password "${password}" \
      --arg org "${CORTEX_ORG}" \
      '{login:$login,name:$login,roles:["read","analyze","orgadmin"],preferences:"{}",password:$password,organization:$org}')"
    curl -fsS -X POST "${CORTEX_HOST_URL}/api/user" \
      -u "${CORTEX_ADMIN_USER}:${CORTEX_ADMIN_PASSWORD}" \
      -H "Content-Type: application/json" \
      -d "${payload}" >/dev/null
  fi

  key="$(extract_api_key "$(curl -fsS -X POST \
    -u "${CORTEX_ADMIN_USER}:${CORTEX_ADMIN_PASSWORD}" \
    "${CORTEX_HOST_URL}/api/user/${login}/key/renew")")"
  if [[ -z "${key}" ]]; then
    echo "No pude obtener API key de Cortex para ${login}."
    exit 1
  fi

  set_env_var "${env_file}" "CORTEX_THEHIVE_USER" "${login}"
  set_env_var "${env_file}" "CORTEX_API_KEY" "${key}"
  chmod 0640 "${env_file}"
  printf '%s' "${key}"
}

wait_for_shared_backends() {
  echo "Comprobando backends compartidos (${CASSANDRA_CONTAINER}, ${ELASTICSEARCH_CONTAINER})..."

  if ! docker network inspect "${SHARED_NETWORK}" >/dev/null 2>&1; then
    echo "No existe la red Docker compartida: ${SHARED_NETWORK}"
    echo "Levanta primero el stack base: docker compose -f ${SOURCE_DIR}/docker-compose.yml up -d"
    exit 1
  fi

  for _ in $(seq 1 60); do
    if docker exec "${CASSANDRA_CONTAINER}" cqlsh -e 'DESCRIBE KEYSPACES' 127.0.0.1 9042 >/dev/null 2>&1; then
      break
    fi
    sleep 5
  done
  if ! docker exec "${CASSANDRA_CONTAINER}" cqlsh -e 'DESCRIBE KEYSPACES' 127.0.0.1 9042 >/dev/null 2>&1; then
    echo "Cassandra compartido no responde en ${CASSANDRA_CONTAINER}."
    exit 1
  fi

  for _ in $(seq 1 60); do
    if docker exec "${ELASTICSEARCH_CONTAINER}" curl -fsS 'http://127.0.0.1:9200/_cluster/health?wait_for_status=yellow&timeout=5s' >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
  done

  echo "Elasticsearch compartido no responde en ${ELASTICSEARCH_CONTAINER}."
  exit 1
}

prepare_shared_storage() {
  echo "Preparando keyspace Cassandra ${THEHIVE_KEYSPACE}; TheHive creara el indice Elasticsearch ${THEHIVE_INDEX}..."
  docker exec "${CASSANDRA_CONTAINER}" cqlsh -e \
    "CREATE KEYSPACE IF NOT EXISTS ${THEHIVE_KEYSPACE} WITH replication = {'class': 'NetworkTopologyStrategy', 'dc1': 1};" \
    127.0.0.1 9042 >/dev/null
}

wait_for_thehive() {
  echo "Esperando a TheHive (${INSTANCE}) en http://127.0.0.1:${PORT}/api/status ..."
  for _ in $(seq 1 120); do
    if curl -fsS "http://127.0.0.1:${PORT}/api/status" >/dev/null 2>&1; then
      echo "TheHive ${INSTANCE} responde."
      return 0
    fi
    sleep 10
  done
  echo "TheHive ${INSTANCE} no respondio a tiempo."
  docker compose -f "${INSTANCE_DIR}/docker-compose.yml" logs --tail=160 thehive
  exit 1
}

login_admin() {
  COOKIE_JAR="$(mktemp)"
  local login_response
  for _ in $(seq 1 60); do
    login_response="$(curl -fsS -c "${COOKIE_JAR}" -X POST "http://127.0.0.1:${PORT}/api/v1/login" \
      -H "Content-Type: application/json" \
      -d "{\"user\":\"${ADMIN_USER}\",\"password\":\"${ADMIN_PASSWORD}\"}" || true)"
    if printf '%s' "${login_response}" | grep -q "\"login\":\"${ADMIN_USER}\""; then
      return 0
    fi
    sleep 5
  done

  echo "No pude iniciar sesión como admin local en TheHive ${INSTANCE}." >&2
  echo "Revisa ADMIN_USER/ADMIN_PASSWORD para http://127.0.0.1:${PORT}." >&2
  printf '%s\n' "${login_response}" >&2
  rm -f "${COOKIE_JAR}"
  exit 1
}

renew_user_key() {
  local login="$1"
  local response
  for _ in $(seq 1 30); do
    response="$(curl -fsS -b "${COOKIE_JAR}" -X POST "http://127.0.0.1:${PORT}/api/v1/user/${login//@/%40}/key/renew" || true)"
    if [[ -n "${response}" ]]; then
      printf '%s' "${response}"
      return 0
    fi
    sleep 5
  done
  echo "No pude renovar la API key para ${login} en TheHive ${INSTANCE}." >&2
  return 1
}

create_org() {
  local response
  response="$(curl -sS -b "${COOKIE_JAR}" -X POST "http://127.0.0.1:${PORT}/api/v1/organisation" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"${ORG_NAME}\",\"description\":\"SOCIA laboratory organisation\"}" || true)"
  if printf '%s' "${response}" | grep -qi 'already\|exists\|Duplicate'; then
    echo "La organización ${ORG_NAME} ya existe."
  elif ! printf '%s' "${response}" | grep -q "\"name\":\"${ORG_NAME}\""; then
    echo "No pude crear organización ${ORG_NAME}. Respuesta:"
    printf '%s\n' "${response}"
    rm -f "${COOKIE_JAR}"
    exit 1
  fi
}

create_lab_user() {
  local login="$1"
  local display_name="$2"
  local password="$3"
  local response

  response="$(curl -sS -b "${COOKIE_JAR}" -X POST "http://127.0.0.1:${PORT}/api/v1/user" \
    -H "Content-Type: application/json" \
    -d "{\"login\":\"${login}\",\"name\":\"${display_name}\",\"type\":\"Normal\",\"organisation\":\"${ORG_NAME}\",\"profile\":\"analyst\"}" || true)"

  if printf '%s' "${response}" | grep -qi 'already\|exists'; then
    echo "El usuario ${login} ya existe."
  elif ! printf '%s' "${response}" | grep -q "\"login\":\"${login}\""; then
    echo "No pude crear usuario ${login}. Respuesta:"
    printf '%s\n' "${response}"
    rm -f "${COOKIE_JAR}"
    exit 1
  fi

  curl -fsS -b "${COOKIE_JAR}" -X POST "http://127.0.0.1:${PORT}/api/v1/user/${login//@/%40}/password/set" \
    -H "Content-Type: application/json" \
    -d "{\"password\":\"${password}\"}" >/dev/null
}

bootstrap_instance() {
  local analyst1_login="analista1@thehive.local"
  local analyst2_login="analista2@thehive.local"

  login_admin
  ADMIN_KEY="${ADMIN_API_KEY:-$(renew_user_key "${ADMIN_USER}")}"
  create_org
  create_lab_user "${analyst1_login}" "Analista 1" "analista1"
  create_lab_user "${analyst2_login}" "Analista 2" "analista2"
  THEHIVE_API_KEY="$(renew_user_key "${analyst1_login}")"
  rm -f "${COOKIE_JAR}"

  echo "Organización: ${ORG_NAME}"
  echo "Usuario analista 1: ${analyst1_login} / analista1"
  echo "Usuario analista 2: ${analyst2_login} / analista2"
}

install_consumer_service() {
  if ! id socia-thehive >/dev/null 2>&1; then
    useradd --system --home "${BASE_DIR}" --shell /usr/sbin/nologin socia-thehive
  fi

  python3 -m venv "${INSTANCE_DIR}/consumer/venv"
  "${INSTANCE_DIR}/consumer/venv/bin/pip" install --upgrade pip >/dev/null
  "${INSTANCE_DIR}/consumer/venv/bin/pip" install -r "${INSTANCE_DIR}/consumer/requirements.txt" >/dev/null

  python3 -m venv "${INSTANCE_DIR}/graylog-alert-consumer/venv"
  "${INSTANCE_DIR}/graylog-alert-consumer/venv/bin/pip" install --upgrade pip >/dev/null
  "${INSTANCE_DIR}/graylog-alert-consumer/venv/bin/pip" install -r "${INSTANCE_DIR}/graylog-alert-consumer/requirements.txt" >/dev/null

  replace_tokens "${TEMPLATE_DIR}/graylog-alert-consumer.env.tpl" "${INSTANCE_DIR}/graylog-alert-consumer/.env"
  chmod 0640 "${INSTANCE_DIR}/graylog-alert-consumer/.env"
  chown -R socia-thehive:socia-thehive "${INSTANCE_DIR}/consumer" "${INSTANCE_DIR}/graylog-alert-consumer"

  replace_tokens "${TEMPLATE_DIR}/graylog-alert-consumer.service.tpl" "/etc/systemd/system/graylog-alert-consumer-${INSTANCE}.service"
  "${INSTANCE_DIR}/graylog-alert-consumer/venv/bin/python" -m py_compile "${INSTANCE_DIR}/graylog-alert-consumer/graylog-alert-consumer.py"
  systemctl daemon-reload
  systemctl enable --now "graylog-alert-consumer-${INSTANCE}.service"
}

configure_cortex() {
  if [[ "${CORTEX_ENABLED,,}" =~ ^(0|false|no)$ ]]; then
    echo "CORTEX_ENABLED=false; se omite la configuración Cortex para ${INSTANCE}."
    return 0
  fi
  if [[ ! -x "${INSTANCE_DIR}/consumer/venv/bin/python" ]]; then
    echo "No existe venv del consumer; se omite la configuración Cortex para ${INSTANCE}."
    return 0
  fi

  echo "Configurando conexión Cortex para ${INSTANCE}..."
  local instance_cortex_key
  instance_cortex_key="$(ensure_instance_cortex_key)"
  THEHIVE_URL="http://127.0.0.1:${PORT}" \
  THEHIVE_ADMIN_KEY="${ADMIN_KEY}" \
  THEHIVE_ADMIN_USER="${ADMIN_USER}" \
  THEHIVE_ADMIN_PASSWORD="${ADMIN_PASSWORD}" \
  CORTEX_COPY_FROM_URL="${CORTEX_COPY_FROM_URL}" \
  CORTEX_URL="${CORTEX_URL}" \
  CORTEX_NAME="${CORTEX_NAME}" \
  CORTEX_API_KEY="${instance_cortex_key}" \
  CORTEX_ANALYZERS="${CORTEX_ANALYZERS}" \
  CORTEX_CONFIGURE_ANALYZERS="${CORTEX_CONFIGURE_ANALYZERS}" \
  "${INSTANCE_DIR}/consumer/venv/bin/python" <<'PY'
import os
import sys

import requests


def truthy(value):
    return str(value or "").lower() in {"1", "true", "yes"}


def bearer_session(key):
    session = requests.Session()
    session.headers.update({"Authorization": f"Bearer {key}"})
    return session


def host_reachable_cortex_url(url):
    normalized = url.rstrip("/")
    if normalized in {"http://cortex:9001", "https://cortex:9001"}:
        return normalized.replace("://cortex:", "://127.0.0.1:")
    return normalized


def fail(message):
    print(message, file=sys.stderr)
    sys.exit(1)


thehive = os.environ["THEHIVE_URL"].rstrip("/")
admin_key = os.environ["THEHIVE_ADMIN_KEY"]
session = bearer_session(admin_key)

cortex_key = os.environ.get("CORTEX_API_KEY", "").strip()
if cortex_key:
    config = {
        "statusCheckInterval": "1 minute",
        "refreshDelay": "5 seconds",
        "maxRetryOnError": 3,
        "jobTimeout": "3 hours",
        "servers": [
            {
                "name": os.environ.get("CORTEX_NAME", "Cortex"),
                "url": os.environ.get("CORTEX_URL", "http://cortex:9001").rstrip("/"),
                "auth": {"type": "bearer", "key": cortex_key},
                "wsConfig": {},
                "includedTheHiveOrganisations": ["*"],
                "excludedTheHiveOrganisations": [],
                "maxResponseSize": 1048576,
                "numberOfConcurrentSubmission": 10,
            }
        ],
    }
else:
    source = os.environ.get("CORTEX_COPY_FROM_URL", "http://127.0.0.1:9000").rstrip("/")
    if source == thehive:
        source_session = bearer_session(admin_key)
    else:
        source_session = requests.Session()
        login = source_session.post(
            f"{source}/api/v1/login",
            json={
                "user": os.environ["THEHIVE_ADMIN_USER"],
                "password": os.environ["THEHIVE_ADMIN_PASSWORD"],
            },
            timeout=20,
        )
        if login.status_code != 200:
            fail(f"No pude iniciar sesión en TheHive origen {source}: HTTP {login.status_code} {login.text[:300]}")
    copied = source_session.get(f"{source}/api/v1/admin/config/cortex", timeout=20)
    if copied.status_code == 404:
        print("No hay configuración Cortex en el TheHive principal; se omite Cortex.")
        sys.exit(0)
    if copied.status_code != 200:
        fail(f"No pude leer Cortex desde {source}: HTTP {copied.status_code} {copied.text[:300]}")
    config = copied.json()

servers = config.get("servers") or []
if not servers:
    print("La configuración Cortex no contiene servidores; se omite Cortex.")
    sys.exit(0)

update = session.put(f"{thehive}/api/v1/admin/config/cortex", json=config, timeout=30)
if update.status_code not in {200, 204}:
    fail(f"No se pudo guardar Cortex: HTTP {update.status_code} {update.text[:500]}")

print(f"Conexión Cortex configurada con {len(servers)} servidor(es).")

if not truthy(os.environ.get("CORTEX_CONFIGURE_ANALYZERS", "true")):
    sys.exit(0)

server = servers[0]
auth = server.get("auth") or {}
if auth.get("type") != "bearer" or not auth.get("key"):
    print("No se puede verificar analizadores: la autenticación Cortex no es bearer/key.")
    sys.exit(0)

cortex = host_reachable_cortex_url(server.get("url", os.environ.get("CORTEX_URL", "http://cortex:9001")))
cortex_session = bearer_session(auth["key"])
enabled = cortex_session.get(f"{cortex}/api/organization/analyzer", timeout=30)
if enabled.status_code != 200:
    fail(f"No pude listar analizadores Cortex: HTTP {enabled.status_code} {enabled.text[:500]}")

enabled_analyzers = enabled.json()
enabled_names = {item.get("name") for item in enabled_analyzers}
requested = [item.strip() for item in os.environ.get("CORTEX_ANALYZERS", "").split(",") if item.strip()]
if not requested:
    source = os.environ.get("CORTEX_COPY_FROM_URL", "http://127.0.0.1:9000").rstrip("/")
    source_session = requests.Session()
    login = source_session.post(
        f"{source}/api/v1/login",
        json={
            "user": os.environ["THEHIVE_ADMIN_USER"],
            "password": os.environ["THEHIVE_ADMIN_PASSWORD"],
        },
        timeout=20,
    )
    if login.status_code == 200:
        copied = source_session.get(f"{source}/api/v1/admin/config/cortex", timeout=20)
        if copied.status_code == 200:
            source_servers = copied.json().get("servers") or []
            source_auth = (source_servers[0].get("auth") if source_servers else {}) or {}
            if source_auth.get("type") == "bearer" and source_auth.get("key"):
                source_cortex = host_reachable_cortex_url(source_servers[0].get("url", os.environ.get("CORTEX_URL", "http://cortex:9001")))
                source_enabled = bearer_session(source_auth["key"]).get(f"{source_cortex}/api/organization/analyzer", timeout=30)
                if source_enabled.status_code == 200:
                    requested = [item.get("name") for item in source_enabled.json() if item.get("name")]
                    if requested:
                        print("Analizadores Cortex copiados del principal: " + ", ".join(requested))

for analyzer in requested:
    if analyzer in enabled_names:
        continue

    definitions_response = cortex_session.get(f"{cortex}/api/analyzerdefinition", timeout=30)
    if definitions_response.status_code != 200:
        fail(f"No pude listar definiciones Cortex: HTTP {definitions_response.status_code} {definitions_response.text[:500]}")
    definitions = {item.get("id"): item for item in definitions_response.json()}

    config_response = cortex_session.get(f"{cortex}/api/analyzerconfig", timeout=30)
    if config_response.status_code != 200:
        fail(f"No pude leer configuración de analizadores Cortex: HTTP {config_response.status_code} {config_response.text[:500]}")
    configs_by_worker = {}
    for item in config_response.json():
        for worker in item.get("workers") or []:
            configs_by_worker[worker] = item.get("config") or {}

    definition = definitions.get(analyzer)
    if not definition:
        fail(f"No existe definición Cortex para {analyzer}. Revisa el montaje de Cortex-Analyzers en el stack principal.")

    payload = {"name": analyzer}
    worker_name = definition.get("name")
    config = configs_by_worker.get(worker_name, {})
    allowed = {item.get("name") for item in definition.get("configurationItems") or [] if item.get("name")}
    filtered = {key: value for key, value in config.items() if not allowed or key in allowed}
    if filtered:
        payload["configuration"] = filtered

    created = cortex_session.post(f"{cortex}/api/organization/analyzer/{analyzer}", json=payload, timeout=30)
    if created.status_code not in {200, 201, 204, 409}:
        fail(f"No se pudo habilitar analizador {analyzer}: HTTP {created.status_code} {created.text[:500]}")
    print(f"Analizador Cortex habilitado: {analyzer}")

if enabled_analyzers or requested:
    final = cortex_session.get(f"{cortex}/api/organization/analyzer", timeout=30)
    names = [item.get("name", "unknown") for item in final.json()] if final.status_code == 200 else sorted(enabled_names)
    print("Analizadores Cortex disponibles: " + ", ".join(names))
else:
    print("Cortex no tiene analizadores habilitados. Define CORTEX_ANALYZERS=Nombre_1,Nombre_2 para habilitarlos.")
PY
}

configure_misp() {
  if [[ ! -x "${INSTANCE_DIR}/consumer/venv/bin/python" ]]; then
    echo "No existe venv del consumer; se omite la configuración MISP para ${INSTANCE}."
    return 0
  fi

  echo "Configurando conexión MISP para ${INSTANCE}..."
  THEHIVE_URL="http://127.0.0.1:${PORT}" \
  THEHIVE_ADMIN_KEY="${ADMIN_KEY}" \
  THEHIVE_ADMIN_USER="${ADMIN_USER}" \
  THEHIVE_ADMIN_PASSWORD="${ADMIN_PASSWORD}" \
  MISP_COPY_FROM_URL="${MISP_COPY_FROM_URL:-http://127.0.0.1:9000}" \
  MISP_URL="${MISP_URL}" \
  MISP_API_KEY="${MISP_API_KEY}" \
  MISP_NAME="${MISP_NAME}" \
  MISP_PURPOSE="${MISP_PURPOSE}" \
  MISP_INTERVAL="${MISP_INTERVAL}" \
  MISP_ACCEPT_ANY_CERT="${MISP_ACCEPT_ANY_CERT}" \
  "${INSTANCE_DIR}/consumer/venv/bin/python" <<'PY'
import os
import sys

import requests

base = os.environ["THEHIVE_URL"].rstrip("/")
session = requests.Session()
session.headers.update({"Authorization": f"Bearer {os.environ['THEHIVE_ADMIN_KEY']}"})

if os.environ.get("MISP_API_KEY", "").strip():
    accept_any_cert = os.environ.get("MISP_ACCEPT_ANY_CERT", "true").lower() in {"1", "true", "yes"}
    server = {
        "name": os.environ.get("MISP_NAME", "MISP local"),
        "url": os.environ["MISP_URL"].rstrip("/"),
        "auth": {"type": "key", "key": os.environ["MISP_API_KEY"]},
        "purpose": os.environ.get("MISP_PURPOSE", "ImportAndExport"),
        "wsConfig": {
            "proxy": {"protocol": "http"},
            "ssl": {
                "loose": {
                    "acceptAnyCertificate": accept_any_cert,
                    "checkCertificateAuthority": not accept_any_cert,
                }
            },
        },
        "includedTheHiveOrganisations": ["*"],
        "excludedTheHiveOrganisations": [],
        "tags": ["misp"],
        "maxAge": None,
        "max-attributes": None,
        "whitelist": {"organisations": [], "tags": []},
        "exclusion": {"organisations": [], "tags": []},
        "exportCaseTags": False,
        "exportObservableTags": False,
        "exportTheHiveUrl": False,
    }
    config = {"interval": os.environ.get("MISP_INTERVAL", "10 minutes"), "servers": [server]}
else:
    source = os.environ.get("MISP_COPY_FROM_URL", "http://127.0.0.1:9000").rstrip("/")
    source_session = requests.Session()
    login = source_session.post(
        f"{source}/api/v1/login",
        json={
            "user": os.environ["THEHIVE_ADMIN_USER"],
            "password": os.environ["THEHIVE_ADMIN_PASSWORD"],
        },
        timeout=20,
    )
    if login.status_code != 200:
        print(f"No pude iniciar sesión en TheHive origen {source}: HTTP {login.status_code} {login.text[:300]}", file=sys.stderr)
        sys.exit(1)
    copied = source_session.get(f"{source}/api/v1/admin/config/misp", timeout=20)
    if copied.status_code == 404:
        print("No hay configuración MISP en el TheHive principal; se omite MISP.")
        sys.exit(0)
    if copied.status_code != 200:
        print(f"No pude leer MISP desde {source}: HTTP {copied.status_code} {copied.text[:300]}", file=sys.stderr)
        sys.exit(1)
    config = copied.json()

servers = config.get("servers") or []
if not servers:
    print("La configuración MISP no contiene servidores; se omite MISP.")
    sys.exit(0)

for server in servers:
    test = session.post(f"{base}/api/v1/admin/config/misp/test", json=server, timeout=30)
    if test.status_code != 200:
        print(f"Test MISP falló para {server.get('name', server.get('url', 'MISP'))}: HTTP {test.status_code} {test.text[:500]}", file=sys.stderr)
        sys.exit(1)

update = session.put(f"{base}/api/v1/admin/config/misp", json=config, timeout=30)
if update.status_code != 204:
    print(f"No se pudo guardar MISP: HTTP {update.status_code} {update.text[:500]}", file=sys.stderr)
    sys.exit(1)

print(f"Conexión MISP configurada correctamente con {len(servers)} servidor(es).")
PY
}

NO_CONSUMER=0
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -lt 2 ]]; then
  usage
  exit 0
fi

INSTANCE="$1"
PORT="$2"
shift 2

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-consumer)
      NO_CONSUMER=1
      ;;
    *)
      echo "Opcion desconocida: $1"
      usage
      exit 1
      ;;
  esac
  shift
done

need_root
require_cmd docker
require_cmd curl
require_cmd sed
require_cmd ss
require_cmd python3
validate_instance "${INSTANCE}"
validate_port "${PORT}"
TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/templates" && pwd)"
INSTANCE_DIR="${BASE_DIR}/${INSTANCE}"
ORG_NAME="${ORG_NAME_DEFAULT}"
THEHIVE_API_KEY=""
ADMIN_KEY=""
COOKIE_JAR=""
COOKIE_NAME="THEHIVE_SESSION_${INSTANCE//-/_}"
INSTANCE_CQL="${INSTANCE//-/_}"
THEHIVE_KEYSPACE="${THEHIVE_KEYSPACE_PREFIX}_${INSTANCE_CQL}"
THEHIVE_INDEX="${THEHIVE_INDEX_PREFIX}-${INSTANCE}"
validate_cql_identifier "THEHIVE_KEYSPACE" "${THEHIVE_KEYSPACE}"
validate_es_index "${THEHIVE_INDEX}"

if [[ -e "${INSTANCE_DIR}" ]]; then
  echo "La instancia ya existe: ${INSTANCE_DIR}"
  exit 1
fi

wait_for_shared_backends
prepare_shared_storage

install -d "${INSTANCE_DIR}/thehive/config" "${INSTANCE_DIR}/consumer" "${INSTANCE_DIR}/graylog-alert-consumer"
replace_tokens "${TEMPLATE_DIR}/docker-compose.yml.tpl" "${INSTANCE_DIR}/docker-compose.yml"
replace_tokens "${TEMPLATE_DIR}/application.conf.tpl" "${INSTANCE_DIR}/thehive/config/application.conf"
cp "${SOURCE_DIR}/consumer/thehive-consumer.py" "${INSTANCE_DIR}/consumer/thehive-consumer.py"
cp "${SOURCE_DIR}/consumer/requirements.txt" "${INSTANCE_DIR}/consumer/requirements.txt"
cp "${SOURCE_DIR}/graylog-alert-consumer/graylog-alert-consumer.py" "${INSTANCE_DIR}/graylog-alert-consumer/graylog-alert-consumer.py"
cp "${SOURCE_DIR}/graylog-alert-consumer/requirements.txt" "${INSTANCE_DIR}/graylog-alert-consumer/requirements.txt"

secret="$(openssl rand -hex 32 2>/dev/null || tr -dc A-Za-z0-9 </dev/urandom | head -c 64)"
printf 'THEHIVE_SECRET=%s\n' "${secret}" >"${INSTANCE_DIR}/.env"

sysctl -w vm.max_map_count=262144 >/dev/null
printf 'vm.max_map_count=262144\n' >/etc/sysctl.d/99-socia-thehive.conf

docker compose -f "${INSTANCE_DIR}/docker-compose.yml" up -d
wait_for_thehive

bootstrap_instance

if [[ "${NO_CONSUMER}" -eq 0 ]]; then
  install_consumer_service
fi
configure_cortex
configure_misp

host_ip="$(hostname -I | awk '{print $1}')"
echo
echo "Instancia creada: ${INSTANCE}"
echo "URL: http://${host_ip}:${PORT}"
echo "Organización: ${ORG_NAME}"
echo "Usuario analista 1: analista1@thehive.local"
echo "Password analista 1: analista1"
echo "Usuario analista 2: analista2@thehive.local"
echo "Password analista 2: analista2"
echo "Kafka group: thehive-socia-${INSTANCE}"
echo "Cassandra keyspace: ${THEHIVE_KEYSPACE}"
echo "Elasticsearch index: ${THEHIVE_INDEX}"
if [[ "${NO_CONSUMER}" -eq 0 ]]; then
  echo "Servicio Graylog alerts: graylog-alert-consumer-${INSTANCE}.service"
fi
