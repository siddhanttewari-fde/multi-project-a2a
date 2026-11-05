"""Unit tests for Phase D cross-project A2A discovery and SPIFFE auth flow."""

from unittest.mock import MagicMock, patch

import httpx
import pytest
from a2a.types import AgentCard, AgentInterface

from agents.shared.utils import (
    GoogleAdcBearerAuth,
    RegistryRemoteA2aAgent,
    _default_agent_capabilities,
    create_authenticated_httpx_client,
)


@pytest.mark.asyncio
async def test_registry_remote_a2a_agent_lazy_resolution() -> None:
    """Verify RegistryRemoteA2aAgent resolves its card from AgentRegistry on run."""
    httpx_client = create_authenticated_httpx_client()
    lazy_agent = RegistryRemoteA2aAgent(
        name="specialist_agent_b",
        description="Deferred specialist agent",
        gateway_project_id="explore-sobi",
        region="us-central1",
        remote_agent_id="agents/specialist-agent-b",
        httpx_client=httpx_client,
    )
    assert lazy_agent._registry_resolved is False

    resolved_card = AgentCard(
        name="specialist_agent_b",
        description="Resolved from Project 3 Agent Registry",
        version="0.1.0",
        supported_interfaces=[
            AgentInterface(
                url="https://us-central1-aiplatform.googleapis.com/reasoningEngines/v1/projects/758855451259/locations/us-central1/reasoningEngines/111/api/a2a/app",
                protocol_binding="JSONRPC",
                protocol_version="1.0",
            ),
        ],
        capabilities=_default_agent_capabilities(),
        default_input_modes=["text/plain"],
        default_output_modes=["text/plain"],
        skills=[],
    )
    mock_remote_agent = MagicMock()
    mock_remote_agent._agent_card = resolved_card

    with patch("agents.shared.utils.AgentRegistry") as mock_registry_cls:
        mock_registry_instance = mock_registry_cls.return_value
        mock_registry_instance.get_remote_a2a_agent.return_value = mock_remote_agent

        await lazy_agent._ensure_resolved(None)

        assert lazy_agent._registry_resolved is True
        assert lazy_agent._agent_card == resolved_card
        mock_registry_cls.assert_called_once_with(
            project_id="explore-sobi",
            location="us-central1",
        )
        mock_registry_instance.get_remote_a2a_agent.assert_called_once_with(
            agent_name="agents/specialist-agent-b",
            httpx_client=httpx_client,
        )

    await httpx_client.aclose()


def test_spiffe_bearer_token_reuse_when_valid() -> None:
    """Verify GoogleAdcBearerAuth reuses a valid token without redundant refresh."""
    mock_creds = MagicMock()
    mock_creds.valid = True
    mock_creds.token = "cached-spiffe-token-xyz"

    with patch(
        "agents.shared.utils.google.auth.default",
        return_value=(mock_creds, "argolis-training-project"),
    ) as mock_default:
        auth = GoogleAdcBearerAuth()
        req1 = httpx.Request(
            "GET", "https://agentregistry.googleapis.com/v1alpha/agents"
        )
        authed1 = next(auth.auth_flow(req1))
        req2 = httpx.Request(
            "POST", "https://us-central1-aiplatform.googleapis.com/a2a"
        )
        authed2 = next(auth.auth_flow(req2))

        mock_default.assert_called_once()
        mock_creds.refresh.assert_not_called()
        assert authed1.headers["Authorization"] == "Bearer cached-spiffe-token-xyz"
        assert authed2.headers["Authorization"] == "Bearer cached-spiffe-token-xyz"
