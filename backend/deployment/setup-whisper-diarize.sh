#!/bin/bash
# =============================================================================
# Whisper + Diarization Setup Script (CPU)
# For Proxmox CT / systems without GPU
# Clones from git repo directly
# =============================================================================

set -e

WHISPER_MODEL="${WHISPER_MODEL:-large-v3}"
INSTALL_DIR="${INSTALL_DIR:-/workspace}"
HF_AUTH_TOKEN="${HF_AUTH_TOKEN:-}"
REPO_URL="${REPO_URL:-https://github.com/kimwwk/meeting-minutes.git}"
REPO_BRANCH="${REPO_BRANCH:-feat/speaker-diarization}"

echo "==========================================="
echo "  Whisper + Diarization Setup (CPU)"
echo "==========================================="
echo "  Model: $WHISPER_MODEL"
echo "  Install dir: $INSTALL_DIR"
echo "  Repo: $REPO_URL"
echo "  Branch: $REPO_BRANCH"
echo "==========================================="

# -----------------------------------------------------------------------------
# 1. System Dependencies
# -----------------------------------------------------------------------------
echo ""
echo "[1/6] Installing system dependencies..."
apt-get update
apt-get install -y \
    build-essential \
    cmake \
    git \
    wget \
    curl \
    ffmpeg \
    python3 \
    python3-pip \
    python3-venv

# -----------------------------------------------------------------------------
# 2. Clone Repository
# -----------------------------------------------------------------------------
echo ""
echo "[2/6] Cloning repository..."
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

if [ ! -d "meeting-minutes" ]; then
    git clone -b "$REPO_BRANCH" "$REPO_URL"
fi
cd meeting-minutes

# Initialize whisper.cpp submodule
if [ ! -d "backend/whisper.cpp" ] || [ -z "$(ls -A backend/whisper.cpp 2>/dev/null)" ]; then
    echo "Initializing whisper.cpp submodule..."
    git submodule update --init --recursive
fi

# -----------------------------------------------------------------------------
# 3. Build Whisper.cpp (CPU)
# -----------------------------------------------------------------------------
echo ""
echo "[3/6] Building whisper.cpp (CPU)..."
cd "$INSTALL_DIR/meeting-minutes/backend/whisper.cpp"

cmake -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DWHISPER_BUILD_SERVER=ON \
    -DWHISPER_BUILD_EXAMPLES=ON \
    -DWHISPER_BUILD_TESTS=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    -DGGML_STATIC=ON \
    -DGGML_NATIVE=ON \
    -DGGML_CUDA=OFF \
    -DGGML_METAL=OFF

cmake --build build --config Release --target whisper-server -j$(nproc)

echo "Whisper server built successfully!"

# -----------------------------------------------------------------------------
# 4. Download Whisper Model
# -----------------------------------------------------------------------------
echo ""
echo "[4/6] Downloading Whisper model ($WHISPER_MODEL)..."
mkdir -p "$INSTALL_DIR/meeting-minutes/backend/models"

MODEL_PATH="$INSTALL_DIR/meeting-minutes/backend/models/ggml-${WHISPER_MODEL}.bin"
if [ ! -f "$MODEL_PATH" ]; then
    wget -O "$MODEL_PATH" \
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-${WHISPER_MODEL}.bin"
else
    echo "Model already exists, skipping download"
fi

# -----------------------------------------------------------------------------
# 5. Setup Python Environment for Diarization
# -----------------------------------------------------------------------------
echo ""
echo "[5/6] Setting up diarization service..."
cd "$INSTALL_DIR/meeting-minutes/backend"

python3 -m venv venv
source venv/bin/activate

pip install --upgrade pip
pip install \
    fastapi>=0.115.0 \
    "uvicorn[standard]>=0.34.0" \
    python-multipart>=0.0.9 \
    httpx>=0.27.0 \
    "torch<2.6" \
    "torchaudio<2.6" \
    "huggingface_hub>=0.20.0,<0.23.0" \
    "pyannote.audio>=3.1.0,<4.0"

# -----------------------------------------------------------------------------
# 6. Create Start/Stop Scripts
# -----------------------------------------------------------------------------
echo ""
echo "[6/6] Creating management scripts..."

# Start script
cat > "$INSTALL_DIR/start-whisper-diarize.sh" << 'EOF'
#!/bin/bash
cd /workspace/meeting-minutes/backend

export WHISPER_MODEL="${WHISPER_MODEL:-large-v3}"
export WHISPER_SERVER_URL=http://localhost:8178
export HF_AUTH_TOKEN="${HF_AUTH_TOKEN:-}"

THREADS="${WHISPER_THREADS:-$(nproc)}"

echo "Starting Whisper server (model: $WHISPER_MODEL, threads: $THREADS)..."
./whisper.cpp/build/bin/whisper-server \
    --model ./models/ggml-${WHISPER_MODEL}.bin \
    --host 0.0.0.0 \
    --port 8178 \
    --threads $THREADS &
echo $! > /tmp/whisper.pid

# Wait for Whisper
for i in {1..30}; do
    curl -s http://localhost:8178/ > /dev/null 2>&1 && break
    sleep 1
done
echo "Whisper server ready on port 8178"

echo "Starting Diarization service..."
source venv/bin/activate
python -m uvicorn diarization_service.main:app --host 0.0.0.0 --port 8179 &
echo $! > /tmp/diarization.pid

echo ""
echo "==========================================="
echo "  Services Running"
echo "==========================================="
echo "  Whisper:      http://0.0.0.0:8178"
echo "  Diarization:  http://0.0.0.0:8179"
echo "==========================================="

wait
EOF

# Stop script
cat > "$INSTALL_DIR/stop-whisper-diarize.sh" << 'EOF'
#!/bin/bash
echo "Stopping services..."
[ -f /tmp/whisper.pid ] && kill $(cat /tmp/whisper.pid) 2>/dev/null && rm /tmp/whisper.pid
[ -f /tmp/diarization.pid ] && kill $(cat /tmp/diarization.pid) 2>/dev/null && rm /tmp/diarization.pid
pkill -f "whisper-server" 2>/dev/null || true
pkill -f "diarization_service" 2>/dev/null || true
echo "Stopped"
EOF

# Test script
cat > "$INSTALL_DIR/test-whisper-diarize.sh" << 'EOF'
#!/bin/bash
echo "Testing services..."
echo ""
echo "Whisper (8178):"
curl -s http://localhost:8178/ && echo " OK" || echo "NOT RUNNING"
echo ""
echo "Diarization (8179):"
curl -s http://localhost:8179/health || echo "NOT RUNNING"
EOF

chmod +x "$INSTALL_DIR"/*.sh

# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------
echo ""
echo "==========================================="
echo "  Setup Complete!"
echo "==========================================="
echo ""
echo "  Set your HuggingFace token:"
echo "    export HF_AUTH_TOKEN=hf_xxxxx"
echo ""
echo "  Start services:"
echo "    $INSTALL_DIR/start-whisper-diarize.sh"
echo ""
echo "  Stop services:"
echo "    $INSTALL_DIR/stop-whisper-diarize.sh"
echo ""
echo "  Test services:"
echo "    $INSTALL_DIR/test-whisper-diarize.sh"
echo ""
echo "==========================================="
