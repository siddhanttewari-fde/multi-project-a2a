"""FastAPI server factory for Coordinator Agent A in Project 1."""

import uvicorn
from fastapi import FastAPI

from agents.coordinator_agent.agent import (
    COORDINATOR_AGENT_NAME,
    COORDINATOR_DESCRIPTION,
    root_agent,
)
from agents.coordinator_agent.agent import (
    app as adk_app,
)
from agents.shared.config import settings
from agents.shared.utils import create_agent_server_app

COORDINATOR_SERVER_TITLE = "Coordinator Agent A (Project 1)"


def create_app() -> FastAPI:
    """Create the FastAPI application for Coordinator Agent A."""
    return create_agent_server_app(
        service_name=COORDINATOR_AGENT_NAME,
        title=COORDINATOR_SERVER_TITLE,
        description=COORDINATOR_DESCRIPTION,
        root_agent=root_agent,
        adk_app=adk_app,
    )


app = create_app()


def main() -> None:
    """Run the Coordinator Agent A FastAPI server."""
    uvicorn.run(
        app,
        host=settings.host,
        port=settings.port,
        log_level="info",
    )


if __name__ == "__main__":
    main()
