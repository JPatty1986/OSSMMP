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
if lspci | grep -i -E 'nvidia|amd' > /dev/null; then
  GPU_MODE="gpu"
  info "GPU detected."
else
  GPU_MODE="cpu"
  warn "No GPU detected. Using CPU mode."
fi

if [ "$GPU_MODE" = "gpu" ]; then
  info "Installing NVIDIA drivers and Container Toolkit for GPU support…"

  # 1) Install the recommended NVIDIA driver
  sudo apt-get update
  sudo apt-get install -y ubuntu-drivers-common
  sudo ubuntu-drivers autoinstall

  # 2) Install the NVIDIA Container Toolkit so Docker --gpus works
  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
    | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
  curl -sL https://nvidia.github.io/libnvidia-container/stable/$(. /etc/os-release && echo $ID)-$(. /etc/os-release && echo $VERSION_ID)/nvidia-container-toolkit.list \
    | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
    | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
  sudo apt-get update
  sudo apt-get install -y nvidia-container-toolkit
  sudo nvidia-ctk runtime configure --runtime=docker    # register the NVIDIA runtime :contentReference[oaicite:0]{index=0}
  sudo systemctl restart docker

  # 3) Enable Flash Attention in Ollama
  export OLLAMA_FLASH_ATTENTION=1                          # tells Ollama to use Flash Attention :contentReference[oaicite:1]{index=1}

  # (Optional) only expose GPU #0 to Ollama:
  # export CUDA_VISIBLE_DEVICES=0
else
  warn "Skipping GPU setup; continuing in CPU-only mode."
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

# Install Ollama
info "Installing Ollama..."
curl -fsSL https://ollama.com/install.sh | sh

# Skip pulling a default model; let the user choose manually later
# ollama pull llama3 || true

# Run Ollama in the background
sudo tee /etc/systemd/system/ollama.service > /dev/null <<EOF
[Unit]
Description=Ollama Service
After=network.target docker.service
Requires=docker.service

[Service]
# If you set OLLAMA_FLASH_ATTENTION above, systemd will pick it up:
Environment=OLLAMA_FLASH_ATTENTION=1
# (Optional) To pin to a specific GPU:
# Environment=CUDA_VISIBLE_DEVICES=0
ExecStart=/usr/local/bin/ollama serve
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

# Reload and restart
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


info "Setup complete!"
echo -e "\n- Ollama running on port 11434 (mode: $GPU_MODE)"
echo -e "- Open WebUI running on port 3000"
echo -e "- Encrypted data mounted at /securedata"
echo -e "${YELLOW}\n[!] Reminder: Your encrypted volume uses a key file at /root/.securekey — back it up securely or you will lose access to your data.${NC}"
