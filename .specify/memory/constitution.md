# Project Constitution: Multi-Project Enterprise A2A Governance on Argolis

This constitution defines the non-negotiable architectural, security, Infrastructure-as-Code (IaC), and Python coding invariants for this repository. All plans, Terraform modules, scripts, and agent implementations MUST comply with these principles.

---

## 1. Architectural Invariants (Simplified 3-Project Topology)

1. **Strict 3-Project Separation**:
   * **Project 1 (`AGENT_A_PROJECT_ID`)**: Hosts the Coordinator ADK Agent (`coordinator-agent-a`) on Vertex AI Agent Runtime (`identity_type = "AGENT_IDENTITY"`).
   * **Project 2 (`AGENT_B_PROJECT_ID`)**: Hosts the Specialist ADK Agent (`specialist-agent-b`) on Vertex AI Agent Runtime (`identity_type = "AGENT_IDENTITY"`), exposing its A2A JSON-RPC interface via `/api/a2a/app`.
   * **Project 3 (`GATEWAY_PROJECT_ID`)**: Hosts the **Single Central Egress Agent Gateway (`central-egress-gw`, `AGENT_TO_ANYWHERE`)**, the **Central Regional Agent Registry**, the **IAP Unified Access Policy (`V2`, `failOpen: false`)**, and the **Custom Organization Policy constraint (`custom.allowlistedEgressAgentGatewaysForAgentEngine`)**.
2. **Single Central Egress Gateway (No Redundant Local Ingress Gateways)**:
   * Both Agent A (Project 1) and Agent B (Project 2) MUST bind their `agent_to_anywhere_config` cross-project to Project 3's `central-egress-gw`.
   * Do not provision redundant `CLIENT_TO_AGENT` Ingress Gateways in Project 1 or Project 2.
3. **Identifier-Based A2A Discovery**:
   * Agent A MUST resolve Agent B dynamically by its logical identifier (`"agents/specialist-agent-b"`) in Project 3's Central Agent Registry using `google.adk.integrations.agent_registry.AgentRegistry.get_remote_a2a_agent()`, rather than hardcoding Project 2's numeric Reasoning Engine URL.
4. **Zero-Trust Anti-Bypass Controls**:
   * **Data Plane**: 100% of outbound traffic from Agent A and Agent B is steered through Project 3's `central-egress-gw` at the Agent Runtime sandbox network layer; both agent Dockerfiles MUST trust `AGENT_GATEWAY_ROOT_CERTIFICATES`.
   * **Control Plane**: Project 1 and Project 2 MUST enforce the `custom.allowlistedEgressAgentGatewaysForAgentEngine` Organization Policy constraint so no `ReasoningEngine` can be created or updated without binding to Project 3's `central-egress-gw`.
   * **Identity Plane**: Agent B MUST grant `roles/agentInvoker` exclusively to Agent A's immutable SPIFFE principal (`principal://agents.global.org-<ORG_ID>.system.id.goog/resources/aiplatform/projects/<PROJ_1_NUM>/locations/<REGION>/reasoningEngines/<ENGINE_A_ID>`).
   * **Perimeter Plane**: All three projects MUST reside inside a single **VPC Service Controls (VPC-SC)** perimeter with `/28` Private Service Connect (PSC) network attachments.

---

## 2. Infrastructure-as-Code (Terraform) & Configuration Invariants

1. **100% Declarative Terraform**:
   * All GCP resources—VPCs, `/28` subnets, PSC network attachments, VPC-SC perimeters, Central Egress Gateway, Agent Registry services, IAP extensions/policies, Custom Organization Policies, Artifact Registries, Vertex AI Reasoning Engines, and cross-project IAM bindings—MUST be provisioned via modular Terraform in `infra/terraform/`.
2. **Zero Hardcoded Environment Values**:
   * Never hardcode GCP Organization IDs, Project IDs, Project Numbers, Regions, or User Emails in Terraform modules, scripts, or Python code.
   * All deployment parameters originate in `config/project_config.env` (templated by `config/project_config.env.example`), which `scripts/bootstrap_tf.sh` uses to generate `infra/terraform/terraform.tfvars` and `infra/terraform/backend.hcl`.

---

## 3. Python, FastAPI & Google ADK Coding Standards

All Python files in `agents/` and `tests/` MUST strictly follow [`_agents/skills/python-coding-standards/SKILL.md`](../../_agents/skills/python-coding-standards/SKILL.md):

1. **Centralized Configuration & Reuse (`agents/shared/`)**:
   * All environment variables and constants MUST be read once in `agents/shared/config.py` (`settings = Settings()`) and imported everywhere else. Never scatter `os.getenv()` calls across modules.
   * Shared helpers (`GoogleAdcBearerAuth`, `create_authenticated_httpx_client()`, `resolve_remote_a2a_agent()`, `build_health_response()`, A2A route attachment helpers) MUST live in `agents/shared/utils.py`.
2. **Symmetrical Agent Package Layout**:
   * Each agent package (`agents/coordinator_agent/`, `agents/specialist_agent/`) contains `agent.py` (ADK `root_agent`, `App`, and domain tools) and `server.py` (FastAPI `create_app()` factory).
3. **Single Canonical Route per Handler**:
   * Never register duplicate route aliases for the same handler function unless required by the Vertex AI Reasoning Engine / A2A platform contract.
4. **`create_app()` Factory Pattern (No Hanging Module-Level Code)**:
   * Keep only imports, constants, `class` definitions, and `def` functions at module scope. Encapsulate FastAPI instantiation, lifespan, and route mounting inside `create_app() -> FastAPI`, with `app = create_app()` at the bottom of `server.py`.
5. **Flat Module-Level Functions (No Nested `def` or `nonlocal`)**:
   * Never define nested functions (`def` or `async def` inside another function) or use `nonlocal`/`global` state. Use `@functools.cache` or `app.state` at top level.
6. **Top-Level Imports Only (`PLC0415`)**:
   * Every `import` and `from ... import ...` statement MUST be at the top of the file (sorted via Ruff `I001`). Never place imports inside functions, `lifespan`, `try/except`, `if TYPE_CHECKING:`, or `if __name__ == "__main__":`.
7. **Native Python 3.12 Typing (`TID251`)**:
   * Never use `from __future__ import annotations`. Use native Python 3.12 runtime type annotations (`dict[str, str]`, `list[str]`, `X | None`) directly.
8. **No Redundant `__all__` & Mandatory Verification Gate**:
   * Omit `__all__` in regular `.py` modules (`config.py`, `utils.py`, `agent.py`, `server.py`).
   * Every code change MUST pass `uv run ruff check .` and `uv run ruff format --check .`.

---

## 4. Phase Completion, Git Commit & PR Approval Gate

1. **Mandatory Commit After Each Phase**:
   * Upon completing any phase in [`.specify/memory/plan.md`](plan.md) and passing all verification gates (`uv run ruff check .`, `uv run ruff format --check .`, and phase-specific CLI/unit tests), all changes for that phase MUST be staged and committed to Git with a descriptive commit message.
2. **Explicit Approval Before Raising a PR**:
   * Immediately after committing a phase's changes, STOP and ask the user for explicit approval to push / raise a Pull Request (PR) for that phase before proceeding.
