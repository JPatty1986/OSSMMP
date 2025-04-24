# 🔐 Secure Shared Development Environment Setup

This project sets up a **secure, encrypted development environment** using Docker, Ollama, and Open WebUI. It detects GPU/CPU, installs dependencies, creates an encrypted container, and launches a private, browser-accessible AI interface — no command-line model setup needed.

---

## 🚀 Features

- ✅ Detects GPU or defaults to CPU
- 🔐 Creates and mounts encrypted storage (`/securedata`)
- 🐳 Installs Docker and Docker Compose
- 📦 Relocates Docker's root data directory into `/securedata` for encrypted containerization
- 🧠 Installs [Ollama](https://ollama.com) (no models pulled by default)
- 🌐 Deploys [Open WebUI](https://github.com/open-webui/open-webui) on **port 3000**
- 🔄 Runs Ollama as a persistent system service via systemd
- 💡 Users manage models and chat settings entirely through Open WebUI

---

## 🧰 Requirements

- 🐧 Ubuntu Server 20.04 or later (fresh install recommended)
- 🔑 Sudo or root privileges
- 🌐 Internet connection
- 💾 At least 10–20 GB free disk space for encrypted container

---

## 📦 Installation Guide

### 1. Download the script

```bash
curl -O https://raw.githubusercontent.com/<your-username>/<your-repo>/main/setup.sh
```

### 2. Make it executable

```bash
sudo chmod +x setup.sh
```

### 3. Run the script

```bash
sudo ./setup.sh
```

📝 During setup, you’ll be prompted to enter the size of your encrypted container in **GB** (e.g., `10` for 10 GB).

---

## 💾 How Much Disk Space Should I Allocate?

When prompted:

> `Enter encrypted container size in GB (e.g., 5, 10, 50):`

Here’s a quick reference:

| Container Size | What You Can Fit                                 |
|----------------|--------------------------------------------------|
| **5 GB**       | Minimum: Open WebUI + 1 small model              |
| **10 GB**      | Room for WebUI + 1–2 medium LLMs                 |
| **20–30 GB**   | Several models + embeddings, chat history, etc.  |
| **50+ GB**     | Ideal for experimentation and multiple models    |

**✅ Recommended Minimum:**  
**10–20 GB** for a usable setup with room to grow.

🧠 LLMs are large. For example:
- `llama3` ~4.5 GB
- `llama2:13b` ~7–8 GB
- WebUI state, logs, and cache can grow over time

---

## 🔐 Encryption Key Details

This setup uses a **randomly generated encryption key**, stored at:

```
/root/.securekey
```

- 🔒 This key is used to encrypt and decrypt your data volume.
- 🧠 If this key is lost or deleted, you will **not** be able to recover your data.
- 🔄 You can regenerate the key (not recommended unless reinitializing) with:

```bash
sudo head -c 64 /dev/urandom > /root/.securekey
sudo chmod 600 /root/.securekey
```

⚠️ **IMPORTANT: Back Up `/root/.securekey` Securely**
This is the only key that unlocks your encrypted volume.

- 📁 Store it in a **separate, secure location** (e.g., encrypted USB, password manager file vault).
- 🔓 Without this file, your encrypted data **cannot be recovered.**


---

## 🛠️ Next Steps

- 🌐 Open your browser and go to: `http://<your-server-ip>:3000`
- 🧠 From there, use **Open WebUI** to:
  - Pull models like `mistral`, `llama2`, etc.
  - Manage settings, tokens, and chat history
  - Interact with LLMs through a clean interface

> 🛑 You do **not** need to run `ollama pull` or configure anything from the command line — Open WebUI handles it all!

---

## 🚧 Known Limitations

- ❌ **No AMD GPU support:** Ollama currently supports only NVIDIA GPUs. AMD GPUs will fallback to CPU mode.
- 🔒 **Key storage is manual:** You must back up the `/root/.securekey` file yourself — the script does not automate this for security reasons.
---


## 📬 Need Help?

- 📂 [Open an Issue](https://github.com/<your-username>/<your-repo>/issues)
- 💬 Reach out via GitHub if you run into problems

---

> ✅ Perfect for AI devs, teams, or tinkerers needing a **secure, self-hosted, GPU/CPU-compatible AI environment with minimal setup**.
