# Google Cloud Console Testing, Observability & Verification Runbook

This guide provides step-by-step instructions to verify, test, and observe the **3-Project Enterprise Agent-to-Agent (A2A) Governance** deployment in the **Google Cloud Console** and via the CLI.

---

## 0. Retrieve Live Deployment Parameters & Console Links

All project IDs, Reasoning Engine IDs, SPIFFE identities, and direct Google Cloud Console URLs are exported as Terraform outputs. Run the following command from the repository root to display your live values:

```bash
terraform -chdir=infra/terraform output
```

Key outputs returned:
* `console_links.project_1_agent_engine` — Vertex AI Agent Engine UI for **Project 1 (`AGENT_A_PROJECT_ID`)**
* `console_links.project_2_agent_engine` — Vertex AI Agent Engine UI for **Project 2 (`AGENT_B_PROJECT_ID`)**
* `console_links.project_3_agent_gateways` — Central Egress Agent Gateway UI for **Project 3 (`GATEWAY_PROJECT_ID`)**
* `console_links.project_3_agent_registry` — Central Agent Registry UI for **Project 3 (`GATEWAY_PROJECT_ID`)**
* `agent_a_engine_id` / `agent_a_spiffe_principal` — Coordinator Agent A Reasoning Engine ID and SPIFFE ID
* `agent_b_engine_id` / `agent_b_spiffe_principal` — Specialist Agent B Reasoning Engine ID and SPIFFE ID
* `agent_b_a2a_endpoint_url` — Specialist Agent B A2A JSON-RPC endpoint URL (`/api/a2a/app`)

---

## 1. Verify Central Agent Gateway & Agent Registry in Project 3 (`GATEWAY_PROJECT_ID`)

### 1.1 Verify `central-egress-gw` in Network Services
1. Open the **Google Cloud Console** and select **Project 3 (`<GATEWAY_PROJECT_ID>`)**.
2. Navigate to **Network Services -> Agent Gateways**:
   ```text
   https://console.cloud.google.com/net-services/agent-gateways/list?project=<GATEWAY_PROJECT_ID>
   ```
3. Click **`central-egress-gw`** (Region: `<REGION>`) and verify:
   * **Status**: `ACTIVE`
   * **Governed Access Path**: `AGENT_TO_ANYWHERE` (Google-managed egress)
   * **Protocols**: `MCP`
   * **Attached Registries**: `//agentregistry.googleapis.com/projects/<GATEWAY_PROJECT_ID>/locations/<REGION>`
   * **Authorization Policy**: Bound to `central-egress-iap-policy` (`REQUEST_AUTHZ` -> `central-egress-iap-ext`, `iapPolicyVersion = "V2"`, `failOpen = false`).

### 1.2 Verify Central Agent Registry Catalog
1. In **Project 3 (`<GATEWAY_PROJECT_ID>`)**, navigate to **Agent Registry -> Agents**:
   ```text
   https://console.cloud.google.com/agent-registry/agents?project=<GATEWAY_PROJECT_ID>
   ```
2. Verify that both **`Specialist Agent B`** (`services/specialist-agent-b`) and **`Coordinator Agent A`** (`services/coordinator-agent-a`) appear with their `A2A_AGENT_CARD` endpoint specifications (`JSONRPC` v1.0 & v0.3 interfaces pointing to `/api/a2a/app`).
3. Navigate to **Agent Registry -> Endpoints** (or query via API) to verify **`Essential Google Cloud APIs`** (`services/essential-gcp-apis`), which allowlists `aiplatform`, `logging`, `telemetry`, `cloudtrace`, `monitoring`, and `agentregistry` hostnames.

---

## 2. Verify SPIFFE Workload Identities & Cross-Project Gateway Bindings (Projects 1 & 2)

### 2.1 Project 2 (`AGENT_B_PROJECT_ID`) — Specialist Agent B
1. Select **Project 2 (`<AGENT_B_PROJECT_ID>`)** in the Google Cloud Console and open **Vertex AI -> Agent Engine**:
   ```text
   https://console.cloud.google.com/vertex-ai/agents/agent-engines?project=<AGENT_B_PROJECT_ID>
   ```
2. Click **`specialist-agent-b`** (ID: `<ENGINE_B_ID>`) and inspect its deployment details:
   * **Identity Type**: `AGENT_IDENTITY`
   * **Effective SPIFFE Principal**:
     ```text
     principal://agents.global.org-<ORG_ID>.system.id.goog/resources/aiplatform/projects/<AGENT_B_PROJECT_NUMBER>/locations/<REGION>/reasoningEngines/<ENGINE_B_ID>
     ```
   * **Bound Egress Agent Gateway**:
     ```text
     projects/<GATEWAY_PROJECT_ID>/locations/<REGION>/agentGateways/central-egress-gw
     ```
   * **Caller Authorization (`roles/agentInvoker`)**: In **IAM & Admin -> IAM** for Project 2, verify that custom role `projects/<AGENT_B_PROJECT_ID>/roles/agentInvoker` is granted exclusively to Coordinator Agent A's SPIFFE principal.

### 2.2 Project 1 (`AGENT_A_PROJECT_ID`) — Coordinator Agent A
1. Select **Project 1 (`<AGENT_A_PROJECT_ID>`)** in the Google Cloud Console and open **Vertex AI -> Agent Engine**:
   ```text
   https://console.cloud.google.com/vertex-ai/agents/agent-engines?project=<AGENT_A_PROJECT_ID>
   ```
2. Click **`coordinator-agent-a`** (ID: `<ENGINE_A_ID>`) and verify:
   * **Identity Type**: `AGENT_IDENTITY`
   * **Effective SPIFFE Principal**:
     ```text
     principal://agents.global.org-<ORG_ID>.system.id.goog/resources/aiplatform/projects/<AGENT_A_PROJECT_NUMBER>/locations/<REGION>/reasoningEngines/<ENGINE_A_ID>
     ```
   * **Bound Egress Agent Gateway**:
     ```text
     projects/<GATEWAY_PROJECT_ID>/locations/<REGION>/agentGateways/central-egress-gw
     ```

---

## 3. Interactive End-to-End A2A Testing (Cloud Console Playground & CLI)

### 3.1 Test Specialist Agent B Directly in Project 2 Playground
1. In **Project 2 (`<AGENT_B_PROJECT_ID>`) -> Vertex AI -> Agent Engine -> `specialist-agent-b`**, open the **Playground** tab.
2. Enter the prompt:
   ```text
   What is the status of ticket TKT-101?
   ```
3. Verify that `specialist_agent_b` invokes the `get_project_b_ticket_status` tool and returns:
   * **Ticket ID**: `TKT-101`
   * **Status**: `APPROVED_IN_PROJECT_B`
   * **Handler**: `specialist_agent_b`
   * **Project Role**: `Project 2 Specialist Host`

### 3.2 Test Cross-Project A2A Delegation in Project 1 Playground
1. In **Project 1 (`<AGENT_A_PROJECT_ID>`) -> Vertex AI -> Agent Engine -> `coordinator-agent-a`**, open the **Playground** tab.
2. Enter the prompt:
   ```text
   Ask the specialist agent in Project B for the status of ticket TKT-101
   ```
3. Verify the multi-hop execution:
   * `coordinator_agent_a` calls `transfer_to_agent(agent_name="specialist_agent_b")`.
   * `coordinator_agent_a` dynamically resolves `"agents/specialist-agent-b"` from **Project 3's Central Agent Registry** through `central-egress-gw`.
   * `coordinator_agent_a` sends an A2A JSON-RPC `message/send` request authenticated with its SPIFFE Bearer token through **Project 3's `central-egress-gw`** to **Specialist Agent B in Project 2**.
   * `specialist_agent_b` executes `get_project_b_ticket_status("TKT-101")` in Project 2 and returns `APPROVED_IN_PROJECT_B` to Project 1.

### 3.3 Automated CLI End-to-End Verification Script
Run the automated verification script to test Registry discovery, direct Agent B A2A JSON-RPC, cross-project Agent A -> Agent B A2A JSON-RPC, and Vertex AI `:streamQuery`:

```bash
./scripts/verify_e2e_a2a.sh
```

---

## 4. Exploring Agent Gateway Logs & Observability in Google Cloud Console

### 4.1 Built-in Observability Tab Inside Agent Gateway (`GATEWAY_PROJECT_ID`)
1. Open **Network Services -> Agent Gateways -> `central-egress-gw`** in **Project 3 (`<GATEWAY_PROJECT_ID>`)**:
   ```text
   https://console.cloud.google.com/net-services/agent-gateways/details/<REGION>/central-egress-gw?project=<GATEWAY_PROJECT_ID>
   ```
2. Click the **Observability** (or **Monitoring**) tab to view:
   * **Request Rate (RPS)** by HTTP response status (`200 OK` vs `403 Forbidden`).
   * **Gateway & Authz Extension Latency** (P50 / P95 / P99 round-trip time and `central-egress-iap-ext` evaluation latency).
   * **Active mTLS Connections** from Project 1 and Project 2 Reasoning Engines.

### 4.2 Inspecting `central-egress-gw` Traffic in Logs Explorer (`GATEWAY_PROJECT_ID`)
Open **Logging -> Logs Explorer** in **Project 3 (`<GATEWAY_PROJECT_ID>`)**:
```text
https://console.cloud.google.com/logs/query?project=<GATEWAY_PROJECT_ID>
```

#### Filter 1: All Decrypted Requests Traversing `central-egress-gw`
```text
resource.type="networkservices.googleapis.com/Gateway"
resource.labels.gateway_name="central-egress-gw"
httpRequest.requestMethod!="CONNECT"
```

#### Filter 2: Cross-Project A2A Calls (Agent A -> Agent B `/api/a2a/app`)
```text
resource.type="networkservices.googleapis.com/Gateway"
resource.labels.gateway_name="central-egress-gw"
httpRequest.requestUrl:"/api/a2a/app"
```
Expand the JSON payload of a matching entry and verify:
* `httpRequest.status`: `200`
* `jsonPayload.enforcedGatewaySecurityPolicy.requestWasTlsIntercepted`: `true` *(confirms deep TLS inspection with the Gateway Root CA)*
* `jsonPayload.authzPolicyInfo.result`: `"ALLOWED"` *(confirms IAP Unified Access Policy v2 `central-egress-iap-policy` authorized the request)*
* `jsonPayload.agentGatewayInfo.agentRegistryResource`: `"projects/<GATEWAY_PROJECT_NUMBER>/locations/<REGION>/agents/agentregistry-..."` *(confirms the gateway matched Specialist Agent B's registered Agent Card)*
* `jsonPayload.mtls.clientCertPresent`: `"true"` and `clientCertSha256Fingerprint` *(identifies Coordinator Agent A's SPIFFE workload certificate)*

#### Filter 3: Dynamic Agent Registry Discovery Lookups
```text
resource.type="networkservices.googleapis.com/Gateway"
resource.labels.gateway_name="central-egress-gw"
httpRequest.requestUrl:"agentregistry.googleapis.com"
```

#### Filter 4: Outbound Gemini LLM Calls from Both Agents
```text
resource.type="networkservices.googleapis.com/Gateway"
resource.labels.gateway_name="central-egress-gw"
httpRequest.requestUrl:"generateContent"
```

#### Filter 5: Blocked / Unauthorized Egress Attempts (`DENIED`)
```text
resource.type="networkservices.googleapis.com/Gateway"
resource.labels.gateway_name="central-egress-gw"
jsonPayload.authzPolicyInfo.result="DENIED"
```

### 4.3 Log Analytics SQL Query for `central-egress-gw` (`GATEWAY_PROJECT_ID`)
Open **Logging -> Log Analytics** in **Project 3 (`<GATEWAY_PROJECT_ID>`)** and run:

```sql
SELECT
  timestamp,
  http_request.request_method AS method,
  http_request.status AS status,
  JSON_VALUE(json_payload.enforcedGatewaySecurityPolicy.hostname) AS destination_host,
  http_request.request_url AS full_url,
  JSON_VALUE(json_payload.authzPolicyInfo.result) AS iap_decision,
  JSON_VALUE(json_payload.agentGatewayInfo.agentRegistryResource) AS matched_registry_resource,
  JSON_VALUE(json_payload.enforcedGatewaySecurityPolicy.requestWasTlsIntercepted) AS tls_intercepted,
  SUBSTR(JSON_VALUE(json_payload.mtls.clientCertSha256Fingerprint), 1, 12) AS caller_spiffe_cert_id,
  http_request.latency AS latency
FROM
  `<GATEWAY_PROJECT_ID>.global._Default._AllLogs`
WHERE
  resource.type = "networkservices.googleapis.com/Gateway"
  AND JSON_VALUE(resource.labels.gateway_name) = "central-egress-gw"
  AND http_request.request_method != "CONNECT"
ORDER BY
  timestamp DESC
LIMIT 50
```

### 4.4 Reasoning Engine Runtime Logs & Cloud Trace (Projects 1 & 2)
* **Project 1 (`<AGENT_A_PROJECT_ID>`) Container Logs**:
  ```text
  resource.type="aiplatform.googleapis.com/ReasoningEngine"
  resource.labels.reasoning_engine_id="<ENGINE_A_ID>"
  ```
* **Project 2 (`<AGENT_B_PROJECT_ID>`) Container Logs**:
  ```text
  resource.type="aiplatform.googleapis.com/ReasoningEngine"
  resource.labels.reasoning_engine_id="<ENGINE_B_ID>"
  ```
* **Cloud Trace Explorer**:
  * Project 1: `https://console.cloud.google.com/traces/explorer?project=<AGENT_A_PROJECT_ID>`
  * Project 2: `https://console.cloud.google.com/traces/explorer?project=<AGENT_B_PROJECT_ID>`

---

## 5. Live Negative Governance & Anti-Bypass Demos in Cloud Console

### Demo 5.1: Control-Plane Anti-Bypass (`CUSTOM_ORG_POLICY_VIOLATION`)
Demonstrate that no developer can create or update a `ReasoningEngine` in Project 1 or Project 2 without binding it to Project 3's `central-egress-gw`:

1. Open **IAM & Admin -> Organization Policies** in **Project 1 (`<AGENT_A_PROJECT_ID>`)**:
   ```text
   https://console.cloud.google.com/iam-admin/orgpolicies/custom-allowlistedEgressAgentGatewaysForAgentEngine?project=<AGENT_A_PROJECT_ID>
   ```
2. Verify `custom.allowlistedEgressAgentGatewaysForAgentEngine` is **Enforced**.
3. Attempt to patch `<ENGINE_A_ID>` without `agentGatewayConfig` (or attempt to create an unbound Reasoning Engine):
   ```bash
   source config/project_config.env
   ENGINE_A_ID="$(terraform -chdir=infra/terraform output -raw agent_a_engine_id)"
   TOKEN="$(gcloud auth print-access-token)"
   curl -i -X PATCH \
     -H "Authorization: Bearer ${TOKEN}" \
     -H "X-Goog-User-Project: ${AGENT_A_PROJECT_ID}" \
     -H "Content-Type: application/json" \
     "https://${REGION}-aiplatform.googleapis.com/v1beta1/projects/${AGENT_A_PROJECT_ID}/locations/${REGION}/reasoningEngines/${ENGINE_A_ID}?updateMask=spec.deploymentSpec.minInstances" \
     -d '{"spec":{"deploymentSpec":{"minInstances":1}}}'
   ```
4. **Expected Result**: Vertex AI immediately rejects the request with `HTTP 400 Bad Request` and `"reason": "CUSTOM_ORG_POLICY_VIOLATION"` citing `customConstraints/custom.allowlistedEgressAgentGatewaysForAgentEngine`.

### Demo 5.2: Identity-Plane Anti-Bypass (Revoking `roles/agentInvoker` on Agent B)
Demonstrate that even when traffic traverses `central-egress-gw`, Project 2's Reasoning Engine enforces SPIFFE caller identity:

1. Temporarily remove Coordinator Agent A's `agentInvoker` binding in Project 2 (`<AGENT_B_PROJECT_ID>`), send the A2A prompt in Project 1's Playground, and observe `403 PERMISSION_DENIED` on `/api/a2a/app`.
2. Restore the binding immediately with:
   ```bash
   terraform -chdir=infra/terraform apply -var="deploy_agents=true" -var="iap_enforcement_mode=DRY_RUN" -auto-approve
   ```
