"""Unit tests for Specialist Agent B tool, ADK agent definition, and FastAPI server."""

from fastapi.testclient import TestClient

from agents.specialist_agent.agent import (
    SPECIALIST_AGENT_NAME,
    SPECIALIST_APP_NAME,
    get_project_b_ticket_status,
    root_agent,
)
from agents.specialist_agent.agent import (
    app as adk_app,
)
from agents.specialist_agent.server import create_app


def test_get_project_b_ticket_status_normalizes_ticket_id() -> None:
    """Verify deterministic ticket status payload from Project 2 specialist tool."""
    result = get_project_b_ticket_status("  tkt-101 ")
    assert result == {
        "ticket_id": "TKT-101",
        "status": "APPROVED_IN_PROJECT_B",
        "handler": "specialist_agent_b",
        "project_role": "Project 2 Specialist Host",
    }


def test_get_project_b_ticket_status_handles_empty_input() -> None:
    """Verify fallback ticket_id when empty string is supplied."""
    result = get_project_b_ticket_status("   ")
    assert result["ticket_id"] == "UNKNOWN"
    assert result["status"] == "APPROVED_IN_PROJECT_B"


def test_specialist_agent_and_app_configuration() -> None:
    """Verify Specialist Agent B ADK Agent and App attributes."""
    assert root_agent.name == SPECIALIST_AGENT_NAME
    assert adk_app.name == SPECIALIST_APP_NAME
    assert adk_app.root_agent is root_agent
    assert get_project_b_ticket_status in root_agent.tools


def test_specialist_server_health_and_a2a_card() -> None:
    """Verify Specialist Agent B FastAPI server exposes /health and A2A AgentCard."""
    fastapi_app = create_app()
    with TestClient(fastapi_app) as client:
        health_resp = client.get("/health")
        assert health_resp.status_code == 200
        assert health_resp.json()["status"] == "ok"
        assert health_resp.json()["service"] == SPECIALIST_AGENT_NAME

        card_resp = client.get("/a2a/app/.well-known/agent-card.json")
        assert card_resp.status_code == 200
        card_data = card_resp.json()
        assert card_data["name"] == SPECIALIST_AGENT_NAME

        invalid_re_resp = client.post(
            "/api/reasoning_engine",
            json={"class_method": "non_existent_method", "input": {}},
        )
        assert invalid_re_resp.status_code == 404
