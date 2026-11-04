"""Unit tests for Coordinator Agent A, A2A sub-agent wiring, and FastAPI server."""

from fastapi.testclient import TestClient
from google.adk.agents.remote_a2a_agent import RemoteA2aAgent

from agents.coordinator_agent.agent import (
    COORDINATOR_AGENT_NAME,
    COORDINATOR_APP_NAME,
    root_agent,
    specialist_sub_agent,
)
from agents.coordinator_agent.agent import (
    app as adk_app,
)
from agents.coordinator_agent.server import create_app


def test_coordinator_agent_and_sub_agent_wiring() -> None:
    """Verify Coordinator Agent A wires Specialist Agent B as a RemoteA2aAgent."""
    assert root_agent.name == COORDINATOR_AGENT_NAME
    assert adk_app.name == COORDINATOR_APP_NAME
    assert adk_app.root_agent is root_agent
    assert isinstance(specialist_sub_agent, RemoteA2aAgent)
    assert specialist_sub_agent in root_agent.sub_agents


def test_coordinator_server_health_and_a2a_card() -> None:
    """Verify Coordinator Agent A FastAPI server exposes /health and A2A AgentCard."""
    fastapi_app = create_app()
    with TestClient(fastapi_app) as client:
        health_resp = client.get("/health")
        assert health_resp.status_code == 200
        assert health_resp.json()["status"] == "ok"
        assert health_resp.json()["service"] == COORDINATOR_AGENT_NAME

        card_resp = client.get("/a2a/app/.well-known/agent-card.json")
        assert card_resp.status_code == 200
        card_data = card_resp.json()
        assert card_data["name"] == COORDINATOR_AGENT_NAME
