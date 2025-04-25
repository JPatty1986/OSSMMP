#!/bin/bash
set -e

clear

# Colors for output
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
NC="\033[0m" # No Color

function info {
  echo -e "${GREEN}[+] $1${NC}"
}

function warn {
  echo -e "${YELLOW}[!] $1${NC}"
}

function error_exit {
  echo -e "${RED}[✗] $1${NC}" >&2
  exit 1
}

# Detect GPU
info "Detecting GPU..."
if lspci | grep -i 'nvidia' | grep -Ei 'vga|3d' > /dev/null; then
  GPU_MODE="nvidia"
  info "NVIDIA GPU detected — Ollama will use GPU acceleration."
elif lspci | grep -i 'amd' | grep -Ei 'vga|3d' > /dev/null; then
  GPU_MODE="amd"
  warn "AMD GPU detected — Ollama does NOT support AMD GPU acceleration. Falling back to CPU mode."
  GPU_MODE="cpu"
else
  GPU_MODE="cpu"
  warn "No supported GPU detected. Proceeding in CPU-only mode."
fi

info "Updating and installing base packages..."
sudo apt update && sudo apt -y upgrade
sudo apt install -y \
  parted cryptsetup curl git docker.io docker-compose unzip \
  python3-docker python3-dotenv python3-docopt python3-texttable python3-websocket \
  containerd dnsmasq-base bridge-utils runc ubuntu-fan pigz

info "Enabling unattended upgrades for security patches..."
cat <<EOF | sudo tee /etc/apt/apt.conf.d/20auto-upgrades
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

# Prompt for encrypted container size
read -p "Enter encrypted container size in GB (e.g., 5, 10, 50): " CONTAINER_SIZE_GB

info "Creating or opening encrypted file container..."
sudo mkdir -p /securedata
if [ ! -f /securedata/container.img ]; then
  sudo dd if=/dev/zero of=/securedata/container.img bs=1G count=$CONTAINER_SIZE_GB status=progress
fi

# Create encryption key if needed
KEY_FILE="/root/.securekey"
if [ ! -f "$KEY_FILE" ]; then
  info "Generating encryption key..."
  sudo head -c 64 /dev/urandom > "$KEY_FILE"
  sudo chmod 600 "$KEY_FILE"
fi

# Set up and open LUKS volume
if ! sudo cryptsetup isLuks /securedata/container.img; then
  echo YES | sudo cryptsetup luksFormat /securedata/container.img "$KEY_FILE" --batch-mode
fi

sudo cryptsetup luksOpen /securedata/container.img securedata --key-file "$KEY_FILE"
sudo mkfs.ext4 /dev/mapper/securedata
sudo mount /dev/mapper/securedata /securedata

info "Encrypted volume mounted at /securedata"

# Move Docker's data-root into encrypted volume
info "Reconfiguring Docker to use encrypted storage..."

sudo systemctl stop docker
sudo mkdir -p /securedata/docker
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "data-root": "/securedata/docker"
}
EOF

# Restart Docker to apply new settings
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl restart docker

# Install Ollama
info "Installing Ollama..."
curl -fsSL https://ollama.com/install.sh | sh

# Set up Ollama systemd service based on GPU support
info "Setting up Ollama systemd service..."

if [ "$GPU_MODE" = "cpu" ]; then
  info "Configuring Ollama to run in CPU mode (disabling CUDA)..."
  sudo tee /etc/systemd/system/ollama.service > /dev/null <<EOF
[Unit]
Description=Ollama Service (CPU Mode)
After=network.target docker.service
Requires=docker.service

[Service]
Environment=OLLAMA_NO_CUDA=1
ExecStart=/usr/local/bin/ollama serve
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
else
  sudo tee /etc/systemd/system/ollama.service > /dev/null <<EOF
[Unit]
Description=Ollama Service (GPU Mode)
After=network.target docker.service
Requires=docker.service

[Service]
ExecStart=/usr/local/bin/ollama serve
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
fi

sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable --now ollama

info "Ollama is running on port 11434 (mode: $GPU_MODE)"

# Launch Open WebUI container on port 3000
echo "[+] Launching Open WebUI using prebuilt container on port 3000..."
sudo docker rm -f open-webui &>/dev/null || true
sudo docker run -d \
  -p 3000:8080 \
  -e OLLAMA_API_BASE_URL=http://localhost:11434 \
  -v /securedata:/app/data \
  --name open-webui \
  ghcr.io/open-webui/open-webui:ollama

# Create systemd service to auto-start Open WebUI container on boot
info "Creating systemd service for Open WebUI..."

sudo tee /etc/systemd/system/open-webui.service > /dev/null <<EOF
[Unit]
Description=Open WebUI Container
Requires=docker.service
After=docker.service

[Service]
Restart=always
ExecStartPre=-/usr/bin/docker rm -f open-webui
ExecStart=/usr/bin/docker run \\
  $GPU_DOCKER_FLAG \\
  -p 3000:8080 \\
  -e OLLAMA_API_BASE_URL=http://localhost:11434 \\
  -v /securedata:/app/data \\
  --name open-webui \\
  ghcr.io/open-webui/open-webui:ollama
ExecStop=/usr/bin/docker stop open-webui

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable --now open-webui

info "Setup complete!"
echo -e "\n- Ollama running on port 11434 (mode: $GPU_MODE)"
echo -e "- Open WebUI running on port 3000"
echo -e "- Encrypted data mounted at /securedata"
echo -e "${YELLOW}\n[!] Reminder: Your encrypted volume uses a key file at /root/.securekey — back it up securely or you will lose access to your data.${NC}"
