# SOCIA TheHive Multiinstancia con Backend Compartido

Este directorio permite crear instancias de TheHive para alumnos reutilizando el Cassandra y el Elasticsearch del despliegue base.
La carpeta original `multiinstance` no se modifica y sigue creando una pila completa por alumno.

Cada instancia nueva crea solo:

```text
socia-contenedor1-thehive
socia-contenedor1-thehive-files
socia-contenedor1-thehive-logs
graylog-alert-consumer-contenedor1.service
```

Los datos se aislan por:

```text
Cassandra keyspace: thehive_contenedor1
Elasticsearch index: thehive-contenedor1
```

## Uso

```bash
sudo ./create-instance.sh contenedor1 9101
sudo ./create-instance.sh contenedor2 9102
sudo ./create-instance.sh contenedor3 9103
```

Tambien puedes crear varias instancias de una vez:

```bash
sudo ./create-many.sh 5
```

Por defecto crea `contenedor1` a `contenedor5` en los puertos `9101` a `9105`.
Puedes cambiar el prefijo, indice inicial o puerto inicial:

```bash
sudo PREFIX=alumno START_INDEX=1 START_PORT=9201 ./create-many.sh 5
```

Si no quieres consumidor Kafka por instancia:

```bash
sudo NO_CONSUMER=1 ./create-many.sh 5
```

Para programar la creacion de varias instancias a una fecha y hora concretas:

```bash
sudo ./schedule-create-many.sh 5 "2026-05-20 13:00"
sudo PREFIX=alumno START_INDEX=21 START_PORT=9121 ./schedule-create-many.sh 3 "tomorrow 08:00"
```

Esto crea una unidad systemd persistente. Puedes verla con:

```bash
systemctl list-timers 'socia-create-many-*'
```

Y cancelarla con:

```bash
sudo systemctl stop socia-create-many-<id>.timer
sudo systemctl disable socia-create-many-<id>.timer
```

Para programar el borrado de varias instancias:

```bash
sudo ./schedule-delete-many.sh 5 "2026-05-20 18:00"
sudo PREFIX=alumno START_INDEX=21 ./schedule-delete-many.sh --all "tomorrow 20:00"
```

Se gestiona igual con `systemd`:

```bash
systemctl list-timers 'socia-delete-many-*'
sudo systemctl stop socia-delete-many-<id>.timer
sudo systemctl disable socia-delete-many-<id>.timer
```

Importante: este programador borra por cantidad o con `--all` para el prefijo
configurado. Si quieres borrar instancias concretas, usa `delete-instance.sh`
directamente una por una:

```bash
sudo ./delete-instance.sh contenedor2
sudo ./delete-instance.sh contenedor5
sudo ./delete-instance.sh contenedor9
```

Cada instancia reutiliza los backends compartidos del stack base:

```text
socia-cassandra
socia-elasticsearch
red Docker: socia-thehive
```

Acceso esperado:

```text
http://IP_DEL_SERVIDOR:9101
Organización: SOCIA
Usuario analista: analista1@thehive.local
Password analista: analista1
Usuario analista 2: analista2@thehive.local
Password analista 2: analista2
```

Cada instancia usa una cookie de sesión distinta, por ejemplo `THEHIVE_SESSION_contenedor1`, para evitar que una sesión en un puerto cierre la sesión de otra instancia en otro puerto.

Si se crea consumidor Kafka, cada instancia usa un grupo distinto para la vía Graylog:

```text
thehive-graylog-contenedor1
thehive-graylog-contenedor2
```

Eso hace que todas las instancias reciban las mismas alertas del topic `graylog-alerts`.

El consumidor se crea con filtrado y agregacion activados por defecto:

```text
KAFKA_MAX_POLL_RECORDS=50
THEHIVE_ALLOWED_RULE_IDS=31151,31104,5763,40111,5758,5551
THEHIVE_DROP_RULE_IDS=31101,5760
THEHIVE_AGGREGATE_RULE_IDS=31151
THEHIVE_AGGREGATION_WINDOW_SECONDS=10
THEHIVE_AGGREGATION_MAX_EXAMPLES=20
```

Con esta configuracion, los `31151` de escaneo web se agrupan en ventanas de 10 segundos antes de enviarse a TheHive.

Tambien configura MISP durante el despliegue. Por defecto copia la configuración MISP guardada en el TheHive principal (`MISP_COPY_FROM_URL=http://127.0.0.1:9000`):

```bash
sudo ./create-instance.sh contenedor1 9101
sudo ./create-many.sh 5
```

Si prefieres pasar una API key MISP manualmente en vez de copiar la configuración del principal:

```bash
sudo MISP_API_KEY='...' ./create-instance.sh contenedor1 9101
sudo MISP_API_KEY='...' ./create-many.sh 5
```

Valores por defecto:

```text
MISP_URL=https://172.17.33.145
MISP_NAME=MISP local
MISP_PURPOSE=ImportAndExport
MISP_INTERVAL=10 minutes
MISP_ACCEPT_ANY_CERT=true
```

Para un laboratorio se puede reutilizar una clave, pero para trazabilidad conviene usar una API key MISP distinta por instancia.

## Cortex y Analizadores

Por defecto el script copia la configuración Cortex del TheHive principal en `http://127.0.0.1:9000` y la aplica a cada instancia nueva.
Esto reutiliza la misma conexión ya probada contra `socia-cortex`.

Valores por defecto:

```text
CORTEX_ENABLED=true
CORTEX_COPY_FROM_URL=http://127.0.0.1:9000
CORTEX_URL=http://cortex:9001
CORTEX_NAME=Cortex
CORTEX_CONFIGURE_ANALYZERS=true
```

Si prefieres no copiar la configuración del TheHive principal, puedes pasar la API key de Cortex directamente:

```bash
sudo CORTEX_API_KEY='...' ./create-instance.sh contenedor1 9101
```

El script comprueba los analizadores habilitados en Cortex. Si no defines `CORTEX_ANALYZERS`, lee los analizadores habilitados con la configuración Cortex del TheHive principal y habilita esa misma lista con la key destino. Si quieres forzar definiciones concretas:

```bash
sudo CORTEX_ANALYZERS=AbuseIPDB_2_0,VirusTotal_GetReport_3_1 ./create-instance.sh contenedor1 9101
```

Nota: algunos analizadores necesitan configuración propia en Cortex, por ejemplo API keys de servicios externos. Si ya están habilitados en `socia-cortex`, las nuevas instancias solo necesitan el conector TheHive -> Cortex.

## Requisitos

Debe estar levantado el despliegue base:

```bash
cd /home/debian/socia-thehive
sudo docker compose up -d
```

Ese despliegue aporta:

```text
socia-cassandra
socia-elasticsearch
red Docker socia-thehive
TheHive principal en http://127.0.0.1:9000
```

El TheHive principal debe tener el usuario admin:

```text
admin@thehive.local / secret
```

El script usa esa API key admin para crear el usuario analista de cada instancia. Si cambiaste la password o quieres pasar la API key directamente:

```bash
sudo ADMIN_PASSWORD='otra' ./create-instance.sh contenedor1 9101
sudo ADMIN_API_KEY='...' ./create-instance.sh contenedor1 9101
```

## Recursos

Por defecto cada instancia solo consume heap de TheHive:

```text
TheHive: 768m
```

Puedes ajustar:

```bash
sudo THEHIVE_HEAP=512m ./create-instance.sh contenedor4 9104
```

El ahorro viene de no levantar Cassandra y Elasticsearch por alumno. Aun asi, el Cassandra y Elasticsearch compartidos deben dimensionarse con margen si hay muchas instancias activas.

## Eliminar Instancia

Esto borra contenedores, volumenes, ficheros, keyspace Cassandra e indices Elasticsearch de la instancia:

```bash
sudo ./delete-instance.sh contenedor1
```

Si necesitas conservar el keyspace y el indice compartidos para investigar o recuperar datos:

```bash
sudo ./delete-instance.sh contenedor1 --keep-shared-data
```

Tambien puedes eliminar varias instancias de una vez:

```bash
sudo ./delete-many.sh 5
```

Por defecto elimina `contenedor1` a `contenedor5`. Para borrar todas las instancias existentes con el prefijo configurado en `BASE_DIR`:

```bash
sudo ./delete-many.sh --all
```

Si necesitas conservar los datos compartidos:

```bash
sudo KEEP_SHARED_DATA=1 ./delete-many.sh 5
```

## Notas

- Cada instancia comparte Cassandra y Elasticsearch.
- Cada instancia tiene keyspace Cassandra e indice Elasticsearch propios.
- El puerto debe ser unico.
- No se modifica el TheHive principal; solo se lee su configuración Cortex si `CORTEX_COPY_FROM_URL` apunta a él.
- Cada instancia crea la organización `SOCIA` y los usuarios `analista1` y `analista2`, con contraseñas iguales al nombre de usuario.
- El consumidor por instancia se instala como `graylog-alert-consumer-<instancia>.service`; no se instala el consumer directo de `ioc-events`.
