"""
Diarization Service - FastAPI application for transcription with speaker identification.

This service acts as a wrapper around whisper.cpp, adding speaker diarization
using pyannote.audio. It provides a compatible API for existing clients while
enriching the output with speaker labels.

Ports:
    - 8179: This diarization service
    - 8178: Whisper.cpp server (called internally)
"""
import os
import uuid
import shutil
import logging
from pathlib import Path
from typing import Optional
from contextlib import asynccontextmanager

from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from .config import DiarizationConfig
from .processor import AudioProcessor

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - [%(filename)s:%(lineno)d] - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)

# Global processor instance
processor: Optional[AudioProcessor] = None

# Temp directory for uploaded files
UPLOAD_DIR = Path("/tmp/diarization_uploads")


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan handler - initialize and cleanup resources."""
    global processor

    logger.info("=" * 60)
    logger.info("Starting Diarization Service")
    logger.info("=" * 60)

    # Create upload directory
    UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
    logger.info(f"Upload directory: {UPLOAD_DIR}")

    # Initialize processor
    try:
        config = DiarizationConfig()
        processor = AudioProcessor(config)
        logger.info("AudioProcessor initialized successfully")
    except Exception as e:
        logger.error(f"Failed to initialize AudioProcessor: {e}")
        # Continue anyway - health endpoint will report degraded status

    logger.info("=" * 60)
    logger.info("Diarization Service Ready")
    logger.info("=" * 60)

    yield

    # Cleanup
    logger.info("Shutting down Diarization Service")
    if UPLOAD_DIR.exists():
        try:
            shutil.rmtree(UPLOAD_DIR)
            logger.info("Cleaned up upload directory")
        except Exception as e:
            logger.warning(f"Failed to cleanup upload directory: {e}")


app = FastAPI(
    title="Diarization Service",
    description="Transcription with speaker diarization using Whisper + Pyannote",
    version="1.0.0",
    lifespan=lifespan
)

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/")
async def root():
    """Root endpoint - basic service info."""
    return {
        "service": "Diarization Service",
        "version": "1.0.0",
        "endpoints": {
            "/health": "Service health check",
            "/inference": "Transcribe with diarization (whisper.cpp compatible)",
            "/transcribe": "Transcribe with diarization"
        }
    }


@app.get("/health")
async def health():
    """Health check endpoint with detailed status."""
    global processor

    whisper_ok = False
    diarization_ok = False

    if processor:
        # Check whisper server
        whisper_ok = await processor.whisper_client.health_check()
        diarization_ok = processor.diarization_available

    status = "ok" if (whisper_ok and diarization_ok) else (
        "degraded" if whisper_ok else "error"
    )

    return {
        "status": status,
        "services": {
            "whisper_server": "ok" if whisper_ok else "unavailable",
            "diarization": "ok" if diarization_ok else "unavailable"
        },
        "config": {
            "whisper_url": processor.config.whisper_server_url if processor else None,
            "diarization_model": processor.config.diarization_pipeline_name if processor else None,
            "device": processor.config.device_str if processor else None
        }
    }


@app.post("/inference")
async def inference(
    file: UploadFile = File(...),
    response_format: str = Form("json"),
    diarize: bool = Form(True),
    temperature: Optional[str] = Form("0.0"),
):
    """
    Transcribe audio with optional speaker diarization.

    This endpoint is compatible with the whisper.cpp /inference API,
    but adds speaker diarization when diarize=True.

    Args:
        file: Audio file to transcribe
        response_format: Response format (only 'json' supported)
        diarize: Enable speaker diarization (default True)
        temperature: Whisper temperature parameter (passed through)

    Returns:
        JSON with transcription segments including speaker labels
    """
    global processor

    if not processor:
        raise HTTPException(
            status_code=503,
            detail="Service not initialized"
        )

    # Save uploaded file
    file_id = str(uuid.uuid4())
    file_ext = Path(file.filename).suffix if file.filename else ".wav"
    temp_path = UPLOAD_DIR / f"{file_id}{file_ext}"

    try:
        # Save uploaded file
        with open(temp_path, "wb") as f:
            content = await file.read()
            f.write(content)

        logger.info(f"Processing file: {file.filename} ({len(content)} bytes)")

        # Process audio
        segments = await processor.process_audio(
            audio_path=str(temp_path),
            enable_diarization=diarize
        )

        if not segments:
            logger.warning("No segments returned from processing")
            return JSONResponse(
                status_code=200,
                content={"segments": [], "text": ""}
            )

        # Build response
        full_text = " ".join(seg["text"] for seg in segments if seg.get("text"))

        return {
            "segments": segments,
            "text": full_text
        }

    except Exception as e:
        logger.error(f"Processing failed: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Processing failed: {str(e)}"
        )

    finally:
        # Cleanup uploaded file
        if temp_path.exists():
            try:
                temp_path.unlink()
            except Exception as e:
                logger.warning(f"Failed to cleanup temp file: {e}")


@app.post("/transcribe")
async def transcribe(
    file: UploadFile = File(...),
    diarize: bool = Form(True),
):
    """
    Transcribe audio with speaker diarization.

    Simplified endpoint that always returns diarized transcription.

    Args:
        file: Audio file to transcribe
        diarize: Enable speaker diarization (default True)

    Returns:
        JSON with transcription segments including speaker labels
    """
    return await inference(file=file, response_format="json", diarize=diarize)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8179,
        reload=False
    )
