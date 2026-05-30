services:
  hermes:
    image: {{HERMES_IMAGE}}
    container_name: hermes-agent
    restart: unless-stopped
    command: gateway run
    environment:
      - HERMES_UID={{AGENT_UID}}
      - HERMES_GID={{AGENT_GID}}
    volumes:
      - {{HERMES_STATEFUL_DATA_DIR}}:/opt/data
      - {{REPO_WORKDIR}}:/opt/data/project/{{REPO_NAME}}
      - {{REPO_WORKDIR}}/.env:/opt/data/.env
      - {{HOST_VAULT}}:/vault
      - /var/run/docker.sock:/var/run/docker.sock
    ports:
      - "8642:8642"
    networks:
      - hermes-net

networks:
  hermes-net:
    driver: bridge
