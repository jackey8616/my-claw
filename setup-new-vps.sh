sudo apt update && sudo apt upgrade -y
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

mkdir -p openclaw/data
mkdir -p openclaw/obsidian-vault
mkdir -p openclaw/skills
sudo chmod -R 775 openclaw && sudo chown -R 1000:1000 openclaw
docker run -it --rm \
  --env-file $(pwd)/.env \
  -v $(pwd)/openclaw/data:/home/node/.openclaw \
  ghcr.io/openclaw/openclaw:latest \
  npx openclaw onboard

mkdir -p caddy/data
mkdir -p caddy/config
sudo chmod -R 775 caddy && sudo chown -R 1000:1000 caddy
