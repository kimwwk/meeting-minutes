# RunPod GPU Manual SSH Deployment

Deploy Whisper + Ollama to RunPod via SSH (manual setup).

## Quick Start

### 1. Create Pod
- Template: `runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04`
- Get SSH connection string from RunPod dashboard

### 2. SSH & Setup

```bash
# SSH into pod
ssh <connection-string> -i ~/.ssh/runpod_meetily

# Install nano (optional, for editing)
apt-get update && apt-get install -y nano

# Create setup script
nano /workspace/runpod-setup.sh
# Paste contents of runpod-setup-origin-no-backend.sh (or runpod-setup-origin.sh for full stack)

# Run setup
chmod +x /workspace/runpod-setup.sh
./runpod-setup.sh
```

### 3. Start Services

```bash
/workspace/start-gpu-services.sh    # or start-meetily.sh for full stack
```

## Files

| File | Description |
|------|-------------|
| `runpod-setup-origin-no-backend.sh` | GPU services only (Whisper + Ollama) |
| `runpod-setup-origin.sh` | Full stack (Whisper + Ollama + FastAPI backend) |
| `RUNPOD_GUIDE.md` | Detailed guide |
| `SSH_SETUP.md` | SSH key setup |

## Endpoints

| Service | Port | Script |
|---------|------|--------|
| Whisper | 8178 | Both |
| Ollama | 11434 | Both |
| Backend API | 5167 | Full stack only |
