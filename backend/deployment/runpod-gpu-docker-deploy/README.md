# RunPod GPU Docker Deployment

Deploy Whisper + Ollama + Speaker Diarization to RunPod via Docker image.

## Dockerfiles

| File | Repo | Build | Services |
|------|------|-------|----------|
| `Dockerfile.origin-lite` | Zackriya-Solutions | On first boot | Whisper, Ollama |
| `Dockerfile.fork-speaker-diarization-lite` | kimwwk fork | On first boot | Whisper, Ollama, Diarization |
| `Dockerfile.fork-speaker-diarization` | kimwwk fork | At build time | Whisper, Ollama, Diarization |

## Quick Start (Published Image)

1. RunPod → Templates → New Template
2. Configure:
   - **Image:** `kimwwk/meetily-gpu-services:lite`
   - **Ports:** `8178, 8179, 11434`
   - **Env:** `HF_AUTH_TOKEN=<your_huggingface_token>` (required for diarization)
3. Create pod, first boot takes ~10-15 min (lite version)

## Build & Push

```bash
# Build lite version
docker build -f Dockerfile.fork-speaker-diarization-lite -t kimwwk/meetily-gpu-services:lite .
docker push kimwwk/meetily-gpu-services:lite

# Build pre-built version (faster startup, larger image)
docker build -f Dockerfile.fork-speaker-diarization -t kimwwk/meetily-gpu-services:latest .
docker push kimwwk/meetily-gpu-services:latest
```

## Endpoints

| Service | Port | Usage |
|---------|------|-------|
| Whisper | 8178 | Transcription only |
| Diarization | 8179 | Transcription + speaker labels |
| Ollama | 11434 | LLM inference |
