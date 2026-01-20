# Local CPU Backend Deployment

Run Meetily backend locally (CPU) while using RunPod for GPU services (Whisper + Ollama).

## Quick Start

### 1. Set Environment

```bash
export OLLAMA_HOST=https://<your-runpod-id>-11434.proxy.runpod.net
```

### 2. Run with Docker

```bash
cd meeting-minutes/backend

# Build and start
docker compose -f docker-compose.backend-only.yml up -d

# View logs
docker compose -f docker-compose.backend-only.yml logs -f
```

### 3. Verify

```bash
curl http://localhost:5167/get-meetings
# Or open http://localhost:5167/docs
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `OLLAMA_HOST` | http://localhost:11434 | Ollama server URL |
| `APP_PORT` | 5167 | Backend API port |

## Data

- Database: `./data/meeting_minutes.db`

## Push to Registry

```bash
docker tag meetily-backend:latest <your-registry>/meetily/backend:latest
docker push <your-registry>/meetily/backend:latest
```
