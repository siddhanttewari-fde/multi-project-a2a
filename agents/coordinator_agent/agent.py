"""Coordinator Agent A hosted in Project 1 delegating A2A lookups to Agent B."""

from google.adk.agents import Agent
from google.adk.apps import App

from agents.shared.config import settings
from agents.shared.utils import resolve_remote_a2a_agent

COORDINATOR_AGENT_NAME = "coordinator_agent_a"
COORDINATOR_APP_NAME = "coordinator_agent"
COORDINATOR_DESCRIPTION = (
    "Coordinator agent hosted in Project 1 that resolves Specialist Agent B "
    "in Project 3's Central Agent Registry and delegates enterprise ticket "
    "status lookups across projects over A2A."
)
COORDINATOR_INSTRUCTION = (
    "You are Coordinator Agent A running inside Project 1 on Vertex AI Agent Runtime.\n"
    "You coordinate enterprise governance workflows across GCP projects.\n"
    "When a user asks for the status of a ticket or asks you to consult Project B:\n"
    "1. Delegate the request to your remote A2A sub-agent (`specialist_agent_b`).\n"
    "2. Summarize the specialist agent's response with ticket ID, status, and handler."
)

specialist_sub_agent = resolve_remote_a2a_agent()

root_agent = Agent(
    name=COORDINATOR_AGENT_NAME,
    model=settings.gemini_model,
    description=COORDINATOR_DESCRIPTION,
    instruction=COORDINATOR_INSTRUCTION,
    sub_agents=[specialist_sub_agent],
)

app = App(
    name=COORDINATOR_APP_NAME,
    root_agent=root_agent,
)
