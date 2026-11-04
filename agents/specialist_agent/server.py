"""FastAPI server factory for Specialist Agent B in Project 2."""

import uvicorn
from fastapi import FastAPI

from agents.shared.config import settings
from agents.shared.utils import create_agent_server_app
from agents.specialist_agent.agent import (
    SPECIALIST_AGENT_NAME,
    SPECIALIST_DESCRIPTION,
    root_agent,
)
from agents.specialist_agent.agent import (
    app as adk_app,
)

SPECIALIST_SERVER_TITLE = "Specialist Agent B (Project 2)"


def create_app() -> FastAPI:
    """Create the FastAPI application for Specialist Agent B."""
    return create_agent_server_app(
        service_name=SPECIALIST_AGENT_NAME,
        title=SPECIALIST_SERVER_TITLE,
        description=SPECIALIST_DESCRIPTION,
        root_agent=root_agent,
        adk_app=adk_app,
    )


app = create_app()


def main() -> None:
    """Run the Specialist Agent B FastAPI server."""
    uvicorn.run(
        app,
        host=settings.host,
        port=settings.port,
        log_level="info",
    )


if __name__ == "__main__":
    main()
