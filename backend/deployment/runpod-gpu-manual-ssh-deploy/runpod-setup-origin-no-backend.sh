#!/bin/bash
# =============================================================================
# Meetily RunPod GPU Services Setup
# Deploys: Whisper Server + Ollama (GPU-accelerated)
# Template: runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04
# GPU: A40 (recommended) or RTX 4090
# =============================================================================
#
# This script sets up GPU services only. The FastAPI backend should be
# deployed separately (see backend-setup.sh).
#
# Architecture:
#   RunPod (this script):
#     - Whisper Server (port 8178) - Speech-to-text transcription
#     - Ollama (port 11434) - LLM summarization
#
#   Separate host (backend-setup.sh):
#     - FastAPI Backend (port 5167) - API server
#
# =============================================================================

set -e

echo "=========================================="
echo "  Meetily RunPod GPU Services Setup"
echo "=========================================="
echo ""
echo "This will install:"
echo "  - Whisper Server (GPU-accelerated transcription)"
echo "  - Ollama (GPU-accelerated LLM)"
echo ""

# -----------------------------------------------------------------------------
# 1. Install System Dependencies
# -----------------------------------------------------------------------------
echo "[1/5] Installing system dependencies..."
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
# 2. Clone Repository (for whisper.cpp)
# -----------------------------------------------------------------------------
echo "[2/5] Cloning Meetily repository..."
cd /workspace
if [ ! -d "meeting-minutes" ]; then
    git clone https://github.com/Zackriya-Solutions/meeting-minutes.git
fi
cd meeting-minutes

# -----------------------------------------------------------------------------
# 3. Build Whisper Server (GPU-accelerated)
# -----------------------------------------------------------------------------
echo "[3/5] Building Whisper server with CUDA support..."
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
echo "[4/5] Downloading Whisper model..."
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
# 5. Install Ollama (for LLM summarization)
# -----------------------------------------------------------------------------
echo "[5/5] Installing Ollama..."
if ! command -v ollama &> /dev/null; then
    curl -fsSL https://ollama.com/install.sh | sh
fi

# -----------------------------------------------------------------------------
# 6. Create startup scripts
# -----------------------------------------------------------------------------
echo "Creating startup scripts..."

# Create start script for GPU services
cat > /workspace/start-gpu-services.sh << 'EOF'
#!/bin/bash
# Start Meetily GPU Services (Whisper + Ollama)

echo "Starting Meetily GPU Services..."

# Auto-install Ollama if missing (deleted on pod restart)
if ! command -v ollama &> /dev/null; then
    echo "Ollama not found. Installing..."
    if ! command -v zstd &> /dev/null; then
        apt-get update && apt-get install -y zstd
    fi
    curl -fsSL https://ollama.com/install.sh | sh
fi

# Set environment variables
export WHISPER_MODEL=${WHISPER_MODEL:-models/ggml-base.en.bin}
export WHISPER_HOST=0.0.0.0
export WHISPER_PORT=8178
export WHISPER_USE_GPU=true
export OLLAMA_HOST=0.0.0.0:11434

# Start Ollama in background
echo "Starting Ollama on port 11434..."
ollama serve &
OLLAMA_PID=$!
sleep 5

# Pull default model if not exists
echo "Pulling default Ollama model (llama3.2:3b)..."
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

echo ""
echo "=========================================="
echo "  Meetily GPU Services Started!"
echo "=========================================="
echo ""
echo "Endpoints (expose these TCP ports in RunPod):"
echo "  - Whisper Server:  http://0.0.0.0:8178"
echo "  - Ollama:          http://0.0.0.0:11434"
echo ""
echo "PIDs:"
echo "  - Ollama:  $OLLAMA_PID"
echo "  - Whisper: $WHISPER_PID"
echo ""
echo "For your backend deployment, set these environment variables:"
echo "  OLLAMA_HOST=http://<runpod-public-ip>:11434"
echo "  WHISPER_URL=http://<runpod-public-ip>:8178"
echo ""

# Keep script running
wait
EOF

chmod +x /workspace/start-gpu-services.sh

# Create stop script
cat > /workspace/stop-gpu-services.sh << 'EOF'
#!/bin/bash
echo "Stopping Meetily GPU services..."
pkill -f "whisper-server" || true
pkill -f "ollama serve" || true
echo "GPU services stopped."
EOF

chmod +x /workspace/stop-gpu-services.sh

# Create test script
cat > /workspace/test-gpu-services.sh << 'EOF'
#!/bin/bash
echo "Testing Meetily GPU services..."
echo ""

echo "1. Testing Whisper Server..."
WHISPER_RESPONSE=$(curl -s http://localhost:8178/ 2>/dev/null)
if [ -n "$WHISPER_RESPONSE" ]; then
    echo "   Whisper: OK"
    echo "   $WHISPER_RESPONSE" | head -c 100
else
    echo "   Whisper: FAILED (no response)"
fi
echo ""

echo "2. Testing Ollama..."
OLLAMA_RESPONSE=$(curl -s http://localhost:11434/api/tags 2>/dev/null)
if [ -n "$OLLAMA_RESPONSE" ]; then
    echo "   Ollama: OK"
    echo "   $OLLAMA_RESPONSE" | head -c 200
else
    echo "   Ollama: FAILED (no response)"
fi
echo ""

echo "Tests complete!"
EOF

chmod +x /workspace/test-gpu-services.sh

echo ""
echo "=========================================="
echo "  GPU Services Setup Complete!"
echo "=========================================="
echo ""
echo "To start services:"
echo "  /workspace/start-gpu-services.sh"
echo ""
echo "To stop services:"
echo "  /workspace/stop-gpu-services.sh"
echo ""
echo "To test services:"
echo "  /workspace/test-gpu-services.sh"
echo ""
echo "IMPORTANT: Expose these TCP ports in RunPod:"
echo "  - 8178 (Whisper transcription)"
echo "  - 11434 (Ollama LLM)"
echo ""
echo "After starting, note your RunPod public IP/URL for backend config."
echo ""
