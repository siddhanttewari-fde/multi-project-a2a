# Multi-Project Enterprise A2A Governance on Google Cloud

A zero-trust, 100% Terraform-managed **3-Project Enterprise Agent-to-Agent (A2A) Governance** reference architecture built with **Google Agent Development Kit (`google-adk`)**, **Vertex AI Agent Runtime (`AGENT_IDENTITY` SPIFFE identities)**, **Central Egress Agent Gateway (`AGENT_TO_ANYWHERE`)**, **Central Agent Registry**, **IAP Unified Access Policy (`V2`, `failOpen: false`)**, **Custom Organization Policy constraints**, and **VPC Service Controls (VPC-SC)**.

---

## 1. Architecture Overview (3-Project Hub-and-Spoke Topology)

| Project Role | Config Variable | Key Provisioned Resources |
| :--- | :--- | :--- |
| **Project 1: Coordinator Host** | `AGENT_A_PROJECT_ID` | • **Coordinator Agent A (`coordinator-agent-a`)** on Vertex AI Agent Runtime (`AGENT_IDENTITY` SPIFFE principal)<br/>• Cross-project `agentToAnywhereConfig` binding to Project 3's `central-egress-gw`<br/>• Custom Org Policy (`custom.allowlistedEgressAgentGatewaysForAgentEngine`)<br/>• Dedicated VPC, `/28` PSC subnet, PSC network attachment, Artifact Registry |
| **Project 2: Specialist Host** | `AGENT_B_PROJECT_ID` | • **Specialist Agent B (`specialist-agent-b`)** on Vertex AI Agent Runtime (`AGENT_IDENTITY` SPIFFE principal), exposing A2A JSON-RPC at `/api/a2a/app`<br/>• Cross-project `agentToAnywhereConfig` binding to Project 3's `central-egress-gw`<br/>• Resource-scoped `roles/agentInvoker` granted exclusively to Coordinator Agent A's SPIFFE ID<br/>• Custom Org Policy (`custom.allowlistedEgressAgentGatewaysForAgentEngine`)<br/>• Dedicated VPC, `/28` PSC subnet, PSC network attachment, Artifact Registry |
| **Project 3: Central Governance Hub** | `GATEWAY_PROJECT_ID` | • **Single Central Egress Agent Gateway (`central-egress-gw`, `AGENT_TO_ANYWHERE`)** steering & TLS-inspecting 100% of outbound traffic from Projects 1 and 2<br/>• **Central Regional Agent Registry** cataloging `specialist-agent-b`, `coordinator-agent-a`, and `essential-gcp-apis`<br/>• **IAP Unified Access Policy (`V2`, `failOpen: false`)** (`central-egress-iap-policy` -> `central-egress-iap-ext`)<br/>• Organization-level **VPC-SC Service Perimeter (`a2a_enterprise_perimeter`)** enclosing all 3 projects |

---

## 2. Quickstart Deployment

### Step 1: Configure Environment Variables
```bash
cp config/project_config.env.example config/project_config.env
# Populate your 3 GCP project IDs, ORG_ID, and VPC_SC_ADMIN_USER in config/project_config.env
```

### Step 2: Deploy All Infrastructure & Agents (2-Pass Terraform + Cloud Build)
```bash
./scripts/deploy_all.sh
```
`scripts/deploy_all.sh` executes:
1. [`scripts/bootstrap_tf.sh`](scripts/bootstrap_tf.sh) — Enables APIs across all 3 projects, resolves project numbers, resets Argolis IAM policy constraints, creates the remote state bucket, and generates `infra/terraform/terraform.tfvars` and `infra/terraform/backend.hcl`.
2. **Terraform Pass 1 (`deploy_agents=false`)** — Provisions VPCs, `/28` PSC attachments, VPC-SC perimeter, Project 3's Central Egress Gateway (`central-egress-gw`), Central Agent Registry, IAP UAP v2, and Artifact Registries.
3. [`scripts/build_and_push.sh`](scripts/build_and_push.sh) — Extracts the dynamically generated TLS Inspection Root CA (`agentGatewayCard.rootCertificates`) from Project 3's `central-egress-gw` and builds/pushes both agent images via Cloud Build.
4. **Terraform Pass 2 (`deploy_agents=true`)** — Deploys both Vertex AI Reasoning Engines with `AGENT_IDENTITY`, binds them cross-project to Project 3's `central-egress-gw`, registers their A2A Agent Cards in Project 3's Agent Registry, binds SPIFFE IAM roles (`roles/iap.egressor`, `roles/agentregistry.viewer`, `roles/agentInvoker`), and enforces `custom.allowlistedEgressAgentGatewaysForAgentEngine`.

### Step 3: Run Live End-to-End A2A Verification
```bash
./scripts/verify_e2e_a2a.sh
```

---

## 3. Documentation & Runbooks

* [**Architecture & Security Rationale (ADR)**](docs/architecture-and-security-rationale.md) — Why a single Central Egress Gateway in Project 3 governs all cross-project A2A traffic without redundant local ingress gateways.
* [**Security Threats & Mitigations**](docs/security-threats-and-mitigations.md) — Deep dive into the 9 enterprise threat vectors and 4-plane anti-bypass controls (Data, Control, Identity, and Perimeter planes).
* [**Google Cloud Console Testing & Observability Guide**](docs/cloud-console-testing-guide.md) — Step-by-step instructions to test the agents in the Vertex AI Playground, inspect `central-egress-gw` logs, run Log Analytics SQL queries, and execute negative governance demos.
* [**Executive Presentation (3 Slides)**](docs/enterprise-a2a-slides.md) — Problem & Solution, 3-Project Architecture & Data Flow Diagram, and Security Controls Matrix.

---

## 4. Local Development & Verification Gates

```bash
uv run --no-sync ruff check .
uv run --no-sync ruff format --check .
uv run --no-sync pytest tests/unit/ -v
terraform -chdir=infra/terraform fmt -check
terraform -chdir=infra/terraform validate
```
