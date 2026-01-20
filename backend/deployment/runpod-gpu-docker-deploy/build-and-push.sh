#!/bin/bash
# =============================================================================
# Build and Push Meetily GPU Docker Image
# =============================================================================

set -e

# Configuration - UPDATE THESE
DOCKER_USERNAME="${DOCKER_USERNAME:-kimwwk}"
IMAGE_NAME="meetily-gpu-services"
TAG="${TAG:-latest}"

# Optional: Use a different Whisper model (base.en, small.en, medium.en, large-v3)
WHISPER_MODEL="${WHISPER_MODEL:-base.en}"

FULL_IMAGE="${DOCKER_USERNAME}/${IMAGE_NAME}:${TAG}"

echo "=========================================="
echo "  Building Meetily GPU Docker Image"
echo "=========================================="
echo ""
echo "Image: ${FULL_IMAGE}"
echo "Whisper Model: ${WHISPER_MODEL}"
echo ""

# Build the image
docker build \
    -f Dockerfile.runpod-gpu \
    --build-arg WHISPER_MODEL=${WHISPER_MODEL} \
    -t ${FULL_IMAGE} \
    .

echo ""
echo "Build complete!"
echo ""

# Ask to push
read -p "Push to Docker Hub? (y/n) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Logging in to Docker Hub..."
    docker login

    echo "Pushing ${FULL_IMAGE}..."
    docker push ${FULL_IMAGE}

    echo ""
    echo "=========================================="
    echo "  Push Complete!"
    echo "=========================================="
    echo ""
    echo "Your image is now available at:"
    echo "  docker.io/${FULL_IMAGE}"
    echo ""
    echo "RunPod Template Settings:"
    echo "  Container Image: ${FULL_IMAGE}"
    echo "  Docker Command:  (leave empty - uses CMD from Dockerfile)"
    echo "  Exposed Ports:   8178, 11434"
    echo ""
fi
