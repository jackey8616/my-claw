[Unit]
Description=Hermes Agent (Docker Compose)
After=docker.service vault-mount.service network-online.target
Requires=docker.service
Wants=vault-mount.service network-online.target

[Service]
Type=simple
User={{AGENT_USER}}
SupplementaryGroups=docker
WorkingDirectory={{REPO_WORKDIR}}
ExecStartPre=/usr/bin/docker compose pull --quiet
ExecStart=/usr/bin/docker compose up --remove-orphans
ExecStop=/usr/bin/docker compose down
Restart=on-failure
RestartSec=15

[Install]
WantedBy=multi-user.target
