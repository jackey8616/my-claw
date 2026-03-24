sudo apt update && sudo apt upgrade -y
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

mkdir -p openclaw/data
mkdir -p openclaw/skills
mkdir -p caddy/data
mkdir -p caddy/config
sudo chmod -R 775 openclaw && sudo chown -R 1000:1000 openclaw
sudo chmod -R 775 caddy && sudo chown -R 1000:1000 caddy
