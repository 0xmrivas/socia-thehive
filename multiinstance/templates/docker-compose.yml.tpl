services:
  cassandra:
    image: cassandra:4.1
    container_name: socia-__INSTANCE__-cassandra
    hostname: cassandra
    restart: unless-stopped
    environment:
      CASSANDRA_CLUSTER_NAME: SOCIA-__INSTANCE__
      CASSANDRA_DC: dc1
      CASSANDRA_RACK: rack1
      CASSANDRA_ENDPOINT_SNITCH: GossipingPropertyFileSnitch
      CASSANDRA_NUM_TOKENS: 16
      MAX_HEAP_SIZE: __CASSANDRA_HEAP__
      HEAP_NEWSIZE: __CASSANDRA_NEW_HEAP__
    volumes:
      - cassandra-data:/var/lib/cassandra
    networks:
      - socia-__INSTANCE__
    healthcheck:
      test: ["CMD-SHELL", "cqlsh -e 'DESCRIBE KEYSPACES' 127.0.0.1 9042 >/dev/null 2>&1"]
      interval: 30s
      timeout: 10s
      retries: 20
      start_period: 90s

  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:7.17.24
    container_name: socia-__INSTANCE__-elasticsearch
    hostname: elasticsearch
    restart: unless-stopped
    environment:
      discovery.type: single-node
      xpack.security.enabled: "false"
      ES_JAVA_OPTS: "-Xms__ELASTIC_HEAP__ -Xmx__ELASTIC_HEAP__"
      bootstrap.memory_lock: "true"
    ulimits:
      memlock:
        soft: -1
        hard: -1
      nofile:
        soft: 65536
        hard: 65536
    volumes:
      - elasticsearch-data:/usr/share/elasticsearch/data
    networks:
      - socia-__INSTANCE__
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://127.0.0.1:9200/_cluster/health?wait_for_status=yellow\\&timeout=5s >/dev/null"]
      interval: 20s
      timeout: 10s
      retries: 20
      start_period: 60s

  thehive:
    image: strangebee/thehive:5.2
    container_name: socia-__INSTANCE__-thehive
    hostname: thehive
    restart: unless-stopped
    depends_on:
      cassandra:
        condition: service_healthy
      elasticsearch:
        condition: service_healthy
    ports:
      - "__PORT__:9000"
    environment:
      JAVA_OPTS: "-Xms__THEHIVE_HEAP__ -Xmx__THEHIVE_HEAP__"
      THEHIVE_SECRET: "${THEHIVE_SECRET}"
    volumes:
      - ./thehive/config/application.conf:/etc/thehive/application.conf:ro
      - thehive-files:/opt/thp/thehive/files
      - thehive-logs:/var/log/thehive
    networks:
      - socia-__INSTANCE__
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://127.0.0.1:9000/api/status >/dev/null"]
      interval: 30s
      timeout: 10s
      retries: 20
      start_period: 120s

networks:
  socia-__INSTANCE__:
    name: socia-__INSTANCE__
    driver: bridge

volumes:
  cassandra-data:
    name: socia-__INSTANCE__-cassandra-data
  elasticsearch-data:
    name: socia-__INSTANCE__-elasticsearch-data
  thehive-files:
    name: socia-__INSTANCE__-thehive-files
  thehive-logs:
    name: socia-__INSTANCE__-thehive-logs
