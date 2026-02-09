# Custom Templates Module
# Handles custom template summaries separately from the rigid SummaryResponse schema

from .routes import router
from .db import CustomTemplateSummaryDB

__all__ = ['router', 'CustomTemplateSummaryDB']
