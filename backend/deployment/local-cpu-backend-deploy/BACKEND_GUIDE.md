# Meetily Services API Documentation

This document describes the three backend services that power the Meetily meeting transcription and summarization system.

---

## Architecture Overview

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Frontend      │     │  Whisper Server │     │     Ollama      │
│   (Next.js)     │     │   (Port 8178)   │     │  (Port 11434)   │
└────────┬────────┘     └────────┬────────┘     └────────┬────────┘
         │                       │                       │
         │  Audio File           │                       │
         ├──────────────────────►│                       │
         │  Transcript Text      │                       │
         │◄──────────────────────┤                       │
         │                       │                       │
         │         ┌─────────────────────────┐           │
         │         │   Backend API           │           │
         ├────────►│   (Port 5167)           │◄──────────┤
         │         │   - Meeting Storage     │  LLM API  │
         │◄────────┤   - Summary Processing  ├──────────►│
         │         │   - Configuration       │           │
         │         └─────────────────────────┘           │
```

**Flow:**
1. Frontend records audio → sends to Whisper for transcription
2. Frontend saves transcript text → Backend API stores in SQLite
3. User requests summary → Backend sends transcript to Ollama
4. Backend stores summary → Frontend displays result

---

## Service 1: Whisper Server (Port 8178)

**Purpose:** Speech-to-text transcription using OpenAI's Whisper model.

**Technology:** whisper.cpp (C++ implementation for performance)

### Endpoints

#### `POST /inference`

Transcribe an audio file to text.

**Request:**
- Content-Type: `multipart/form-data`
- Body:
  | Field | Type | Required | Description |
  |-------|------|----------|-------------|
  | `file` | File | Yes | Audio file (WAV format, 16kHz sample rate) |
  | `response_format` | String | No | Output format: `json`, `text`, `srt`, `vtt` (default: `json`) |
  | `temperature` | Float | No | Sampling temperature (default: 0.0) |
  | `language` | String | No | Language code, e.g., `en` (default: auto-detect) |

**Response (JSON format):**
```json
{
  "text": "Hello, this is a test recording."
}
```

**Response (SRT format):**
```
1
00:00:00,000 --> 00:00:02,500
Hello, this is a test recording.
```

**Important Notes:**
- Audio MUST be WAV format at 16kHz sample rate
- WebM/MP3/other formats must be converted before sending
- Large files may take significant time to process
- GPU acceleration significantly improves speed

**Example Usage:**
```bash
curl -X POST http://localhost:8178/inference \
  -F "file=@recording.wav" \
  -F "response_format=json"
```

---

## Service 2: Backend API (Port 5167)

**Purpose:** Core application backend handling meeting storage, transcript management, summary generation orchestration, and configuration.

**Technology:** Python FastAPI with SQLite database

### Meeting Management Endpoints

#### `GET /get-meetings`

Get list of all meetings.

**Response:**
```json
[
  { "id": "meeting-1768443431591", "title": "Team Standup" },
  { "id": "meeting-1768443123456", "title": "Project Review" }
]
```

---

#### `GET /get-meeting/{meeting_id}`

Get a specific meeting with all its transcripts.

**Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `meeting_id` | String (path) | The meeting ID |

**Response:**
```json
{
  "id": "meeting-1768443431591",
  "title": "Team Standup",
  "created_at": "2026-01-15T02:17:11.000Z",
  "updated_at": "2026-01-15T02:17:11.000Z",
  "transcripts": [
    {
      "id": "meeting-1768443431591",
      "text": "Hello everyone, let's discuss the project status.",
      "timestamp": "2026-01-15T02:17:11.540Z",
      "audio_start_time": 0.0,
      "audio_end_time": 4.5,
      "duration": 4.5
    }
  ]
}
```

---

#### `POST /save-meeting-title`

Update a meeting's title.

**Request:**
```json
{
  "meeting_id": "meeting-1768443431591",
  "title": "Updated Meeting Title"
}
```

**Response:**
```json
{
  "message": "Meeting title saved successfully"
}
```

---

#### `POST /delete-meeting`

Delete a meeting and all associated data.

**Request:**
```json
{
  "meeting_id": "meeting-1768443431591"
}
```

**Response:**
```json
{
  "status": "success",
  "message": "Meeting deleted successfully"
}
```

---

### Transcript Endpoints

#### `POST /save-transcript`

Save a new meeting with transcript segments. Creates the meeting if it doesn't exist.

**Request:**
```json
{
  "meeting_title": "Team Standup",
  "transcripts": [
    {
      "id": "transcript-1768443431540",
      "text": "Hello everyone, let's discuss the project.",
      "timestamp": "2026-01-15T02:17:11.540Z",
      "audio_start_time": 0.0,
      "audio_end_time": 4.5,
      "duration": 4.5
    }
  ],
  "folder_path": "/optional/path/to/meeting/folder"
}
```

**Response:**
```json
{
  "status": "success",
  "message": "Transcript saved successfully",
  "meeting_id": "meeting-1768443431591"
}
```

**Notes:**
- `meeting_id` is auto-generated based on timestamp
- `audio_start_time`, `audio_end_time`, `duration` are optional (for audio playback sync)
- `folder_path` is optional (for file-based storage)

---

#### `POST /search-transcripts`

Search across all transcripts.

**Request:**
```json
{
  "query": "project deadline"
}
```

**Response:**
```json
[
  {
    "id": "meeting-1768443431591",
    "title": "Team Standup",
    "matchContext": "...discussing the project deadline for next week...",
    "timestamp": "2026-01-15T02:17:11.540Z"
  }
]
```

---

### Summary Generation Endpoints

#### `POST /process-transcript`

Start background summary generation using LLM.

**Request:**
```json
{
  "text": "Full transcript text here...",
  "model": "ollama",
  "model_name": "llama3.2:3b",
  "meeting_id": "meeting-1768443431591",
  "chunk_size": 5000,
  "overlap": 1000,
  "custom_prompt": "Generate a summary of the meeting transcript."
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `text` | String | Yes | Full transcript text |
| `model` | String | Yes | Provider: `ollama`, `claude`, `groq`, `openai` |
| `model_name` | String | Yes | Model identifier, e.g., `llama3.2:3b` |
| `meeting_id` | String | Yes | Meeting ID to associate summary with |
| `chunk_size` | Integer | No | Characters per chunk (default: 5000) |
| `overlap` | Integer | No | Overlap between chunks (default: 1000) |
| `custom_prompt` | String | No | Custom summarization instructions |

**Response:**
```json
{
  "message": "Processing started",
  "process_id": "proc-1768443431591"
}
```

**Notes:**
- Processing happens asynchronously in background
- Poll `/get-summary/{meeting_id}` for status and results
- Large transcripts are chunked and processed in parts

---

#### `GET /get-summary/{meeting_id}`

Get summary status and results for a meeting.

**Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `meeting_id` | String (path) | The meeting ID |

**Response (Processing):** HTTP 202
```json
{
  "status": "processing",
  "meetingName": null,
  "meeting_id": "meeting-1768443431591",
  "start": "2026-01-15T02:17:11.000Z",
  "end": null,
  "data": null
}
```

**Response (Completed):** HTTP 200
```json
{
  "status": "completed",
  "meetingName": "Team Standup",
  "meeting_id": "meeting-1768443431591",
  "start": "2026-01-15T02:17:11.000Z",
  "end": "2026-01-15T02:17:45.000Z",
  "data": {
    "MeetingName": "Team Standup",
    "session_summary": {
      "title": "Session Summary",
      "blocks": [{ "content": "Team discussed Q1 goals..." }]
    },
    "action_items": {
      "title": "Action Items",
      "blocks": [{ "content": "Complete project proposal by Friday" }]
    },
    "_section_order": ["session_summary", "action_items"]
  }
}
```

**Response (Error):** HTTP 400
```json
{
  "status": "error",
  "meetingName": null,
  "meeting_id": "meeting-1768443431591",
  "data": null,
  "error": "LLM processing failed: connection timeout"
}
```

**Response (Not Found):** HTTP 404
```json
{
  "status": "error",
  "meetingName": null,
  "meeting_id": "meeting-1768443431591",
  "data": null,
  "error": "Meeting ID not found"
}
```

**Status Values:**
| Status | Description |
|--------|-------------|
| `pending` | Waiting to start |
| `processing` | Currently generating summary |
| `completed` | Summary ready |
| `error` / `failed` | Processing failed |
| `cancelled` | User cancelled |

---

#### `POST /save-meeting-summary`

Manually save/update a meeting summary.

**Request:**
```json
{
  "meeting_id": "meeting-1768443431591",
  "summary": {
    "MeetingName": "Team Standup",
    "session_summary": { "blocks": [...] }
  }
}
```

**Response:**
```json
{
  "message": "Meeting summary saved successfully"
}
```

---

### Configuration Endpoints

#### `GET /get-model-config`

Get current LLM model configuration.

**Response:**
```json
{
  "provider": "ollama",
  "model": "llama3.2:3b",
  "whisperModel": "base",
  "apiKey": null
}
```

**Notes:**
- Returns `null` if no configuration saved
- `apiKey` only returned if stored for the provider

---

#### `POST /save-model-config`

Save LLM model configuration.

**Request:**
```json
{
  "provider": "ollama",
  "model": "llama3.2:3b",
  "whisperModel": "base",
  "apiKey": "optional-api-key"
}
```

**Response:**
```json
{
  "status": "success",
  "message": "Model configuration saved successfully"
}
```

---

#### `GET /get-transcript-config`

Get transcription service configuration.

**Response:**
```json
{
  "provider": "local",
  "model": "whisper-base",
  "apiKey": null
}
```

---

#### `POST /save-transcript-config`

Save transcription service configuration.

**Request:**
```json
{
  "provider": "local",
  "model": "whisper-base",
  "apiKey": null
}
```

---

#### `POST /get-api-key`

Retrieve stored API key for a provider.

**Request:**
```json
{
  "provider": "openai"
}
```

**Response:**
```json
"sk-..."
```

---

## Service 3: Ollama (Port 11434)

**Purpose:** Local LLM inference for generating meeting summaries.

**Technology:** Ollama runtime with various model support

### Endpoints

#### `POST /api/generate`

Generate text completion (used by backend for summaries).

**Request:**
```json
{
  "model": "llama3.2:3b",
  "prompt": "Summarize this meeting transcript:\n\n[transcript text]",
  "stream": false,
  "options": {
    "temperature": 0.7,
    "num_predict": 2048
  }
}
```

**Response:**
```json
{
  "model": "llama3.2:3b",
  "response": "## Meeting Summary\n\nThe team discussed...",
  "done": true,
  "total_duration": 5234567890,
  "load_duration": 1234567,
  "prompt_eval_count": 150,
  "eval_count": 200
}
```

---

#### `POST /api/chat`

Chat-style completion (alternative to generate).

**Request:**
```json
{
  "model": "llama3.2:3b",
  "messages": [
    {
      "role": "system",
      "content": "You are a meeting summarization assistant."
    },
    {
      "role": "user",
      "content": "Summarize this transcript: [text]"
    }
  ],
  "stream": false
}
```

**Response:**
```json
{
  "model": "llama3.2:3b",
  "message": {
    "role": "assistant",
    "content": "## Meeting Summary\n\n..."
  },
  "done": true
}
```

---

#### `GET /api/tags`

List available models.

**Response:**
```json
{
  "models": [
    {
      "name": "llama3.2:3b",
      "modified_at": "2026-01-15T00:00:00Z",
      "size": 2000000000
    }
  ]
}
```

---

#### `POST /api/pull`

Download a model.

**Request:**
```json
{
  "name": "llama3.2:3b"
}
```

---

#### `GET /`

Health check - returns "Ollama is running" if service is up.

---

## RunPod URL Pattern

On RunPod, services are exposed via proxy URLs:

```
https://{POD_ID}-{PORT}.proxy.runpod.net
```

**Examples:**
- Backend API: `https://6u8hng3b8qhng3-5167.proxy.runpod.net`
- Whisper Server: `https://6u8hng3b8qhng3-8178.proxy.runpod.net`
- Ollama: `https://6u8hng3b8qhng3-11434.proxy.runpod.net`

---

## Complete Flow Example

### 1. Record and Transcribe

```bash
# Frontend converts WebM to WAV (16kHz) and sends to Whisper
POST https://xxx-8178.proxy.runpod.net/inference
Content-Type: multipart/form-data

file: recording.wav
response_format: json

# Response
{ "text": "Hello everyone, let's discuss the project timeline." }
```

### 2. Save Transcript

```bash
POST https://xxx-5167.proxy.runpod.net/save-transcript
Content-Type: application/json

{
  "meeting_title": "Project Discussion",
  "transcripts": [{
    "id": "transcript-123",
    "text": "Hello everyone, let's discuss the project timeline.",
    "timestamp": "2026-01-15T02:17:11.540Z"
  }]
}

# Response
{ "meeting_id": "meeting-1768443431591" }
```

### 3. Generate Summary

```bash
POST https://xxx-5167.proxy.runpod.net/process-transcript
Content-Type: application/json

{
  "text": "Hello everyone, let's discuss the project timeline.",
  "model": "ollama",
  "model_name": "llama3.2:3b",
  "meeting_id": "meeting-1768443431591"
}

# Response
{ "message": "Processing started", "process_id": "proc-123" }
```

### 4. Poll for Results

```bash
GET https://xxx-5167.proxy.runpod.net/get-summary/meeting-1768443431591

# Response (when complete)
{
  "status": "completed",
  "data": {
    "session_summary": { "blocks": [{ "content": "Team discussed project timeline..." }] }
  }
}
```

---

## Error Handling

| HTTP Code | Meaning |
|-----------|---------|
| 200 | Success |
| 202 | Accepted (processing in background) |
| 400 | Bad request / Processing failed |
| 404 | Resource not found |
| 500 | Internal server error |

---

## Environment Variables

| Variable | Service | Description |
|----------|---------|-------------|
| `NEXT_PUBLIC_API_URL` | Frontend | Backend API URL |
| `OLLAMA_HOST` | Backend | Ollama server URL (default: http://localhost:11434) |
| `DATABASE_PATH` | Backend | SQLite database path |
