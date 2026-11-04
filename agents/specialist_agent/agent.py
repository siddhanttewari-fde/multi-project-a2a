"""Specialist Agent B hosted in Project 2 for cross-project A2A ticket lookups."""

from google.adk.agents import Agent
from google.adk.apps import App

from agents.shared.config import settings

SPECIALIST_AGENT_NAME = "specialist_agent_b"
SPECIALIST_APP_NAME = "specialist_agent"
SPECIALIST_DESCRIPTION = (
    "Specialist agent hosted in Project 2 that retrieves enterprise governance "
    "ticket statuses over the Agent-to-Agent (A2A) protocol."
)
SPECIALIST_INSTRUCTION = (
    "You are Specialist Agent B running inside Project 2 on Vertex AI Agent Runtime.\n"
    "When a caller or peer agent asks for the status of a governance ticket:\n"
    "1. Always call the `get_project_b_ticket_status` tool with the `ticket_id`.\n"
    "2. Return the exact ticket_id, status, handler, and project_role from the tool."
)


def get_project_b_ticket_status(ticket_id: str) -> dict[str, str]:
    """Retrieve the deterministic governance approval status for a ticket in Project 2.

    Args:
        ticket_id: The identifier of the ticket to look up (for example, 'TKT-101').

    Returns:
        A dictionary containing the normalized ticket_id, status, handler, and role.
    """
    normalized_id = ticket_id.strip().upper() or "UNKNOWN"
    return {
        "ticket_id": normalized_id,
        "status": "APPROVED_IN_PROJECT_B",
        "handler": SPECIALIST_AGENT_NAME,
        "project_role": "Project 2 Specialist Host",
    }


root_agent = Agent(
    name=SPECIALIST_AGENT_NAME,
    model=settings.gemini_model,
    description=SPECIALIST_DESCRIPTION,
    instruction=SPECIALIST_INSTRUCTION,
    tools=[get_project_b_ticket_status],
)

app = App(
    name=SPECIALIST_APP_NAME,
    root_agent=root_agent,
)
