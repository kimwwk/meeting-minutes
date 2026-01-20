# Meetily on RunPod - Deployment Guide

## Quick Start

### 1. Create Pod

| Setting | Value |
|---------|-------|
| **Template** | `runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04` |
| **GPU** | A40 ($0.20/hr) or RTX 4090 ($0.50/hr) |
| **Disk** | 50GB minimum (for models) |
| **Ports** | 5167, 8178, 11434 (TCP) |

### 2. Run Setup Script

```bash
# SSH into your pod or use web terminal

# Download and run setup script
cd /workspace
wget https://raw.githubusercontent.com/YOUR_REPO/runpod-setup.sh
# OR copy the script content manually

chmod +x runpod-setup.sh
./runpod-setup.sh
```

### 3. Start Services

```bash
/workspace/start-meetily.sh
```

### 4. Configure Port Forwarding

In RunPod dashboard, expose these TCP ports:
- **5167** - Main API endpoint
- **8178** - Whisper transcription
- **11434** - Ollama LLM

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     RunPod GPU Instance                      │
│                                                              │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────┐ │
│  │ FastAPI Backend │  │ Whisper Server  │  │   Ollama    │ │
│  │   Port 5167     │  │   Port 8178     │  │ Port 11434  │ │
│  │                 │  │   (GPU CUDA)    │  │  (GPU CUDA) │ │
│  └────────┬────────┘  └────────┬────────┘  └──────┬──────┘ │
│           │                    │                   │        │
│           └────────────────────┴───────────────────┘        │
│                         Internal Network                     │
└─────────────────────────────────────────────────────────────┘
                              │
                    RunPod Port Forwarding
                              │
                              ▼
                    Your Client Application
```

---

## API Endpoints

### Backend API (Port 5167)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/get-meetings` | List all meetings |
| GET | `/get-meeting/{id}` | Get meeting details |
| POST | `/save-transcript` | Save transcript segments |
| POST | `/process-transcript` | Trigger LLM summarization |
| GET | `/get-summary/{id}` | Get meeting summary |
| POST | `/upload-transcript` | Upload transcript file |
| POST | `/search-transcripts` | Search transcripts |
| GET | `/docs` | Swagger UI |

### Whisper Server (Port 8178)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/` | Health check + Web UI |
| POST | `/inference` | Transcribe audio file |
| WS | `/` | WebSocket for streaming |

### Ollama (Port 11434)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/tags` | List models |
| POST | `/api/generate` | Generate text |
| POST | `/api/chat` | Chat completion |

---

## Environment Variables

```bash
# Whisper Configuration
export WHISPER_MODEL=models/ggml-base.en.bin  # or large-v3 for best quality
export WHISPER_USE_GPU=true
export WHISPER_THREADS=4

# Ollama Configuration
export OLLAMA_HOST=http://localhost:11434

# Backend Configuration
export DATABASE_PATH=/workspace/meeting-minutes/backend/data/meeting_minutes.db
```

---

## Whisper Models

| Model | Size | Speed | Quality | VRAM |
|-------|------|-------|---------|------|
| tiny.en | 75MB | Fastest | Basic | ~1GB |
| base.en | 142MB | Fast | Good | ~1GB |
| small.en | 466MB | Medium | Better | ~2GB |
| medium.en | 1.5GB | Slow | Great | ~5GB |
| large-v3 | 3GB | Slowest | Best | ~10GB |

To change model:
```bash
# Download new model
cd /workspace/meeting-minutes/backend/models
wget https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin

# Update environment and restart
export WHISPER_MODEL=models/ggml-large-v3.bin
/workspace/stop-meetily.sh
/workspace/start-meetily.sh
```

---

## Ollama Models

```bash
# Pull models (run after Ollama is started)
ollama pull llama3.2:3b      # Small, fast (2GB)
ollama pull llama3.1:8b      # Medium (5GB)
ollama pull llama3.1:70b     # Large, best quality (40GB)
ollama pull mistral          # Good alternative (4GB)
```

---

## Cost Estimation

### A40 GPU ($0.20/hr spot, $0.40/hr on-demand)

| Usage | Monthly Cost (Spot) | Monthly Cost (On-Demand) |
|-------|---------------------|--------------------------|
| 2 hrs/day | ~$12 | ~$24 |
| 8 hrs/day | ~$48 | ~$96 |
| 24/7 | ~$144 | ~$288 |

Plus ~$4/month for 50GB storage.

---

## Troubleshooting

### Services won't start
```bash
# Check logs
journalctl -xe

# Check if ports are in use
netstat -tlnp | grep -E '5167|8178|11434'

# Kill stuck processes
/workspace/stop-meetily.sh
```

### CUDA errors
```bash
# Verify CUDA
nvidia-smi
nvcc --version

# Check GPU memory
nvidia-smi --query-gpu=memory.used,memory.free --format=csv
```

### Out of memory
- Use smaller Whisper model (base.en instead of large-v3)
- Use smaller Ollama model (llama3.2:3b instead of 70b)

### Whisper server crashes
```bash
# Run with debug output
cd /workspace/meeting-minutes/backend/whisper.cpp
./build/bin/whisper-server \
    --model /workspace/meeting-minutes/backend/models/ggml-base.en.bin \
    --host 0.0.0.0 \
    --port 8178 \
    --print-progress
```

---

## Security Notes

- The API has CORS enabled for all origins (`*`) - restrict for production
- No authentication by default - add API keys for production use
- Database is SQLite file-based - backup `/workspace/meeting-minutes/backend/data/`

---

## Stopping the Pod

To minimize costs:
1. Stop services: `/workspace/stop-meetily.sh`
2. In RunPod dashboard: **Stop Pod** (keeps data, stops GPU billing)
3. To delete everything: **Terminate Pod** (deletes all data)
