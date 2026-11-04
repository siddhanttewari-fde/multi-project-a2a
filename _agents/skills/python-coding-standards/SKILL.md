---
name: python-coding-standards
description: >-
  Use this skill whenever writing, editing, or reviewing Python, FastAPI, or Google ADK code.
  Enforces reference-code refactoring, code reuse in shared/, single canonical routes, create_app()
  factories (no hanging code), flat module-level functions (no nested defs), top-level imports,
  and native Python 3.12 typing.
---

# Python, FastAPI & ADK Coding Standards

Apply these standards every time you write, refactor, or review `.py` files.

## 0. Reference-Code Transformation Gate (Mandatory Pre-Write Check)
When sourcing implementation logic from `reference/full-codebase` or scaffold templates:
- **Preserve domain & architectural behavior**, but **NEVER copy scaffold/reference anti-patterns verbatim**.
- Before calling `write_file` or `edit_file`, actively refactor the code through all 7 rules below.

---

## 1. Code Reuse & Centralized Configuration (`agents/shared/`)
- **Centralize Constants & Environment Reads (`agents/shared/config.py`)**:
  - Any constant or `os.environ` / `os.getenv` setting used by agents (`PROJECT_ID`, `LOCATION`, `APP_VERSION`, `PORT`, `ENABLE_TELEMETRY`, `A2A_PROTOCOL_VERSION`, `RESEARCH_AGENT_ID`, `REVIEWER_AGENT_ID`, service names, Cloud Logging stream names, model IDs, URLs) MUST be defined once in `agents/shared/config.py` (`settings = Settings()`) and imported everywhere else.
  - Avoid scattering raw `os.getenv(...)` calls with hardcoded fallback defaults across agent modules.
- **Centralize Shared Helpers (`agents/shared/utils.py`)**:
  - Any utility function needed by both `research_agent` and `review_agent` (e.g., `configure_vertex_ai_env()`, `get_allow_origins()`, `configure_cors()`, `emit_cloud_audit_log()`, `build_health_response()`) MUST live in `agents/shared/utils.py`.
- **Symmetrical Agent Package Structure**:
  - `agent.py`: ADK `root_agent`, `App`, and core tool/domain functions.
  - `server.py`: FastAPI HTTP routes and `create_app()` factory that delegate to `agent.py`.

---

## 2. Single Canonical Route per Handler (No Duplicate Route Aliases)
Never register multiple URL paths for the exact same endpoint handler unless required by an external platform contract.
- ❌ **Anti-Pattern**:
  ```python
  fastapi_app.add_api_route(
      "/api/v1/clinical/query", process_clinical_query, methods=["POST"]
  )
  fastapi_app.add_api_route("/api/v1/research", process_clinical_query, methods=["POST"])
  ```
- ✅ **Required Pattern**:
  ```python
  fastapi_app.add_api_route("/api/v1/research", process_clinical_query, methods=["POST"])
  ```

---

## 3. No Hanging Module-Level Code (`create_app()` Factory Pattern)
Never scatter loose imperative statements (`load_dotenv()`, `app = FastAPI(...)`, `app.title = ...`, `attach_routes(app)`, `_registry.register_*`) between `class` and `def` blocks in the middle of a file.
- ❌ **Anti-Pattern**:
  ```python
  load_dotenv()
  app = get_fast_api_app(...)
  attach_reasoning_engine_routes(app)


  class ClinicalQueryRequest(BaseModel): ...
  ```
- ✅ **Required Pattern**:
  Keep only imports, constants, `class` definitions, and `def` functions at module scope. Encapsulate app creation, middleware setup, and route registration inside `create_app() -> FastAPI`, with `app = create_app()` at the bottom of `server.py`.

---

## 4. Flat Module-Level Functions (No Nested `def` or `nonlocal` State)
Never define nested functions (`def` or `async def` inside another `def`) or use `nonlocal` / `global` variables to hold lazy state.
- ❌ **Anti-Pattern**:
  ```python
  def attach_routes(app: FastAPI) -> None:
      runtime = None

      def get_runtime():
          nonlocal runtime
          ...
  ```
- ✅ **Required Pattern**:
  ```python
  @functools.cache
  def _get_runtime_bundle() -> tuple[AdkApp, frozenset[str], frozenset[str]]: ...
  ```
  Keep all helpers, generators, and route handlers at the module top level so each function is flat, readable, and independently unit-testable.

---

## 5. All Imports at Top of File (`PLC0415`)
- Place **every** `import` and `from ... import ...` statement at the top of the file (sorted via Ruff `I001`).
- Never place imports inside functions, `lifespan` blocks, `try/except` blocks, `if TYPE_CHECKING:` blocks, or `if __name__ == "__main__":` blocks.

---

## 6. Native Python 3.12 Typing — No `from __future__ import annotations` (`TID251`)
- Never use `from __future__ import annotations`.
- Use native Python 3.12 runtime type annotations (`list[str]`, `dict[str, Any]`, `X | None`) directly so FastAPI, Pydantic, and Google ADK can inspect runtime type objects without string evaluation.

---

## 7. No Redundant `__all__` & Dead-Code Elimination
- **Omit `__all__` in regular `.py` modules** (`agent.py`, `server.py`, `utils.py`, `config.py`); rely on explicit imports and leading underscores (`_`) for private helpers. Only use `__all__` inside `__init__.py` when re-exporting symbols from submodules.
- **Verification Loop**: Before completing any file edit or phase, run:
  ```bash
  uv run --no-sync ruff check . && uv run --no-sync ruff format --check .
  ```
