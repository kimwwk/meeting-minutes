#!/bin/bash
# =============================================================================
# Meetily RunPod Deployment Script
# Template: runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04
# GPU: A40 (recommended) or RTX 4090
# =============================================================================

set -e

echo "=========================================="
echo "  Meetily RunPod Setup Script"
echo "=========================================="

# -----------------------------------------------------------------------------
# 1. Install System Dependencies
# -----------------------------------------------------------------------------
echo "[1/7] Installing system dependencies..."
apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    wget \
    curl \
    ffmpeg \
    pkg-config \
    libsdl2-dev \
    zstd \
    && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# 2. Clone Repository
# -----------------------------------------------------------------------------
echo "[2/7] Cloning Meetily repository..."
cd /workspace
if [ ! -d "meeting-minutes" ]; then
    git clone https://github.com/Zackriya-Solutions/meeting-minutes.git
fi
cd meeting-minutes

# -----------------------------------------------------------------------------
# 3. Build Whisper Server (GPU-accelerated)
# -----------------------------------------------------------------------------
echo "[3/7] Building Whisper server with CUDA support..."
cd /workspace/meeting-minutes/backend

# Initialize whisper.cpp submodule if needed
if [ ! -d "whisper.cpp" ] || [ -z "$(ls -A whisper.cpp 2>/dev/null)" ]; then
    echo "Initializing whisper.cpp submodule..."
    cd /workspace/meeting-minutes
    git submodule update --init --recursive
    cd /workspace/meeting-minutes/backend
fi

cd whisper.cpp

# Build with CUDA
cmake -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DWHISPER_BUILD_SERVER=ON \
    -DWHISPER_BUILD_EXAMPLES=ON \
    -DWHISPER_BUILD_TESTS=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    -DGGML_STATIC=ON \
    -DGGML_CUDA=ON \
    -DGGML_NATIVE=OFF

cmake --build build --config Release --target whisper-server -j$(nproc)

echo "Whisper server built successfully!"

# -----------------------------------------------------------------------------
# 4. Download Whisper Model
# -----------------------------------------------------------------------------
echo "[4/7] Downloading Whisper model..."
WHISPER_MODEL="${WHISPER_MODEL:-base.en}"
mkdir -p /workspace/meeting-minutes/backend/models

MODEL_PATH="/workspace/meeting-minutes/backend/models/ggml-${WHISPER_MODEL}.bin"
if [ ! -f "$MODEL_PATH" ]; then
    echo "Downloading model: ${WHISPER_MODEL}..."
    wget -q --show-progress -O "$MODEL_PATH" \
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-${WHISPER_MODEL}.bin"
else
    echo "Model already exists: ${WHISPER_MODEL}"
fi

# -----------------------------------------------------------------------------
# 5. Install Python Backend Dependencies
# -----------------------------------------------------------------------------
echo "[5/7] Installing Python dependencies..."
cd /workspace/meeting-minutes/backend
pip install --upgrade pip
pip install -r requirements.txt

# Create data directory for SQLite
mkdir -p /workspace/meeting-minutes/backend/data

# -----------------------------------------------------------------------------
# 6. Install Ollama (for LLM summarization)
# -----------------------------------------------------------------------------
echo "[6/7] Installing Ollama..."
if ! command -v ollama &> /dev/null; then
    curl -fsSL https://ollama.com/install.sh | sh
fi

# -----------------------------------------------------------------------------
# 7. Create startup scripts
# -----------------------------------------------------------------------------
echo "[7/7] Creating startup scripts..."

# Create start-all.sh script
cat > /workspace/start-meetily.sh << 'EOF'
#!/bin/bash
# Start all Meetily services

echo "Starting Meetily services..."

# Auto-install Ollama if missing (deleted on pod restart)
if ! command -v ollama &> /dev/null; then
    echo "Ollama not found. Installing..."
    # Install zstd if needed (required by Ollama installer)
    if ! command -v zstd &> /dev/null; then
        apt-get update && apt-get install -y zstd
    fi
    curl -fsSL https://ollama.com/install.sh | sh
fi

# Auto-install Python dependencies if missing (deleted on pod restart)
if ! command -v uvicorn &> /dev/null; then
    echo "Python dependencies not found. Installing..."
    pip install -r /workspace/meeting-minutes/backend/requirements.txt
fi

# Set environment variables
export WHISPER_MODEL=${WHISPER_MODEL:-models/ggml-base.en.bin}
export WHISPER_HOST=0.0.0.0
export WHISPER_PORT=8178
export WHISPER_USE_GPU=true
export OLLAMA_HOST=0.0.0.0:11434
export DATABASE_PATH=/workspace/meeting-minutes/backend/data/meeting_minutes.db

# Start Ollama in background
echo "Starting Ollama..."
ollama serve &
OLLAMA_PID=$!
sleep 5

# Pull a default model if not exists
ollama pull llama3.2:3b 2>/dev/null || true

# Start Whisper server in background
echo "Starting Whisper server on port 8178..."
cd /workspace/meeting-minutes/backend/whisper.cpp
./build/bin/whisper-server \
    --model /workspace/meeting-minutes/backend/${WHISPER_MODEL} \
    --host 0.0.0.0 \
    --port 8178 \
    --threads 4 &
WHISPER_PID=$!
sleep 3

# Start FastAPI backend
echo "Starting FastAPI backend on port 5167..."
cd /workspace/meeting-minutes/backend/app
PYTHONPATH=/workspace/meeting-minutes/backend/app uvicorn main:app --host 0.0.0.0 --port 5167 &
BACKEND_PID=$!

echo ""
echo "=========================================="
echo "  Meetily Services Started!"
echo "=========================================="
echo ""
echo "Endpoints:"
echo "  - FastAPI Backend: http://0.0.0.0:5167"
echo "  - API Docs:        http://0.0.0.0:5167/docs"
echo "  - Whisper Server:  http://0.0.0.0:8178"
echo "  - Ollama:          http://0.0.0.0:11434"
echo ""
echo "PIDs:"
echo "  - Ollama:  $OLLAMA_PID"
echo "  - Whisper: $WHISPER_PID"
echo "  - Backend: $BACKEND_PID"
echo ""
echo "To expose publicly, configure RunPod TCP ports:"
echo "  - 5167 (Backend API)"
echo "  - 8178 (Whisper)"
echo "  - 11434 (Ollama)"
echo ""

# Keep script running
wait
EOF

chmod +x /workspace/start-meetily.sh

# Create stop script
cat > /workspace/stop-meetily.sh << 'EOF'
#!/bin/bash
echo "Stopping Meetily services..."
pkill -f "uvicorn.*main:app" || true
pkill -f "whisper-server" || true
pkill -f "ollama serve" || true
echo "All services stopped."
EOF

chmod +x /workspace/stop-meetily.sh

# Create test script
cat > /workspace/test-meetily.sh << 'EOF'
#!/bin/bash
echo "Testing Meetily services..."
echo ""

echo "1. Testing Backend API..."
curl -s http://localhost:5167/get-meetings | head -c 200
echo ""

echo "2. Testing Whisper Server..."
curl -s http://localhost:8178/ | head -c 200
echo ""

echo "3. Testing Ollama..."
curl -s http://localhost:11434/api/tags | head -c 200
echo ""

echo "All tests complete!"
EOF

chmod +x /workspace/test-meetily.sh

echo ""
echo "=========================================="
echo "  Setup Complete!"
echo "=========================================="
echo ""
echo "To start services:"
echo "  /workspace/start-meetily.sh"
echo ""
echo "To stop services:"
echo "  /workspace/stop-meetily.sh"
echo ""
echo "To test services:"
echo "  /workspace/test-meetily.sh"
echo ""
echo "Expose these TCP ports in RunPod:"
echo "  - 5167 (Backend API - main endpoint)"
echo "  - 8178 (Whisper transcription)"
echo "  - 11434 (Ollama LLM)"
echo ""
