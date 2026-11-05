"""Shared utilities for A2A routing, SPIFFE authentication, and FastAPI app creation."""

import contextlib
import functools
import inspect
import json
import logging
from collections.abc import AsyncIterator, Callable
from typing import Any

import google.auth
import httpx
from a2a.server.request_handlers import DefaultRequestHandler
from a2a.server.routes import (
    add_a2a_routes_to_fastapi,
    create_agent_card_routes,
    create_jsonrpc_routes,
)
from a2a.server.tasks import InMemoryTaskStore
from a2a.types import AgentCapabilities, AgentCard, AgentExtension, AgentInterface
from a2a.utils.constants import AGENT_CARD_WELL_KNOWN_PATH
from fastapi import FastAPI, HTTPException, Request, encoders, responses
from google.adk.a2a.executor.a2a_agent_executor import A2aAgentExecutor
from google.adk.a2a.utils.agent_card_builder import AgentCardBuilder
from google.adk.agents import BaseAgent
from google.adk.agents.remote_a2a_agent import RemoteA2aAgent
from google.adk.apps import App
from google.adk.artifacts import InMemoryArtifactService
from google.adk.cli.fast_api import get_fast_api_app
from google.adk.integrations.agent_registry import AgentRegistry
from google.adk.runners import Runner
from google.adk.sessions import InMemorySessionService
from google.auth.transport.requests import Request as GoogleAuthRequest
from starlette.concurrency import iterate_in_threadpool, run_in_threadpool
from vertexai.agent_engines.templates.adk import AdkApp

from agents.shared.config import (
    ADK_AGENT_EXECUTOR_EXTENSION_URI,
    AGENTS_ROOT_DIR,
    CLOUD_PLATFORM_SCOPE,
    settings,
)


class GoogleAdcBearerAuth(httpx.Auth):
    """Attaches a SPIFFE / Application Default Credentials OAuth 2.0 Bearer token."""

    def __init__(self) -> None:
        self._credentials: Any = None

    def _ensure_valid_token(self) -> str:
        if self._credentials is None:
            self._credentials, _ = google.auth.default(scopes=[CLOUD_PLATFORM_SCOPE])
        if not self._credentials.valid:
            self._credentials.refresh(GoogleAuthRequest())
        return str(self._credentials.token)

    def auth_flow(self, request: httpx.Request) -> Any:
        token = self._ensure_valid_token()
        request.headers["Authorization"] = f"Bearer {token}"
        yield request


def create_authenticated_httpx_client() -> httpx.AsyncClient:
    """Create an async HTTP client authenticated with the workload's SPIFFE identity."""
    return httpx.AsyncClient(
        auth=GoogleAdcBearerAuth(),
        timeout=httpx.Timeout(settings.http_timeout_seconds),
    )


def build_health_response(service_name: str) -> dict[str, str]:
    """Build a deterministic health check payload for an agent service."""
    return {
        "status": "ok",
        "service": service_name,
        "version": settings.app_version,
        "region": settings.region,
    }


def get_allow_origins() -> list[str] | None:
    """Parse comma-separated CORS origins from centralized settings."""
    if not settings.allow_origins_raw.strip():
        return None
    return [
        origin.strip()
        for origin in settings.allow_origins_raw.split(",")
        if origin.strip()
    ]


def is_telemetry_enabled() -> bool:
    """Return True when Cloud Trace / OpenTelemetry export is enabled."""
    return settings.google_cloud_agent_engine_enable_telemetry.lower() in (
        "true",
        "1",
        "yes",
    )


def resolve_app_url(explicit_url: str | None = None) -> str:
    """Resolve the public base URL advertised inside the agent's A2A AgentCard."""
    if explicit_url:
        return explicit_url.rstrip("/")
    if settings.app_url:
        return settings.app_url.rstrip("/")
    if (
        settings.google_cloud_agent_engine_id
        and settings.google_cloud_project
        and settings.google_cloud_agent_engine_location
    ):
        loc = settings.google_cloud_agent_engine_location
        proj = settings.google_cloud_project
        engine_id = settings.google_cloud_agent_engine_id
        return (
            f"https://{loc}-aiplatform.googleapis.com/reasoningEngines/v1"
            f"/projects/{proj}/locations/{loc}/reasoningEngines/{engine_id}/api"
        )
    return f"http://{settings.host}:{settings.port}"


def _build_placeholder_agent_card(
    agent_name: str,
    description: str,
) -> AgentCard:
    """Build an in-memory placeholder AgentCard when GATEWAY_PROJECT_ID is unset."""
    placeholder_url = f"http://localhost:{settings.port}{settings.a2a_rpc_path}"
    return AgentCard(
        name=agent_name,
        description=description,
        version=settings.app_version,
        supported_interfaces=[
            AgentInterface(
                url=placeholder_url,
                protocol_binding="JSONRPC",
                protocol_version="1.0",
            ),
        ],
        capabilities=_default_agent_capabilities(),
        default_input_modes=["text/plain"],
        default_output_modes=["text/plain"],
        skills=[],
    )


logger = logging.getLogger(__name__)


def _resolve_registry_agent_name(
    registry: AgentRegistry,
    logical_agent_id: str,
) -> str:
    """Resolve a logical agent ID to its Agent Registry resource name."""
    short_id = logical_agent_id.rsplit("/", maxsplit=1)[-1]
    list_fn = getattr(registry, "list_agents", None)
    if callable(list_fn):
        try:
            payload = list_fn()
            agents = payload.get("agents", []) if isinstance(payload, dict) else []
            for item in agents:
                name = str(item.get("name", ""))
                agent_id_urn = str(item.get("agentId", ""))
                display_name = str(item.get("displayName", ""))
                if (
                    name.endswith(f"/{short_id}")
                    or agent_id_urn.endswith(f":{short_id}")
                    or display_name == short_id
                ):
                    return name
        except Exception as exc:
            logger.debug("AgentRegistry list_agents fallback for %s: %s", short_id, exc)
    return logical_agent_id


class RegistryRemoteA2aAgent(RemoteA2aAgent):
    """RemoteA2aAgent that lazily resolves its card from Project 3 AgentRegistry."""

    def __init__(
        self,
        *,
        name: str,
        description: str,
        gateway_project_id: str,
        region: str,
        remote_agent_id: str,
        httpx_client: httpx.AsyncClient,
    ) -> None:
        super().__init__(
            name=name,
            description=description,
            agent_card=_build_placeholder_agent_card(name, description),
            httpx_client=httpx_client,
        )
        self._gateway_project_id = gateway_project_id
        self._region = region
        self._remote_agent_id = remote_agent_id
        self._registry_resolved = False

    async def _ensure_resolved(self, ctx: Any = None) -> Any:
        if not self._registry_resolved and self._gateway_project_id:
            registry = AgentRegistry(
                project_id=self._gateway_project_id,
                location=self._region,
            )
            resolved_name = await run_in_threadpool(
                _resolve_registry_agent_name,
                registry,
                self._remote_agent_id,
            )
            resolved_agent = await run_in_threadpool(
                registry.get_remote_a2a_agent,
                agent_name=resolved_name,
                httpx_client=self._httpx_client,
            )
            if resolved_agent._agent_card is not None:
                self._agent_card = resolved_agent._agent_card
            self._registry_resolved = True
        return await super()._ensure_resolved(ctx)


def resolve_remote_a2a_agent(
    agent_name: str = "specialist_agent_b",
    description: str = (
        "Specialist agent hosted in Project 2 that retrieves enterprise "
        "ticket statuses over A2A."
    ),
) -> RemoteA2aAgent:
    """Resolve Specialist Agent B exclusively via Project 3's Central Agent Registry."""
    httpx_client = create_authenticated_httpx_client()
    if settings.gateway_project_id:
        try:
            registry = AgentRegistry(
                project_id=settings.gateway_project_id,
                location=settings.region,
            )
            resolved_name = _resolve_registry_agent_name(
                registry,
                settings.remote_agent_b_id,
            )
            return registry.get_remote_a2a_agent(
                agent_name=resolved_name,
                httpx_client=httpx_client,
            )
        except Exception as exc:
            logger.warning(
                "Deferred AgentRegistry lookup for %s until first invocation: %s",
                settings.remote_agent_b_id,
                exc,
            )
            return RegistryRemoteA2aAgent(
                name=agent_name,
                description=description,
                gateway_project_id=settings.gateway_project_id,
                region=settings.region,
                remote_agent_id=settings.remote_agent_b_id,
                httpx_client=httpx_client,
            )

    return RemoteA2aAgent(
        name=agent_name,
        description=description,
        agent_card=_build_placeholder_agent_card(agent_name, description),
        httpx_client=httpx_client,
    )


@functools.cache
def get_shared_session_service() -> InMemorySessionService:
    """Return a singleton InMemorySessionService shared across all routes."""
    return InMemorySessionService()


@functools.cache
def get_shared_artifact_service() -> InMemoryArtifactService:
    """Return a singleton InMemoryArtifactService shared across all routes."""
    return InMemoryArtifactService()


def _no_op_instrumentor_builder(project_id: str) -> None:
    """No-op instrumentor builder for AdkApp."""
    del project_id
    return None


async def _add_v0_3_compat_interface(card: AgentCard) -> AgentCard:
    """Add v0.3 JSON-RPC interface compatibility entry to the generated AgentCard."""
    if card.supported_interfaces:
        card.supported_interfaces.append(
            AgentInterface(
                protocol_binding="JSONRPC",
                protocol_version="0.3",
                url=card.supported_interfaces[0].url,
            )
        )
    return card


def _default_agent_capabilities() -> AgentCapabilities:
    """Return default A2A streaming capabilities."""
    return AgentCapabilities(
        streaming=True,
        extensions=[
            AgentExtension(
                uri=ADK_AGENT_EXECUTOR_EXTENSION_URI,
                description="Ability to use the ADK A2A agent executor implementation",
            ),
        ],
    )


async def attach_a2a_routes(
    app: FastAPI,
    *,
    agent: BaseAgent,
    runner: Runner,
    rpc_path: str | None = None,
    app_url: str | None = None,
) -> None:
    """Mount A2A AgentCard and JSON-RPC 2.0 routes onto the FastAPI application."""
    resolved_rpc_path = rpc_path or settings.a2a_rpc_path
    resolved_app_url = resolve_app_url(app_url)
    capabilities = _default_agent_capabilities()

    agent_card = await AgentCardBuilder(
        agent=agent,
        capabilities=capabilities,
        rpc_url=f"{resolved_app_url}{resolved_rpc_path}",
        agent_version=settings.app_version,
    ).build()

    request_handler = DefaultRequestHandler(
        agent_executor=A2aAgentExecutor(runner=runner, force_new_version=True),
        task_store=InMemoryTaskStore(),
        agent_card=agent_card,
    )

    add_a2a_routes_to_fastapi(
        app,
        agent_card_routes=create_agent_card_routes(
            agent_card,
            card_modifier=_add_v0_3_compat_interface,
            card_url=f"{resolved_rpc_path}{AGENT_CARD_WELL_KNOWN_PATH}",
        ),
        jsonrpc_routes=create_jsonrpc_routes(
            request_handler,
            rpc_url=resolved_rpc_path,
            enable_v0_3_compat=True,
        ),
    )


def _build_reasoning_engine_bundle(
    adk_app: App,
) -> tuple[AdkApp, frozenset[str], frozenset[str]]:
    """Instantiate and initialize an AdkApp bundle for Reasoning Engine dispatch."""
    runtime = AdkApp(
        app=adk_app,
        session_service_builder=get_shared_session_service,
        artifact_service_builder=get_shared_artifact_service,
        instrumentor_builder=_no_op_instrumentor_builder,
    )
    runtime.set_up()
    operations = runtime.register_operations()
    streaming_methods = frozenset(
        set(operations.get("stream", [])) | set(operations.get("async_stream", []))
    )
    sync_methods = frozenset(
        set(operations.get("", [])) | set(operations.get("async", []))
    )
    return runtime, streaming_methods, sync_methods


def _resolve_reasoning_engine_method(
    app: FastAPI,
    class_method: str,
    *,
    streaming: bool,
) -> Callable[..., Any]:
    """Resolve and validate a Reasoning Engine method on the app's AdkApp bundle."""
    if getattr(app.state, "reasoning_engine_bundle", None) is None:
        app.state.reasoning_engine_bundle = _build_reasoning_engine_bundle(
            app.state.adk_app
        )
    runtime, streaming_methods, sync_methods = app.state.reasoning_engine_bundle
    allowed = streaming_methods if streaming else sync_methods
    if class_method not in allowed:
        raise HTTPException(
            status_code=404,
            detail=f"Unsupported reasoning_engine method: {class_method!r}",
        )
    return getattr(runtime, class_method)


async def _stream_reasoning_engine_events(stream: Any) -> AsyncIterator[str]:
    """Yield newline-delimited JSON events from a Reasoning Engine stream."""
    if hasattr(stream, "__aiter__"):
        async for event in stream:
            yield json.dumps(encoders.jsonable_encoder(event)) + "\n"
    else:
        async for event in iterate_in_threadpool(stream):
            yield json.dumps(encoders.jsonable_encoder(event)) + "\n"


async def handle_reasoning_engine_stream_query(
    request: Request,
) -> responses.StreamingResponse:
    """Handle POST /api/stream_reasoning_engine requests from Vertex AI Playground."""
    body = await request.json()
    method = _resolve_reasoning_engine_method(
        request.app,
        body["class_method"],
        streaming=True,
    )
    kwargs = body.get("input") or {}
    stream = (
        await method(**kwargs)
        if inspect.iscoroutinefunction(method)
        else method(**kwargs)
    )
    return responses.StreamingResponse(
        content=_stream_reasoning_engine_events(stream),
        media_type="application/json",
    )


async def handle_reasoning_engine_query(request: Request) -> responses.JSONResponse:
    """Handle POST /api/reasoning_engine synchronous requests."""
    body = await request.json()
    method = _resolve_reasoning_engine_method(
        request.app,
        body["class_method"],
        streaming=False,
    )
    kwargs = body.get("input") or {}
    if inspect.iscoroutinefunction(method):
        output = await method(**kwargs)
    else:
        output = await run_in_threadpool(method, **kwargs)
    return responses.JSONResponse(content=encoders.jsonable_encoder({"output": output}))


async def handle_health_check(request: Request) -> dict[str, str]:
    """Handle GET /health requests."""
    service_name = getattr(request.app.state, "service_name", settings.app_name)
    return build_health_response(service_name)


def attach_reasoning_engine_routes(app: FastAPI) -> None:
    """Register canonical Reasoning Engine HTTP adapter routes on the FastAPI app."""
    app.add_api_route(
        "/api/stream_reasoning_engine",
        handle_reasoning_engine_stream_query,
        methods=["POST"],
    )
    app.add_api_route(
        "/api/reasoning_engine",
        handle_reasoning_engine_query,
        methods=["POST"],
    )


@contextlib.asynccontextmanager
async def agent_app_lifespan(app: FastAPI) -> AsyncIterator[None]:
    """Initialize ADK Runner and mount A2A routes during FastAPI startup."""
    adk_app: App = app.state.adk_app
    root_agent: BaseAgent = app.state.root_agent
    runner = Runner(
        app=adk_app,
        session_service=get_shared_session_service(),
        artifact_service=get_shared_artifact_service(),
        auto_create_session=True,
    )
    app.state.runner = runner
    app.state.agent_app_name = adk_app.name
    await attach_a2a_routes(
        app,
        agent=root_agent,
        runner=runner,
        rpc_path=settings.a2a_rpc_path,
    )
    yield


def create_agent_server_app(
    *,
    service_name: str,
    title: str,
    description: str,
    root_agent: BaseAgent,
    adk_app: App,
    agents_dir: str = AGENTS_ROOT_DIR,
) -> FastAPI:
    """Create a FastAPI server exposing ADK, A2A, Reasoning Engine, and /health."""
    app: FastAPI = get_fast_api_app(
        agents_dir=agents_dir,
        web=False,
        allow_origins=get_allow_origins(),
        otel_to_cloud=is_telemetry_enabled(),
        lifespan=agent_app_lifespan,
    )
    app.title = title
    app.description = description
    app.state.service_name = service_name
    app.state.root_agent = root_agent
    app.state.adk_app = adk_app
    app.state.reasoning_engine_bundle = None

    app.router.routes = [
        route
        for route in app.router.routes
        if getattr(route, "path", None) != "/health"
    ]
    app.add_api_route("/health", handle_health_check, methods=["GET"])
    attach_reasoning_engine_routes(app)
    return app
