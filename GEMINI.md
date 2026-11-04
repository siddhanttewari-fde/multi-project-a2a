@[.specify/memory/constitution.md](.specify/memory/constitution.md)

## Implementation Workflow & Phased Plan
- **Active Plan**: Always consult [`.specify/memory/plan.md`](.specify/memory/plan.md) when planning, implementing, or verifying any phase of the project.
- **Architecture Decision Record**: Consult [`docs/architecture-and-security-rationale.md`](docs/architecture-and-security-rationale.md) and [`docs/security-threats-and-mitigations.md`](docs/security-threats-and-mitigations.md) for the 3-project Single Central Egress Gateway topology and 4-plane anti-bypass controls.
- **Python Coding Standards**: Strictly enforce [`_agents/skills/python-coding-standards/SKILL.md`](_agents/skills/python-coding-standards/SKILL.md) whenever writing, editing, or reviewing Python, FastAPI, or Google ADK code.
- **Verification Loop**: Before completing any phase or committing code, run `uv run ruff check .`, `uv run ruff format --check .`, and execute the phase's CLI/unit/Cloud Console verification steps specified in [`.specify/memory/plan.md`](.specify/memory/plan.md).
