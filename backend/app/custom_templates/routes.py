from fastapi import APIRouter, HTTPException
from fastapi.responses import JSONResponse
from typing import Dict, Any
import logging

from .models import CreateSummaryRequest, SaveSummaryRequest, CustomTemplateSummaryResponse
from .db import CustomTemplateSummaryDB

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/custom-template", tags=["Custom Templates"])

# Initialize database
db = CustomTemplateSummaryDB()


def transform_to_frontend_format(summary_data: Dict[str, Any]) -> Dict[str, Any]:
    """Transform summary data into frontend format with _section_order"""
    transformed_data = {}

    if not isinstance(summary_data, dict):
        return transformed_data

    # Add MeetingName
    transformed_data["MeetingName"] = summary_data.get("MeetingName", "")

    # Add meeting notes sections if available - PRESERVE ORDER
    if "MeetingNotes" in summary_data and isinstance(summary_data["MeetingNotes"], dict):
        meeting_notes = summary_data["MeetingNotes"]
        if isinstance(meeting_notes.get("sections"), list):
            transformed_data["_section_order"] = []
            used_keys = set()

            for index, section in enumerate(meeting_notes["sections"]):
                if isinstance(section, dict) and "title" in section and "blocks" in section:
                    # Ensure blocks is a list
                    if not isinstance(section.get("blocks"), list):
                        section["blocks"] = []

                    # Convert title to snake_case key
                    base_key = section["title"].lower().replace(" & ", "_").replace(" ", "_")

                    # Handle duplicate section names by adding index
                    key = base_key
                    if key in used_keys:
                        key = f"{base_key}_{index}"

                    used_keys.add(key)
                    transformed_data[key] = section
                    transformed_data["_section_order"].append(key)

    return transformed_data


@router.post("/create")
async def create_custom_summary(request: CreateSummaryRequest):
    """
    Create a custom template summary entry with pending status.
    Call this before generating the summary on the frontend.
    """
    try:
        result = await db.create_summary(request.meeting_id, request.template_id)
        return JSONResponse(
            status_code=201,
            content={
                "message": "Custom template summary created",
                "meeting_id": result["meeting_id"],
                "template_id": result["template_id"],
                "status": result["status"]
            }
        )
    except Exception as e:
        logger.error(f"Error creating custom template summary: {str(e)}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/save")
async def save_custom_summary(request: SaveSummaryRequest):
    """
    Save a completed custom template summary.
    This sets status to 'completed' so get-summary returns the data.
    Supports upsert - creates entry if it doesn't exist.
    """
    try:
        await db.save_summary(
            meeting_id=request.meeting_id,
            result=request.result,
            template_id=request.template_id
        )
        return JSONResponse(
            status_code=200,
            content={
                "message": "Custom template summary saved successfully",
                "meeting_id": request.meeting_id,
                "status": "completed"
            }
        )
    except Exception as e:
        logger.error(f"Error saving custom template summary: {str(e)}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/summary/{meeting_id}")
async def get_custom_summary(meeting_id: str):
    """
    Get a custom template summary by meeting ID.
    Returns the summary in frontend-ready format with _section_order.
    """
    try:
        summary = await db.get_summary(meeting_id)

        if not summary:
            return JSONResponse(
                status_code=404,
                content={
                    "status": "not_found",
                    "meeting_id": meeting_id,
                    "meetingName": None,
                    "data": None,
                    "error": "No custom template summary found for this meeting"
                }
            )

        status = summary.get("status", "pending")
        result = summary.get("result")

        # Transform data for frontend if completed
        transformed_data = None
        meeting_name = None
        if status == "completed" and result:
            # Raw markdown storage: pass through directly
            if "markdown" in result:
                transformed_data = {"markdown": result["markdown"]}
            else:
                transformed_data = transform_to_frontend_format(result)
            meeting_name = result.get("MeetingName", "")

        response = {
            "status": status,
            "meeting_id": meeting_id,
            "meetingName": meeting_name,
            "template_id": summary.get("template_id"),
            "data": transformed_data,
            "error": summary.get("error")
        }

        if status == "completed":
            return JSONResponse(status_code=200, content=response)
        elif status == "pending":
            return JSONResponse(status_code=202, content=response)
        else:
            return JSONResponse(status_code=400, content=response)

    except Exception as e:
        logger.error(f"Error getting custom template summary: {str(e)}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.delete("/summary/{meeting_id}")
async def delete_custom_summary(meeting_id: str):
    """Delete a custom template summary"""
    try:
        deleted = await db.delete_summary(meeting_id)
        if deleted:
            return JSONResponse(
                status_code=200,
                content={"message": "Custom template summary deleted", "meeting_id": meeting_id}
            )
        else:
            return JSONResponse(
                status_code=404,
                content={"message": "Custom template summary not found", "meeting_id": meeting_id}
            )
    except Exception as e:
        logger.error(f"Error deleting custom template summary: {str(e)}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/exists/{meeting_id}")
async def check_custom_summary_exists(meeting_id: str):
    """Check if a meeting has a completed custom template summary"""
    try:
        exists = await db.has_custom_summary(meeting_id)
        return JSONResponse(
            status_code=200,
            content={
                "meeting_id": meeting_id,
                "has_custom_summary": exists
            }
        )
    except Exception as e:
        logger.error(f"Error checking custom template summary: {str(e)}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


# Meeting Notes endpoints

@router.post("/notes/{meeting_id}")
async def save_notes(meeting_id: str, request: dict):
    """Save markdown notes for a meeting"""
    try:
        notes = request.get("notes", "")
        result = await db.save_notes(meeting_id, notes)
        return JSONResponse(status_code=200, content=result)
    except Exception as e:
        logger.error(f"Error saving notes: {str(e)}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/notes/{meeting_id}")
async def get_notes(meeting_id: str):
    """Get markdown notes for a meeting"""
    try:
        result = await db.get_notes(meeting_id)
        if not result:
            return JSONResponse(
                status_code=200,
                content={"meeting_id": meeting_id, "notes": "", "created_at": None, "updated_at": None}
            )
        return JSONResponse(status_code=200, content=result)
    except Exception as e:
        logger.error(f"Error getting notes: {str(e)}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))
