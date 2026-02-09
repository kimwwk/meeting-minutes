from pydantic import BaseModel
from typing import Optional, List, Dict, Any
from datetime import datetime


class Block(BaseModel):
    """A content block within a section"""
    id: str
    type: str  # 'text', 'bullet', 'heading1', 'heading2'
    content: str
    color: Optional[str] = ""


class Section(BaseModel):
    """A section in the summary"""
    title: str
    blocks: List[Block]


class CreateSummaryRequest(BaseModel):
    """Request to create a custom template summary entry"""
    meeting_id: str
    template_id: str


class SaveSummaryRequest(BaseModel):
    """Request to save a custom template summary result"""
    meeting_id: str
    template_id: Optional[str] = None
    result: Dict[str, Any]  # Flexible: {"MeetingName": "", "MeetingNotes": {"sections": [...]}}


class CustomTemplateSummary(BaseModel):
    """Response model for custom template summary"""
    meeting_id: str
    template_id: Optional[str] = None
    status: str  # 'pending', 'completed', 'error'
    result: Optional[Dict[str, Any]] = None
    error: Optional[str] = None
    created_at: Optional[str] = None
    updated_at: Optional[str] = None


class CustomTemplateSummaryResponse(BaseModel):
    """Full response for get-summary endpoint"""
    status: str
    meeting_id: str
    meetingName: Optional[str] = None
    data: Optional[Dict[str, Any]] = None
    error: Optional[str] = None
