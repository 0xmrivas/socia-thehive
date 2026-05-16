services:
  thehive:
    image: strangebee/thehive:5.2
    container_name: socia-__INSTANCE__-thehive
    hostname: thehive
    restart: unless-stopped
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
      - socia-thehive
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://127.0.0.1:9000/api/status >/dev/null"]
      interval: 30s
      timeout: 10s
      retries: 20
      start_period: 120s

networks:
  socia-thehive:
    external: true

volumes:
  thehive-files:
    name: socia-__INSTANCE__-thehive-files
  thehive-logs:
    name: socia-__INSTANCE__-thehive-logs
