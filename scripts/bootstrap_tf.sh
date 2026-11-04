#!/usr/bin/env bash
# ==============================================================================
# Bootstrap Script for 3-Project Enterprise A2A Governance Terraform Setup
# ==============================================================================
# Responsibilities:
#   1. Load & validate `config/project_config.env`
#   2. Dynamically resolve GCP project numbers & VPC-SC Access Policy ID
#   3. Enable required Google Cloud APIs across all 3 projects
#   4. Reset Argolis boolean Org Policy `iam.managed.disableAccessPolicyBindings`
#      so IAP Unified Access Policy (UAP v2 / roles/iap.egressor) bindings succeed
#   5. Create versioned GCS bucket in Project 3 for Terraform remote state
#   6. Generate `infra/terraform/backend.hcl` and `infra/terraform/terraform.tfvars`
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${CONFIG_FILE:-${REPO_ROOT}/config/project_config.env}"
TF_DIR="${REPO_ROOT}/infra/terraform"

if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "ERROR: Configuration file not found at ${CONFIG_FILE}" >&2
  echo "Copy the example file and fill in your Argolis project values:" >&2
  echo "  cp config/project_config.env.example config/project_config.env" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "${CONFIG_FILE}"

REQUIRED_VARS=(
  "ORG_ID"
  "REGION"
  "GATEWAY_PROJECT_ID"
  "AGENT_A_PROJECT_ID"
  "AGENT_B_PROJECT_ID"
  "VPC_SC_ADMIN_USER"
  "GEMINI_MODEL"
)

for var_name in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var_name:-}" ]]; then
    echo "ERROR: Required variable '${var_name}' is empty or unset in ${CONFIG_FILE}" >&2
    exit 1
  fi
done

REMOTE_AGENT_B_ID="${REMOTE_AGENT_B_ID:-agents/specialist-agent-b}"

if [[ "${GATEWAY_PROJECT_ID}" == "${AGENT_A_PROJECT_ID}" ]] || \
   [[ "${GATEWAY_PROJECT_ID}" == "${AGENT_B_PROJECT_ID}" ]] || \
   [[ "${AGENT_A_PROJECT_ID}" == "${AGENT_B_PROJECT_ID}" ]]; then
  echo "ERROR: GATEWAY_PROJECT_ID, AGENT_A_PROJECT_ID, and AGENT_B_PROJECT_ID must be 3 distinct GCP projects." >&2
  exit 1
fi

echo "==> [1/6] Resolving GCP Project Numbers..."
GATEWAY_PROJECT_NUMBER="$(gcloud projects describe "${GATEWAY_PROJECT_ID}" --format="value(projectNumber)")"
AGENT_A_PROJECT_NUMBER="$(gcloud projects describe "${AGENT_A_PROJECT_ID}" --format="value(projectNumber)")"
AGENT_B_PROJECT_NUMBER="$(gcloud projects describe "${AGENT_B_PROJECT_ID}" --format="value(projectNumber)")"

echo "    Project 3 (Gateway Hub): ${GATEWAY_PROJECT_ID} (${GATEWAY_PROJECT_NUMBER})"
echo "    Project 1 (Agent A):     ${AGENT_A_PROJECT_ID} (${AGENT_A_PROJECT_NUMBER})"
echo "    Project 2 (Agent B):     ${AGENT_B_PROJECT_ID} (${AGENT_B_PROJECT_NUMBER})"

ALL_PROJECTS=(
  "${GATEWAY_PROJECT_ID}"
  "${AGENT_A_PROJECT_ID}"
  "${AGENT_B_PROJECT_ID}"
)

BOOTSTRAP_APIS=(
  "serviceusage.googleapis.com"
  "cloudresourcemanager.googleapis.com"
  "orgpolicy.googleapis.com"
  "iam.googleapis.com"
  "compute.googleapis.com"
  "aiplatform.googleapis.com"
  "networkservices.googleapis.com"
  "networksecurity.googleapis.com"
  "agentregistry.googleapis.com"
  "iap.googleapis.com"
  "artifactregistry.googleapis.com"
  "cloudbuild.googleapis.com"
  "accesscontextmanager.googleapis.com"
  "logging.googleapis.com"
  "cloudtrace.googleapis.com"
  "monitoring.googleapis.com"
  "telemetry.googleapis.com"
)

echo "==> [2/6] Enabling required GCP APIs across all 3 projects..."
for proj in "${ALL_PROJECTS[@]}"; do
  echo "    Enabling APIs in ${proj}..."
  gcloud services enable "${BOOTSTRAP_APIS[@]}" --project="${proj}" --quiet
done

if [[ -z "${VPC_SC_POLICY_ID:-}" ]]; then
  echo "==> Auto-detecting Access Context Manager (VPC-SC) Policy ID for Org ${ORG_ID}..."
  VPC_SC_POLICY_ID="$(CLOUDSDK_BILLING_PROJECT="${GATEWAY_PROJECT_ID}" gcloud access-context-manager policies list \
    --organization="${ORG_ID}" \
    --format="value(name.basename())" | head -n 1)"
  if [[ -z "${VPC_SC_POLICY_ID}" ]]; then
    echo "    No existing Access Context Manager policy found for Org ${ORG_ID}; creating default org policy..."
    CLOUDSDK_BILLING_PROJECT="${GATEWAY_PROJECT_ID}" gcloud access-context-manager policies create \
      --organization="${ORG_ID}" \
      --title="Default Org Access Policy" --quiet
    VPC_SC_POLICY_ID="$(CLOUDSDK_BILLING_PROJECT="${GATEWAY_PROJECT_ID}" gcloud access-context-manager policies list \
      --organization="${ORG_ID}" \
      --format="value(name.basename())" | head -n 1)"
  fi
fi
echo "    VPC-SC Policy ID:        ${VPC_SC_POLICY_ID}"

echo "==> [3/6] Resetting Argolis Org Policy 'iam.managed.disableAccessPolicyBindings' (if present)..."
for proj in "${ALL_PROJECTS[@]}"; do
  CLOUDSDK_BILLING_PROJECT="${GATEWAY_PROJECT_ID}" gcloud org-policies reset \
    constraints/iam.managed.disableAccessPolicyBindings \
    --project="${proj}" --quiet 2>/dev/null || true
done

TF_STATE_BUCKET="${GATEWAY_PROJECT_ID}-tfstate"
echo "==> [4/6] Ensuring Terraform remote state bucket gs://${TF_STATE_BUCKET} exists in ${GATEWAY_PROJECT_ID}..."
if ! gcloud storage buckets describe "gs://${TF_STATE_BUCKET}" --project="${GATEWAY_PROJECT_ID}" >/dev/null 2>&1; then
  gcloud storage buckets create "gs://${TF_STATE_BUCKET}" \
    --project="${GATEWAY_PROJECT_ID}" \
    --location="${REGION}" \
    --uniform-bucket-level-access
  gcloud storage buckets update "gs://${TF_STATE_BUCKET}" \
    --versioning \
    --project="${GATEWAY_PROJECT_ID}"
else
  echo "    Bucket gs://${TF_STATE_BUCKET} already exists."
fi

mkdir -p "${TF_DIR}"

echo "==> [5/6] Generating ${TF_DIR}/backend.hcl..."
cat >"${TF_DIR}/backend.hcl" <<EOF
bucket = "${TF_STATE_BUCKET}"
prefix = "multi-project-a2a-agent-gateway/state"
EOF

echo "==> [6/6] Generating ${TF_DIR}/terraform.tfvars..."
cat >"${TF_DIR}/terraform.tfvars" <<EOF
org_id                 = "${ORG_ID}"
region                 = "${REGION}"
gateway_project_id     = "${GATEWAY_PROJECT_ID}"
gateway_project_number = "${GATEWAY_PROJECT_NUMBER}"
agent_a_project_id     = "${AGENT_A_PROJECT_ID}"
agent_a_project_number = "${AGENT_A_PROJECT_NUMBER}"
agent_b_project_id     = "${AGENT_B_PROJECT_ID}"
agent_b_project_number = "${AGENT_B_PROJECT_NUMBER}"
vpc_sc_policy_id       = "${VPC_SC_POLICY_ID}"
vpc_sc_admin_user      = "${VPC_SC_ADMIN_USER}"
gemini_model           = "${GEMINI_MODEL}"
remote_agent_b_id      = "${REMOTE_AGENT_B_ID}"
deploy_agents          = false
iap_enforcement_mode   = "DRY_RUN"
EOF

echo ""
echo "Bootstrap complete!"
echo "Next steps:"
echo "  1. terraform -chdir=infra/terraform init -backend-config=backend.hcl"
echo "  2. terraform -chdir=infra/terraform apply"
