[Unit]
Description=SOCIA Graylog alert Kafka to TheHive consumer (__INSTANCE__)
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=simple
User=socia-thehive
Group=socia-thehive
WorkingDirectory=__INSTANCE_DIR__/graylog-alert-consumer
EnvironmentFile=__INSTANCE_DIR__/graylog-alert-consumer/.env
ExecStart=__INSTANCE_DIR__/graylog-alert-consumer/venv/bin/python __INSTANCE_DIR__/graylog-alert-consumer/graylog-alert-consumer.py
Restart=always
RestartSec=10
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true

[Install]
WantedBy=multi-user.target
