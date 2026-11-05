#!/usr/bin/env bash
# ==============================================================================
# Two-Pass Declarative Terraform + Container Build Orchestration (Phase D)
# ==============================================================================
# Pass 1: Provision 3-project VPCs, /28 PSC attachments, VPC-SC perimeter,
#         Artifact Registries, Custom Org Policy constraint, and Project 3
#         Central Egress Agent Gateway + Agent Registry + IAP UAP v2 (DRY_RUN).
# Step 2: Fetch Central Egress Gateway Root CAs and build/push both agent
#         container images to Project 1 and Project 2 Artifact Registries.
# Pass 2: Provision Coordinator Agent A (Project 1) and Specialist Agent B
#         (Project 2) on Vertex AI Agent Runtime with AGENT_IDENTITY, bind both
#         cross-project to Project 3's Central Egress Gateway, register both
#         agents in Project 3's Central Agent Registry, bind SPIFFE IAM roles
#         (roles/iap.egressor, roles/agentregistry.viewer, agentInvoker), attach
#         Custom Org Policy enforcement, and switch IAP UAP v2 to ENFORCED.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TF_DIR="${REPO_ROOT}/infra/terraform"

echo "==> [1/3] Running Terraform Pass 1 (Base Infrastructure & Central Egress Gateway)..."
terraform -chdir="${TF_DIR}" init -reconfigure -backend-config=backend.hcl
terraform -chdir="${TF_DIR}" apply -auto-approve \
  -var="deploy_agents=false" \
  -var="iap_enforcement_mode=DRY_RUN"

echo "==> [2/3] Building & Pushing Agent Images with Central Egress Gateway Root CA..."
"${SCRIPT_DIR}/build_and_push.sh"

echo "==> [3/3] Running Terraform Pass 2 (Reasoning Engines, Registry, SPIFFE IAM & Enforced Governance)..."
terraform -chdir="${TF_DIR}" apply -auto-approve \
  -var="deploy_agents=true" \
  -var="iap_enforcement_mode=DRY_RUN"

echo "==> Deployment complete! Terraform outputs:"
terraform -chdir="${TF_DIR}" output
