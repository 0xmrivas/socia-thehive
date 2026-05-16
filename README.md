# SOCIA TheHive

Este repositorio contiene el despliegue SOCIA de TheHive, Cortex, Cassandra,
Elasticsearch y consumidores Kafka. La instalación operativa se copia a
`/opt/socia-thehive`; el repositorio fuente está en `/home/debian/socia-thehive`.

## Resumen rápido

Stack base:

```bash
cd /opt/socia-thehive
sudo docker compose up -d
sudo docker compose ps
```

Servicios auxiliares:

```bash
sudo systemctl status thehive-consumer --no-pager
sudo systemctl status graylog-alert-consumer --no-pager
```

Verificación funcional:

```bash
cd /opt/socia-thehive
sudo ./verify.sh
```

Crear instancias de alumnos reutilizando Cassandra y Elasticsearch del stack
base:

```bash
cd /home/debian/socia-thehive/multiinstance-shared-backend
sudo ./create-many.sh 10
```

Programar la creacion de instancias para una fecha y hora concretas:

```bash
cd /home/debian/socia-thehive/multiinstance-shared-backend
sudo ./schedule-create-many.sh 10 "2026-05-20 13:00"
```

Programar el borrado de instancias:

```bash
cd /home/debian/socia-thehive/multiinstance-shared-backend
sudo ./schedule-delete-many.sh 10 "2026-05-20 18:00"
```

Borrar instancias de alumnos:

```bash
cd /home/debian/socia-thehive/multiinstance-shared-backend
sudo ./delete-many.sh 10
```

## Rutas importantes

| Ruta | Uso |
| --- | --- |
| `/home/debian/socia-thehive` | Repositorio fuente. Aquí se documenta y se versiona el despliegue. |
| `/opt/socia-thehive` | Instalación real del stack base. Aquí se ejecuta `docker compose up -d`. |
| `/opt/socia-thehive/.env` | Secretos del stack base Docker: `THEHIVE_SECRET`, `CORTEX_SECRET`, ruta de jobs Cortex. |
| `/opt/socia-thehive/consumer/.env` | Configuración y API key del consumidor Kafka `ioc-events`. |
| `/opt/socia-thehive/graylog-alert-consumer/.env` | Configuración y API key del consumidor Kafka `graylog-alerts`. |
| `/opt/socia-students/<instancia>` | Instancias de alumnos creadas con backend compartido. |
| `/etc/systemd/system/thehive-consumer.service` | Servicio systemd del consumidor principal de `ioc-events`. |
| `/etc/systemd/system/graylog-alert-consumer.service` | Servicio systemd del consumidor principal de `graylog-alerts`. |
| `/etc/systemd/system/graylog-alert-consumer-<instancia>.service` | Servicio systemd por instancia de alumno. |

No subas `.env` reales al repositorio. Contienen API keys y secretos.

## Stack base: los 4 contenedores principales

El stack base se define en:

```text
/opt/socia-thehive/docker-compose.yml
```

Los 4 contenedores principales son:

| Contenedor | Servicio | Puerto publicado | Función |
| --- | --- | --- | --- |
| `socia-cassandra` | Cassandra 4.1 | No publicado al host | Base de datos principal de TheHive. |
| `socia-elasticsearch` | Elasticsearch 7.17.24 | No publicado al host | Índices de búsqueda de TheHive. |
| `socia-thehive` | TheHive 5.2 | `9000` | Interfaz y API principal de TheHive. |
| `socia-cortex` | Cortex 3.1.7 | `9001` | Ejecución de analizadores Cortex. |

Los 4 tienen `restart: unless-stopped`. Eso significa:

- Si un contenedor cae por error, Docker intenta levantarlo de nuevo.
- Si el servidor reinicia y Docker arranca, los contenedores vuelven a arrancar.
- Si alguien ejecuta `docker compose stop` o `docker compose down`, Docker entiende
  que se han parado manualmente y no los levanta hasta ejecutar `docker compose up -d`.

Orden lógico de arranque:

1. `socia-cassandra`
2. `socia-elasticsearch`
3. `socia-thehive`, cuando Cassandra y Elasticsearch están saludables
4. `socia-cortex`, cuando Elasticsearch está saludable

Comandos habituales:

```bash
cd /opt/socia-thehive

# Levantar o reconciliar el stack completo.
sudo docker compose up -d

# Ver estado de los 4 servicios.
sudo docker compose ps

# Ver logs del stack.
sudo docker compose logs --tail=100

# Ver logs de un servicio concreto.
sudo docker compose logs --tail=150 thehive
sudo docker compose logs --tail=150 cortex
sudo docker compose logs --tail=150 cassandra
sudo docker compose logs --tail=150 elasticsearch

# Reiniciar todos los contenedores del stack.
sudo docker compose restart

# Reiniciar solo TheHive.
sudo docker compose restart thehive
```

No uses `docker compose down -v` sobre el stack base salvo que quieras borrar los
volúmenes persistentes del stack base.

## Volúmenes y datos persistentes del stack base

El stack base usa estos volúmenes Docker:

| Volumen | Contenedor | Datos |
| --- | --- | --- |
| `socia-thehive_cassandra-data` | `socia-cassandra` | Keyspaces Cassandra. |
| `socia-thehive_elasticsearch-data` | `socia-elasticsearch` | Índices Elasticsearch. |
| `socia-thehive_thehive-files` | `socia-thehive` | Ficheros adjuntos de TheHive. |
| `socia-thehive_thehive-logs` | `socia-thehive` | Logs de TheHive. |
| `socia-thehive_cortex-logs` | `socia-cortex` | Logs de Cortex. |

También puede existir un volumen anónimo montado por Cortex en `/var/lib/docker`.
No lo borres a mano si está montado por `socia-cortex`.

Comprobar volúmenes:

```bash
sudo docker volume ls
sudo docker system df
```

Comprobar qué monta un contenedor:

```bash
sudo docker inspect socia-cortex
```

## Red Docker

El stack base crea la red:

```text
socia-thehive
```

La usan los 4 contenedores base y las instancias de alumnos con backend
compartido. No borres esta red mientras haya contenedores SOCIA funcionando.

Comprobar redes:

```bash
sudo docker network ls
sudo docker network inspect socia-thehive
```

## Servicios systemd principales

Además de Docker, hay consumidores Python gestionados por systemd.

### `thehive-consumer.service`

Lee eventos desde Kafka topic `ioc-events` y crea alertas en TheHive principal.

Ficheros:

```text
/opt/socia-thehive/consumer/thehive-consumer.py
/opt/socia-thehive/consumer/.env
/etc/systemd/system/thehive-consumer.service
```

Comandos:

```bash
sudo systemctl status thehive-consumer --no-pager
sudo systemctl restart thehive-consumer
sudo journalctl -u thehive-consumer -f
sudo journalctl -u thehive-consumer --since "30 min ago" --no-pager
```

El servicio tiene `Restart=always`, por lo que systemd lo relanza si el proceso
Python cae.

### `graylog-alert-consumer.service`

Lee eventos desde Kafka topic `graylog-alerts` y crea alertas en TheHive
principal.

Ficheros:

```text
/opt/socia-thehive/graylog-alert-consumer/graylog-alert-consumer.py
/opt/socia-thehive/graylog-alert-consumer/.env
/etc/systemd/system/graylog-alert-consumer.service
```

Comandos:

```bash
sudo systemctl status graylog-alert-consumer --no-pager
sudo systemctl restart graylog-alert-consumer
sudo journalctl -u graylog-alert-consumer -f
sudo journalctl -u graylog-alert-consumer --since "30 min ago" --no-pager
```

## API keys y secretos

Hay varios tipos de secreto. No son intercambiables.

### Secretos internos Docker

Fichero:

```text
/opt/socia-thehive/.env
```

Variables:

| Variable | Uso |
| --- | --- |
| `THEHIVE_SECRET` | Secreto interno de TheHive para criptografía/sesiones. |
| `THEHIVE_PUBLIC_URL` | URL pública esperada de TheHive principal. |
| `CORTEX_SECRET` | Secreto interno de Cortex. |
| `CORTEX_DOCKER_JOB_DIRECTORY` | Ruta host para jobs de Cortex. |

Ejemplo sin secretos reales:

```env
THEHIVE_SECRET=replace-with-a-long-random-secret
THEHIVE_PUBLIC_URL=http://127.0.0.1:9000
CORTEX_SECRET=replace-with-a-long-random-secret
CORTEX_DOCKER_JOB_DIRECTORY=/opt/socia-thehive/cortex/jobs
```

Si cambias `THEHIVE_SECRET` o `CORTEX_SECRET` en un sistema ya usado, puedes
romper sesiones, tokens o datos cifrados. Trátalos como secretos persistentes.

### API key de TheHive para consumidores

Ficheros:

```text
/opt/socia-thehive/consumer/.env
/opt/socia-thehive/graylog-alert-consumer/.env
```

Variable principal:

```env
THEHIVE_API_KEY=...
```

La usa el consumidor para llamar a la API de TheHive. El instalador intenta
obtenerla renovando la key del usuario admin:

```text
admin@thehive.local
```

Si la key se revoca o deja de funcionar, el consumidor seguirá vivo pero fallará
al crear alertas. Síntomas habituales:

```bash
sudo journalctl -u thehive-consumer --since "30 min ago" --no-pager
sudo journalctl -u graylog-alert-consumer --since "30 min ago" --no-pager
```

Después de cambiar la key en `.env`, reinicia el servicio:

```bash
sudo systemctl restart thehive-consumer
sudo systemctl restart graylog-alert-consumer
```

### API key de MISP

Se puede pasar durante la instalación o durante la creación de instancias:

```bash
sudo MISP_API_KEY='...' ./install.sh
sudo MISP_API_KEY='...' ./create-instance.sh contenedor1 9101
```

Valores por defecto:

```text
MISP_URL=https://172.17.33.145
MISP_NAME=MISP local
MISP_PURPOSE=ImportAndExport
MISP_INTERVAL=10 minutes
MISP_ACCEPT_ANY_CERT=true
```

En instancias con backend compartido, si no pasas `MISP_API_KEY`, el script
intenta copiar la configuración MISP desde TheHive principal:

```text
MISP_COPY_FROM_URL=http://127.0.0.1:9000
```

### API key de Cortex

En instancias de alumnos, el script intenta copiar la configuración Cortex del
TheHive principal. También se puede forzar una key:

```bash
sudo CORTEX_API_KEY='...' ./create-instance.sh contenedor1 9101
```

Variables útiles:

```text
CORTEX_ENABLED=true
CORTEX_COPY_FROM_URL=http://127.0.0.1:9000
CORTEX_URL=http://cortex:9001
CORTEX_NAME=Cortex
CORTEX_CONFIGURE_ANALYZERS=true
CORTEX_ANALYZERS=AbuseIPDB_2_0,VirusTotal_GetReport_3_1
```

Si `CORTEX_ANALYZERS` está vacío, el script intenta copiar la lista de
analizadores habilitados en el Cortex usado por el TheHive principal.

### Backup único de secretos y tokens

Para no perder API keys, tokens y configuración sensible, hay un script de
backup operativo:

```bash
sudo /opt/socia-thehive/backup-secrets.sh
```

Genera una carpeta y un `.tgz` en:

```text
/opt/socia-thehive/secret-backup/
```

Incluye, si existen:

- `.env` del stack base.
- `.env` de consumidores.
- `.env` de instancias de alumnos.
- Configuración MISP de TheHive.
- Configuración Cortex de TheHive.
- Configuración de analizadores Cortex.
- Lista de analizadores habilitados.

Ese directorio contiene secretos reales. No lo subas a Git. Lo normal es
copiar el `.tgz` generado a un sitio seguro externo.

## Instalación base desde cero

Ejecutar desde el repositorio fuente:

```bash
cd /home/debian/socia-thehive
sudo ./install.sh
```

El instalador hace lo siguiente:

1. Instala dependencias del sistema: Docker, Compose plugin, `jq`, `openssl`,
   `python3-venv`, `python3-pip`.
2. Habilita y arranca Docker.
3. Ajusta `vm.max_map_count=262144` para Elasticsearch.
4. Crea el usuario de sistema `socia-thehive` si no existe.
5. Copia el repositorio a `/opt/socia-thehive`.
6. Crea `/opt/socia-thehive/.env` si no existe.
7. Crea venvs Python para los consumidores.
8. Levanta el stack Docker base con `docker compose up -d`.
9. Espera a que TheHive responda en `/api/status`.
10. Obtiene una API key para el consumidor.
11. Instala y arranca los servicios systemd de consumidores.
12. Configura MISP si se ha pasado `MISP_API_KEY`.

Variables frecuentes de instalación:

```bash
sudo \
  THEHIVE_URL='http://127.0.0.1:9000' \
  THEHIVE_ADMIN_EMAIL='admin@thehive.local' \
  THEHIVE_ADMIN_PASSWORD='secret' \
  THEHIVE_ORG='IES Rafael Alberti' \
  KAFKA_BOOTSTRAP_SERVERS='172.17.33.153:9092' \
  MISP_API_KEY='...' \
  ./install.sh
```

Si TheHive está recién instalado y aún no se completó el asistente inicial, el
instalador puede detenerse al intentar obtener la API key. En ese caso:

1. Entra en `http://IP_DEL_SERVIDOR:9000`.
2. Completa la configuración inicial.
3. Vuelve a ejecutar `sudo ./install.sh`.

## Recuperación si cae algo

### Ver estado general

```bash
sudo systemctl status docker --no-pager
cd /opt/socia-thehive
sudo docker compose ps
sudo systemctl status thehive-consumer --no-pager
sudo systemctl status graylog-alert-consumer --no-pager
```

### Docker está parado

```bash
sudo systemctl restart docker
cd /opt/socia-thehive
sudo docker compose up -d
```

### Falta uno de los 4 contenedores base

```bash
cd /opt/socia-thehive
sudo docker compose up -d
sudo docker compose ps
```

### TheHive no responde

```bash
cd /opt/socia-thehive
sudo docker compose logs --tail=200 thehive
sudo docker compose logs --tail=200 cassandra
sudo docker compose logs --tail=200 elasticsearch
```

Cassandra y Elasticsearch deben estar saludables antes de que TheHive quede
usable.

### Consumidor no crea alertas

```bash
sudo systemctl status thehive-consumer --no-pager
sudo journalctl -u thehive-consumer --since "1 hour ago" --no-pager
```

Revisa especialmente:

- Conectividad con Kafka.
- Topic configurado en `KAFKA_TOPIC`.
- `THEHIVE_API_KEY` válida.
- Organización configurada en `THEHIVE_ORG`.
- Filtros `THEHIVE_ALLOWED_RULE_IDS` y `THEHIVE_DROP_RULE_IDS`.

### Graylog alerts no llegan

```bash
sudo systemctl status graylog-alert-consumer --no-pager
sudo journalctl -u graylog-alert-consumer --since "1 hour ago" --no-pager
```

Revisa:

- `KAFKA_TOPIC=graylog-alerts`.
- `KAFKA_GROUP_ID`.
- API key de TheHive.
- Logs de parsing del consumidor.

## Verificación

El script:

```bash
/opt/socia-thehive/verify.sh
```

comprueba:

1. Contenedores base Docker.
2. HTTP 200 en `THEHIVE_URL/api/status`.
3. Servicio `thehive-consumer`.
4. Envío de mensaje de prueba a Kafka.
5. Creación de alerta de prueba en TheHive.

Ejecutar:

```bash
cd /opt/socia-thehive
sudo ./verify.sh
```

Para que la prueba de Kafka funcione debe existir algún productor disponible:
`kcat`, `kafka-console-producer` o un contenedor Kafka accesible.

## Instancias de alumnos con backend compartido

La opción recomendada para aulas está en:

```text
/home/debian/socia-thehive/multiinstance-shared-backend
```

Esta modalidad reutiliza:

```text
socia-cassandra
socia-elasticsearch
red Docker socia-thehive
socia-cortex
```

Cada alumno recibe solo:

```text
socia-<instancia>-thehive
socia-<instancia>-thehive-files
socia-<instancia>-thehive-logs
graylog-alert-consumer-<instancia>.service
```

Los datos se separan así:

| Recurso | Nombre ejemplo para `contenedor1` |
| --- | --- |
| Contenedor TheHive | `socia-contenedor1-thehive` |
| Puerto | `9101` |
| Cassandra keyspace | `thehive_contenedor1` |
| Elasticsearch index | `thehive-contenedor1` |
| Cookie de sesión | `THEHIVE_SESSION_contenedor1` |
| Servicio Graylog | `graylog-alert-consumer-contenedor1.service` |

Requisitos:

```bash
cd /opt/socia-thehive
sudo docker compose up -d
sudo docker compose ps
```

Crear una instancia:

```bash
cd /home/debian/socia-thehive/multiinstance-shared-backend
sudo ./create-instance.sh contenedor1 9101
```

Crear 10 instancias:

```bash
cd /home/debian/socia-thehive/multiinstance-shared-backend
sudo ./create-many.sh 10
```

Crear 10 instancias con otro prefijo y otro rango de puertos:

```bash
sudo PREFIX=alumno START_INDEX=1 START_PORT=9201 ./create-many.sh 10
```

Crear instancias sin consumidor por instancia:

```bash
sudo NO_CONSUMER=1 ./create-many.sh 10
```

Usuarios creados por instancia:

| Instancia | Usuario analista | Password | Usuario forense | Password |
| --- | --- | --- | --- | --- |
| `contenedor1` | `analista1@thehive.local` | `analista1` | `forense1@thehive.local` | `forense1` |
| `contenedor2` | `analista2@thehive.local` | `analista2` | `forense2@thehive.local` | `forense2` |

La instancia debe terminar en número porque el script usa ese número para crear
`analistaX` y `forenseX`.

Variables útiles:

```bash
sudo \
  BASE_DIR=/opt/socia-students \
  KAFKA_BOOTSTRAP_SERVERS=172.17.33.153:9092 \
  ADMIN_USER=admin@thehive.local \
  ADMIN_PASSWORD=secret \
  CORTEX_ENABLED=true \
  MISP_API_KEY='...' \
  ./create-instance.sh contenedor1 9101
```

El script hace lo siguiente:

1. Comprueba que existe la red `socia-thehive`.
2. Comprueba que `socia-cassandra` responde a CQL.
3. Comprueba que `socia-elasticsearch` responde con cluster health yellow o
   green.
4. Crea keyspace Cassandra propio.
5. Genera `/opt/socia-students/<instancia>/docker-compose.yml`.
6. Genera configuración TheHive propia.
7. Levanta el contenedor `socia-<instancia>-thehive`.
8. Crea organización `SOCIA`.
9. Crea usuario analista y forense.
10. Renueva API key del analista para el consumidor de esa instancia.
11. Instala `graylog-alert-consumer-<instancia>.service`, salvo `--no-consumer`.
12. Configura Cortex.
13. Configura MISP copiando del principal o usando `MISP_API_KEY`.

## Instancias multiinstance completas

Existe otra modalidad en:

```text
/home/debian/socia-thehive/multiinstance
```

Esa modalidad crea una pila completa por alumno:

```text
socia-contenedor1-thehive
socia-contenedor1-cassandra
socia-contenedor1-elasticsearch
volúmenes propios
red propia
```

Úsala solo si necesitas aislamiento completo de Cassandra y Elasticsearch por
alumno. Consume bastante más RAM y disco que la modalidad con backend
compartido.

Comandos:

```bash
cd /home/debian/socia-thehive/multiinstance
sudo ./create-instance.sh contenedor1 9101
sudo ./create-many.sh 5
sudo ./delete-instance.sh contenedor1
```

## Borrado de instancias de alumnos

### Borrar una instancia con backend compartido

```bash
cd /home/debian/socia-thehive/multiinstance-shared-backend
sudo ./delete-instance.sh contenedor1
```

Por defecto borra:

- Servicio `thehive-consumer-contenedor1.service` si existe.
- Servicio `graylog-alert-consumer-contenedor1.service`.
- Contenedor `socia-contenedor1-thehive`.
- Volúmenes Docker de esa instancia.
- Directorio `/opt/socia-students/contenedor1`.
- Keyspace Cassandra `thehive_contenedor1`.
- Índices Elasticsearch `thehive-contenedor1*`.

Conservar datos compartidos:

```bash
sudo ./delete-instance.sh contenedor1 --keep-shared-data
```

Esto borra contenedor, volúmenes y servicios, pero conserva keyspace e índices.
Útil si quieres investigar o recuperar datos.

### Borrar muchas instancias

```bash
cd /home/debian/socia-thehive/multiinstance-shared-backend
sudo ./delete-many.sh 10
```

Borrar todas las que coincidan con el prefijo:

```bash
sudo ./delete-many.sh --all
```

Conservar keyspaces e índices durante borrado masivo:

```bash
sudo KEEP_SHARED_DATA=1 ./delete-many.sh 10
sudo KEEP_SHARED_DATA=1 ./delete-many.sh --all
```

Usar otro prefijo:

```bash
sudo PREFIX=alumno START_INDEX=1 ./delete-many.sh 10
```

## Limpieza después de borrar contenedores

Comprobaciones seguras:

```bash
sudo docker ps -a
sudo docker volume ls
sudo docker network ls
sudo docker images
sudo docker system df
```

Contenedores parados:

```bash
sudo docker ps -a --filter status=exited --filter status=created --filter status=dead
```

Imágenes dangling:

```bash
sudo docker images --filter dangling=true
```

No borres automáticamente imágenes de analizadores Cortex si no tienes claro si
Cortex las usa. Ejemplos de imágenes que pueden estar sin contenedor permanente
pero ser necesarias para jobs:

```text
ghcr.io/thehive-project/abuseipdb:2
ghcr.io/thehive-project/anyrun_sandbox_analysis:1
ghcr.io/thehive-project/virustotal_getreport:3
```

Para limpiar recursos Docker no usados:

```bash
sudo docker system prune
```

No uses `sudo docker system prune -a --volumes` en este entorno salvo que sepas
exactamente qué vas a perder. Puede borrar imágenes necesarias y volúmenes con
datos persistentes.

## Puertos

| Puerto | Servicio |
| --- | --- |
| `9000` | TheHive principal |
| `9001` | Cortex principal |
| `9101`, `9102`, ... | Instancias de alumnos por defecto |
| `9201`, `9202`, ... | Rango alternativo si se usa `START_PORT=9201` |

Comprobar si un puerto está ocupado:

```bash
sudo ss -ltnp
sudo ss -ltn "( sport = :9101 )"
```

## Kafka

Valores por defecto:

```text
KAFKA_BOOTSTRAP_SERVERS=172.17.33.153:9092
KAFKA_TOPIC=ioc-events
GRAYLOG_ALERT_KAFKA_TOPIC=graylog-alerts
KAFKA_AUTO_OFFSET_RESET=earliest
KAFKA_MAX_POLL_RECORDS=50
```

Consumidor principal `ioc-events`:

```text
KAFKA_GROUP_ID=thehive-socia
```

Consumidor principal `graylog-alerts`:

```text
KAFKA_GROUP_ID=thehive-docker-<ip-del-host-con-guiones>
```

Consumidores por instancia:

```text
thehive-graylog-contenedor1
thehive-graylog-contenedor2
```

Cada instancia usa grupo distinto para que todas reciban las mismas alertas del
topic `graylog-alerts`.

## Filtros y agregación de alertas

Variables del consumidor principal:

```text
THEHIVE_ALLOWED_RULE_IDS=31151,31104,5763,40111,5758,5551
THEHIVE_DROP_RULE_IDS=31101,5760
THEHIVE_AGGREGATE_RULE_IDS=31151
THEHIVE_AGGREGATION_WINDOW_SECONDS=10
THEHIVE_AGGREGATION_MAX_EXAMPLES=20
```

Significado:

- `THEHIVE_ALLOWED_RULE_IDS`: solo se aceptan esas reglas si está definido.
- `THEHIVE_DROP_RULE_IDS`: reglas que se descartan.
- `THEHIVE_AGGREGATE_RULE_IDS`: reglas que se agrupan antes de crear alerta.
- `THEHIVE_AGGREGATION_WINDOW_SECONDS`: ventana de agrupación.
- `THEHIVE_AGGREGATION_MAX_EXAMPLES`: número máximo de ejemplos incluidos.

Después de cambiar variables:

```bash
sudo systemctl restart thehive-consumer
sudo systemctl restart graylog-alert-consumer
```

## Cortex y analizadores

Cortex principal está en:

```text
http://IP_DEL_SERVIDOR:9001
```

TheHive se conecta internamente a Cortex mediante:

```text
http://cortex:9001
```

porque ambos están en la red Docker `socia-thehive`.

Cortex monta:

```text
/var/run/docker.sock
/opt/socia-thehive/cortex/jobs:/tmp/cortex-jobs
```

Esto permite que Cortex lance contenedores temporales de analizadores. Por eso
pueden existir imágenes de analizadores aunque no haya contenedores permanentes.

Comprobaciones:

```bash
cd /opt/socia-thehive
sudo docker compose logs --tail=150 cortex
sudo docker ps -a
sudo docker images
```

## MISP

La configuración por defecto apunta a:

```text
MISP_URL=https://172.17.33.145
```

Durante instalación base:

```bash
cd /home/debian/socia-thehive
sudo MISP_API_KEY='...' ./install.sh
```

Durante creación de instancia:

```bash
cd /home/debian/socia-thehive/multiinstance-shared-backend
sudo MISP_API_KEY='...' ./create-instance.sh contenedor1 9101
```

Si no se pasa `MISP_API_KEY` al crear instancias con backend compartido, se
intenta copiar la configuración MISP desde `http://127.0.0.1:9000`.

## Copiar cambios del repo a la instalación real

El instalador copia el repositorio a `/opt/socia-thehive`, pero editar el repo en
`/home/debian/socia-thehive` no actualiza automáticamente `/opt/socia-thehive`.

Para reinstalar aplicando cambios:

```bash
cd /home/debian/socia-thehive
sudo ./install.sh
```

Para cambios manuales puntuales, copia con cuidado el fichero concreto y reinicia
el servicio afectado. Ejemplos:

```bash
sudo cp /home/debian/socia-thehive/consumer/thehive-consumer.py /opt/socia-thehive/consumer/thehive-consumer.py
sudo /opt/socia-thehive/consumer/venv/bin/python -m py_compile /opt/socia-thehive/consumer/thehive-consumer.py
sudo systemctl restart thehive-consumer
```

```bash
sudo cp /home/debian/socia-thehive/docker-compose.yml /opt/socia-thehive/docker-compose.yml
cd /opt/socia-thehive
sudo docker compose up -d
```

## Comandos de diagnóstico frecuentes

Docker:

```bash
sudo docker ps -a
sudo docker compose -f /opt/socia-thehive/docker-compose.yml ps
sudo docker compose -f /opt/socia-thehive/docker-compose.yml logs --tail=100
sudo docker system df
```

Systemd:

```bash
sudo systemctl status docker --no-pager
sudo systemctl status thehive-consumer --no-pager
sudo systemctl status graylog-alert-consumer --no-pager
sudo systemctl list-units 'graylog-alert-consumer-*'
```

Logs:

```bash
sudo journalctl -u thehive-consumer --since "1 hour ago" --no-pager
sudo journalctl -u graylog-alert-consumer --since "1 hour ago" --no-pager
sudo journalctl -u 'graylog-alert-consumer-contenedor1' --since "1 hour ago" --no-pager
```

Cassandra:

```bash
sudo docker exec socia-cassandra cqlsh -e 'DESCRIBE KEYSPACES' 127.0.0.1 9042
```

Elasticsearch:

```bash
sudo docker exec socia-elasticsearch curl -fsS 'http://127.0.0.1:9200/_cluster/health?pretty'
sudo docker exec socia-elasticsearch curl -fsS 'http://127.0.0.1:9200/_cat/indices?v'
```

TheHive:

```bash
curl -fsS http://127.0.0.1:9000/api/status
curl -fsS http://127.0.0.1:9001/api/status
```

## Acciones peligrosas

Evita estos comandos salvo que estés reconstruyendo el entorno desde cero y
hayas aceptado perder datos:

```bash
cd /opt/socia-thehive
sudo docker compose down -v
sudo docker system prune -a --volumes
sudo docker volume rm socia-thehive_cassandra-data
sudo docker volume rm socia-thehive_elasticsearch-data
```

También evita borrar a mano:

```text
/opt/socia-thehive/.env
/opt/socia-thehive/consumer/.env
/opt/socia-thehive/graylog-alert-consumer/.env
/opt/socia-students
```

Si hay que limpiar instancias de alumnos, usa primero los scripts
`delete-instance.sh` o `delete-many.sh`.
