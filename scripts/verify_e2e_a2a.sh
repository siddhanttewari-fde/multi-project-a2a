#!/usr/bin/env bash
# ==============================================================================
# Live End-to-End 3-Project A2A Governance Verification Script
# ==============================================================================
# Verifies:
#   1. Central Agent Registry catalog in Project 3 (GATEWAY_PROJECT_ID)
#   2. Direct A2A JSON-RPC call to Specialist Agent B in Project 2 (AGENT_B_PROJECT_ID)
#   3. Cross-project A2A JSON-RPC delegation from Coordinator Agent A in Project 1
#      (AGENT_A_PROJECT_ID) -> Project 3 Registry & Egress Gateway -> Agent B (Project 2)
#   4. Vertex AI Playground (:streamQuery) execution on Coordinator Agent A
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${REPO_ROOT}/config/project_config.env"
TF_DIR="${REPO_ROOT}/infra/terraform"

if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "ERROR: Configuration file not found at ${CONFIG_FILE}" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "${CONFIG_FILE}"

ENGINE_A_ID="$(terraform -chdir="${TF_DIR}" output -raw agent_a_engine_id)"
ENGINE_B_ID="$(terraform -chdir="${TF_DIR}" output -raw agent_b_engine_id)"
AGENT_B_A2A_URL="$(terraform -chdir="${TF_DIR}" output -raw agent_b_a2a_endpoint_url)"
AGENT_A_PROJECT_NUMBER="$(gcloud projects describe "${AGENT_A_PROJECT_ID}" --format="value(projectNumber)")"
AGENT_A_A2A_URL="https://${REGION}-aiplatform.googleapis.com/reasoningEngines/v1/projects/${AGENT_A_PROJECT_NUMBER}/locations/${REGION}/reasoningEngines/${ENGINE_A_ID}/api/a2a/app"

TOKEN="$(gcloud auth print-access-token)"

echo "==> [1/4] Verifying Central Agent Registry in Project 3 (${GATEWAY_PROJECT_ID})..."
AGENTS_JSON="$(curl -sSf \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "X-Goog-User-Project: ${GATEWAY_PROJECT_ID}" \
  "https://agentregistry.googleapis.com/v1alpha/projects/${GATEWAY_PROJECT_ID}/locations/${REGION}/agents")"
echo "${AGENTS_JSON}" | python3 -c '
import json, sys
data = json.load(sys.stdin)
names = [a.get("displayName", "") for a in data.get("agents", [])]
assert any(n in names for n in ("specialist_agent_b", "Specialist Agent B")), f"specialist_agent_b missing from registry: {names}"
assert any(n in names for n in ("coordinator_agent_a", "Coordinator Agent A")), f"coordinator_agent_a missing from registry: {names}"
print("    Registered Agents:", ", ".join(names))
'

echo "==> [2/4] Testing Specialist Agent B HMAC Verification in Project 2 (${AGENT_B_PROJECT_ID}, Engine ${ENGINE_B_ID})..."
BODY_B='{"jsonrpc":"2.0","id":"verify-b","method":"message/send","params":{"message":{"messageId":"msg-verify-b","role":"user","parts":[{"kind":"text","text":"What is the status of ticket TKT-101?"}]}}}'

UNSIGNED_CODE="$(curl -s -o /dev/null -w "%{http_code}" -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  "${AGENT_B_A2A_URL}" \
  -d "${BODY_B}")"
echo "    Unsigned direct call to Specialist Agent B HTTP status: ${UNSIGNED_CODE} (expected 401)"
if [[ "${UNSIGNED_CODE}" != "401" ]]; then
  echo "ERROR: Expected 401 for unsigned direct call to Specialist Agent B, got ${UNSIGNED_CODE}" >&2
  exit 1
fi

HMAC_HEADERS="$(python3 -c '
import hashlib, hmac, sys, time, uuid
org_id, gw_proj, a_proj, b_proj, body = sys.argv[1:6]
secret = hashlib.sha256(f"{org_id}:{gw_proj}:{a_proj}:{b_proj}:a2a-gateway-hmac".encode()).hexdigest()
ts = str(int(time.time()))
nonce = uuid.uuid4().hex
body_digest = hashlib.sha256(body.encode()).hexdigest()
sig = hmac.new(secret.encode(), f"{ts}.{nonce}.{body_digest}".encode(), hashlib.sha256).hexdigest()
print(f"{ts} {nonce} {sig}")
' "${ORG_ID}" "${GATEWAY_PROJECT_ID}" "${AGENT_A_PROJECT_ID}" "${AGENT_B_PROJECT_ID}" "${BODY_B}")"
read -r HMAC_TS HMAC_NONCE HMAC_SIG <<< "${HMAC_HEADERS}"

RESP_B="$(curl -sSf -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -H "X-A2A-Timestamp: ${HMAC_TS}" \
  -H "X-A2A-Nonce: ${HMAC_NONCE}" \
  -H "X-A2A-Signature: ${HMAC_SIG}" \
  "${AGENT_B_A2A_URL}" \
  -d "${BODY_B}")"
echo "${RESP_B}" | python3 -c '
import json, sys
raw = sys.stdin.read()
assert "APPROVED_IN_PROJECT_B" in raw, f"Expected APPROVED_IN_PROJECT_B in response: {raw}"
print("    HMAC-signed call to Specialist Agent B returned APPROVED_IN_PROJECT_B")
'

echo "==> [3/4] Testing Cross-Project A2A Delegation from Coordinator Agent A in Project 1 (${AGENT_A_PROJECT_ID}, Engine ${ENGINE_A_ID})..."
RESP_A="$(curl -sSf -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  "${AGENT_A_A2A_URL}" \
  -d '{
    "jsonrpc": "2.0",
    "id": "verify-a",
    "method": "message/send",
    "params": {
      "message": {
        "messageId": "msg-verify-a",
        "role": "user",
        "parts": [{"kind": "text", "text": "Ask the specialist agent in Project B for the status of ticket TKT-101"}]
      }
    }
  }')"
echo "${RESP_A}" | python3 -c '
import json, sys
raw = sys.stdin.read()
assert "APPROVED_IN_PROJECT_B" in raw, f"Expected APPROVED_IN_PROJECT_B in cross-project response: {raw}"
print("    Coordinator Agent A -> Registry -> Central Egress Gateway -> Specialist Agent B returned APPROVED_IN_PROJECT_B")
'

echo "==> [4/4] Testing Vertex AI Playground (:streamQuery) on Coordinator Agent A..."
STREAM_A="$(curl -sSf -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  "https://${REGION}-aiplatform.googleapis.com/v1beta1/projects/${AGENT_A_PROJECT_ID}/locations/${REGION}/reasoningEngines/${ENGINE_A_ID}:streamQuery?alt=sse" \
  -d '{
    "class_method": "async_stream_query",
    "input": {
      "user_id": "cli-verify-user",
      "message": "Ask the specialist agent in Project B for the status of ticket TKT-101"
    }
  }')"
echo "${STREAM_A}" | python3 -c '
import sys
raw = sys.stdin.read()
assert "APPROVED_IN_PROJECT_B" in raw, f"Expected APPROVED_IN_PROJECT_B in streamQuery output: {raw}"
print("    Vertex AI :streamQuery returned APPROVED_IN_PROJECT_B")
'

echo "==> All 4 End-to-End 3-Project A2A Governance checks passed!"
