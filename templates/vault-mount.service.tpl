[Unit]
Description=rclone R2 vault FUSE mount
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
User={{AGENT_USER}}
ExecStartPre=/bin/mkdir -p {{HOST_VAULT}}
ExecStart={{RCLONE_BIN}} mount r2:{{R2_BUCKET_NAME}} {{HOST_VAULT}} \
  --vfs-cache-mode full \
  --vfs-cache-max-age 24h \
  --vfs-cache-max-size 500M \
  --allow-other \
  --log-level INFO
ExecStop=/bin/fusermount -uz {{HOST_VAULT}}
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
