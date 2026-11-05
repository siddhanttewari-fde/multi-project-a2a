"""Unit tests for Specialist Agent B tool, ADK agent definition, and FastAPI server."""

import time
from unittest.mock import MagicMock

from fastapi.testclient import TestClient

from agents.shared.config import (
    A2A_HMAC_NONCE_HEADER,
    A2A_HMAC_SIGNATURE_HEADER,
    A2A_HMAC_TIMESTAMP_HEADER,
    settings,
)
from agents.shared.utils import compute_a2a_hmac_signature
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


def test_specialist_server_enforces_a2a_hmac_middleware(
    monkeypatch: MagicMock,
) -> None:
    """Verify Specialist Agent B rejects unsigned or tampered POST /a2a/app calls."""
    monkeypatch.setattr(settings, "a2a_hmac_secret", "shared-gateway-hmac-secret-256")
    fastapi_app = create_app()
    raw_payload = b'{"jsonrpc":"2.0","id":"1","method":"tasks/get","params":{"id":"x"}}'

    with TestClient(fastapi_app) as client:
        # 1. Unsigned direct request is blocked (401 Unauthorized)
        unsigned_resp = client.post(
            "/a2a/app",
            content=raw_payload,
            headers={"Content-Type": "application/json"},
        )
        assert unsigned_resp.status_code == 401
        assert "Missing A2A HMAC signature headers" in unsigned_resp.json()["error"]

        # 2. Tampered signature is blocked (401 Unauthorized)
        now_ts = str(int(time.time()))
        tampered_resp = client.post(
            "/a2a/app",
            content=raw_payload,
            headers={
                "Content-Type": "application/json",
                A2A_HMAC_TIMESTAMP_HEADER: now_ts,
                A2A_HMAC_NONCE_HEADER: "nonce-abc",
                A2A_HMAC_SIGNATURE_HEADER: "0" * 64,
            },
        )
        assert tampered_resp.status_code == 401
        assert "Invalid A2A HMAC signature" in tampered_resp.json()["error"]

        # 3. Valid HMAC-SHA256 signed request passes middleware (200 JSON-RPC response)
        valid_sig = compute_a2a_hmac_signature(
            body=raw_payload,
            secret="shared-gateway-hmac-secret-256",
            timestamp=now_ts,
            nonce="nonce-abc",
        )
        signed_resp = client.post(
            "/a2a/app",
            content=raw_payload,
            headers={
                "Content-Type": "application/json",
                A2A_HMAC_TIMESTAMP_HEADER: now_ts,
                A2A_HMAC_NONCE_HEADER: "nonce-abc",
                A2A_HMAC_SIGNATURE_HEADER: valid_sig,
            },
        )
        assert signed_resp.status_code == 200
        assert "jsonrpc" in signed_resp.json()
