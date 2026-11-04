"""Unit tests for centralized settings and shared A2A/SPIFFE utilities."""

from unittest.mock import MagicMock, patch

import httpx
from google.adk.agents.remote_a2a_agent import RemoteA2aAgent

from agents.shared.config import Settings, settings
from agents.shared.utils import (
    GoogleAdcBearerAuth,
    build_health_response,
    create_authenticated_httpx_client,
    get_allow_origins,
    is_telemetry_enabled,
    resolve_app_url,
    resolve_remote_a2a_agent,
)


def test_settings_defaults() -> None:
    """Verify centralized Settings defaults."""
    custom_settings = Settings(_env_file=None)
    assert custom_settings.port == 8080
    assert custom_settings.gemini_model == "gemini-2.5-flash"
    assert custom_settings.remote_agent_b_id == "agents/specialist-agent-b"
    assert custom_settings.a2a_rpc_path == "/a2a/app"


def test_build_health_response() -> None:
    """Verify deterministic health check payload structure."""
    payload = build_health_response("specialist_agent_b")
    assert payload == {
        "status": "ok",
        "service": "specialist_agent_b",
        "version": settings.app_version,
        "region": settings.region,
    }


def test_get_allow_origins(monkeypatch: MagicMock) -> None:
    """Verify comma-separated CORS origin parsing."""
    monkeypatch.setattr(settings, "allow_origins_raw", "")
    assert get_allow_origins() is None

    monkeypatch.setattr(
        settings,
        "allow_origins_raw",
        "https://console.cloud.google.com, https://vertexai.google.com ",
    )
    assert get_allow_origins() == [
        "https://console.cloud.google.com",
        "https://vertexai.google.com",
    ]


def test_is_telemetry_enabled(monkeypatch: MagicMock) -> None:
    """Verify telemetry boolean flag parsing."""
    monkeypatch.setattr(settings, "google_cloud_agent_engine_enable_telemetry", "true")
    assert is_telemetry_enabled() is True

    monkeypatch.setattr(settings, "google_cloud_agent_engine_enable_telemetry", "false")
    assert is_telemetry_enabled() is False


def test_resolve_app_url_precedence(monkeypatch: MagicMock) -> None:
    """Verify URL resolution order from explicit override to Reasoning Engine URL."""
    assert resolve_app_url("https://example.com/api/") == "https://example.com/api"

    monkeypatch.setattr(settings, "app_url", "https://custom.internal/app/")
    assert resolve_app_url() == "https://custom.internal/app"

    monkeypatch.setattr(settings, "app_url", "")
    monkeypatch.setattr(settings, "google_cloud_project", "capstonev2-512420")
    monkeypatch.setattr(settings, "google_cloud_agent_engine_location", "us-central1")
    monkeypatch.setattr(settings, "google_cloud_agent_engine_id", "987654321")
    assert resolve_app_url() == (
        "https://us-central1-aiplatform.googleapis.com/v1beta1"
        "/projects/capstonev2-512420/locations/us-central1/reasoningEngines/987654321/api"
    )


def test_google_adc_bearer_auth_injects_spiffe_token() -> None:
    """Verify GoogleAdcBearerAuth refreshes credentials and attaches Bearer header."""
    mock_creds = MagicMock()
    mock_creds.valid = False
    mock_creds.token = "spiffe-svid-oauth-token-123"

    with patch(
        "agents.shared.utils.google.auth.default",
        return_value=(mock_creds, "argolis-training-project"),
    ) as mock_default:
        auth = GoogleAdcBearerAuth()
        request = httpx.Request(
            "POST", "https://us-central1-aiplatform.googleapis.com/a2a"
        )
        flow = auth.auth_flow(request)
        authed_request = next(flow)

        mock_default.assert_called_once()
        mock_creds.refresh.assert_called_once()
        assert (
            authed_request.headers["Authorization"]
            == "Bearer spiffe-svid-oauth-token-123"
        )


def test_resolve_remote_a2a_agent_via_registry(
    monkeypatch: MagicMock,
) -> None:
    """Verify resolve_remote_a2a_agent uses AgentRegistry when configured."""
    monkeypatch.setattr(settings, "gateway_project_id", "")
    placeholder_agent = resolve_remote_a2a_agent()
    assert isinstance(placeholder_agent, RemoteA2aAgent)
    assert placeholder_agent.name == "specialist_agent_b"

    monkeypatch.setattr(settings, "gateway_project_id", "explore-sobi")
    monkeypatch.setattr(settings, "region", "us-central1")
    monkeypatch.setattr(settings, "remote_agent_b_id", "agents/specialist-agent-b")

    sentinel_agent = MagicMock(spec=RemoteA2aAgent)
    with patch("agents.shared.utils.AgentRegistry") as mock_registry_cls:
        mock_registry_instance = mock_registry_cls.return_value
        mock_registry_instance.get_remote_a2a_agent.return_value = sentinel_agent

        resolved = resolve_remote_a2a_agent()
        assert resolved is sentinel_agent
        mock_registry_cls.assert_called_once_with(
            project_id="explore-sobi",
            location="us-central1",
        )
        call_kwargs = mock_registry_instance.get_remote_a2a_agent.call_args.kwargs
        assert call_kwargs["agent_name"] == "agents/specialist-agent-b"
        assert isinstance(call_kwargs["httpx_client"], httpx.AsyncClient)


def test_create_authenticated_httpx_client() -> None:
    """Verify authenticated httpx.AsyncClient uses GoogleAdcBearerAuth."""
    client = create_authenticated_httpx_client()
    assert isinstance(client, httpx.AsyncClient)
    assert isinstance(client.auth, GoogleAdcBearerAuth)
