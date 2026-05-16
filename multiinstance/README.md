# SOCIA TheHive Multiinstancia

Este directorio permite crear instancias aisladas de TheHive para alumnos con nombres genericos:

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

Cada instancia crea sus propios contenedores, red y volumenes:

```text
socia-contenedor1-thehive
socia-contenedor1-cassandra
socia-contenedor1-elasticsearch
socia-contenedor1-*
```

Acceso esperado:

```text
http://IP_DEL_SERVIDOR:9101
Usuario: socia-contenedor1@thehive.local
Password: contenedor1
```

Si se crea consumidor Kafka, cada instancia usa un grupo distinto:

```text
thehive-socia-contenedor1
thehive-socia-contenedor2
```

Eso hace que todas las instancias reciban los mismos eventos del topic `ioc-events`.

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

Tambien puede configurar MISP durante el despliegue si se pasa una API key:

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

## Requisitos

Debe existir el TheHive principal en `http://127.0.0.1:9000` con el usuario admin:

```text
admin@thehive.local / secret
```

El script usa esa API key admin para crear el usuario analista de cada instancia. Si cambiaste la password o quieres pasar la API key directamente:

```bash
sudo ADMIN_PASSWORD='otra' ./create-instance.sh contenedor1 9101
sudo ADMIN_API_KEY='...' ./create-instance.sh contenedor1 9101
```

## Recursos

Por defecto cada instancia usa heaps reducidos:

```text
Cassandra: 768M
Elasticsearch: 768m
TheHive: 768m
```

Para pocos alumnos puede valer. Para muchas instancias en una sola maquina, calcula RAM con margen. Puedes ajustar:

```bash
sudo CASSANDRA_HEAP=512M ELASTIC_HEAP=512m THEHIVE_HEAP=512m ./create-instance.sh contenedor4 9104
```

## Eliminar Instancia

Esto borra contenedores, volumenes y ficheros de la instancia:

```bash
sudo ./delete-instance.sh contenedor1
```

## Notas

- Cada instancia tiene Cassandra y Elasticsearch propios.
- El puerto debe ser unico.
- No se modifica el TheHive principal.
- El consumidor por instancia se instala como `thehive-consumer-<instancia>.service`.
