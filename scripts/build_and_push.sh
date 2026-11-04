#!/usr/bin/env bash
# ==============================================================================
# Build & Push Agent Container Images with Central Egress Gateway Root CAs
# ==============================================================================
# Reads config/project_config.env, retrieves agentGatewayCard.rootCertificates
# from Project 3's central-egress-gw, and submits Cloud Build jobs to build and
# push Coordinator Agent A (Project 1) and Specialist Agent B (Project 2).
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${1:-${REPO_ROOT}/config/project_config.env}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "ERROR: Configuration file not found at ${CONFIG_FILE}." >&2
  echo "Copy config/project_config.env.example to config/project_config.env first." >&2
  exit 1
fi

# shellcheck source=/dev/null
source "${CONFIG_FILE}"

REQUIRED_VARS=(
  "REGION"
  "GATEWAY_PROJECT_ID"
  "AGENT_A_PROJECT_ID"
  "AGENT_B_PROJECT_ID"
)

for var_name in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var_name:-}" ]]; then
    echo "ERROR: Required variable ${var_name} is missing or empty in ${CONFIG_FILE}." >&2
    exit 1
  fi
done

echo "==> Fetching Root CA certificates from Central Egress Gateway in Project 3 (${GATEWAY_PROJECT_ID})..."
ACCESS_TOKEN="$(gcloud auth print-access-token)"
GATEWAY_URL="https://networkservices.googleapis.com/v1alpha1/projects/${GATEWAY_PROJECT_ID}/locations/${REGION}/agentGateways/central-egress-gw"

ROOT_CERTS_PEM="$(
  curl -sSf \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "X-Goog-User-Project: ${GATEWAY_PROJECT_ID}" \
    "${GATEWAY_URL}" \
  | python3 -c "import json, sys; data = json.load(sys.stdin); certs = data.get('agentGatewayCard', {}).get('rootCertificates', []); print('\n'.join(certs))"
)"

if [[ -z "${ROOT_CERTS_PEM}" ]]; then
  echo "WARNING: No rootCertificates returned from central-egress-gw; proceeding with system CA bundle." >&2
fi

build_and_push_agent() {
  local project_id="$1"
  local image_name="$2"
  local dockerfile_rel="$3"
  local image_uri="${REGION}-docker.pkg.dev/${project_id}/agent-repo/${image_name}:${IMAGE_TAG}"

  local tmp_cloudbuild
  tmp_cloudbuild="$(mktemp "${TMPDIR:-/tmp}/cloudbuild-${image_name}-XXXXXX.yaml")"
  cat > "${tmp_cloudbuild}" <<EOF
steps:
  - name: 'gcr.io/cloud-builders/docker'
    args:
      - 'build'
      - '-f'
      - '${dockerfile_rel}'
      - '--build-arg'
      - 'AGENT_GATEWAY_ROOT_CERTIFICATES=\${_ROOT_CERTS}'
      - '-t'
      - '${image_uri}'
      - '.'
images:
  - '${image_uri}'
EOF

  echo "==> Building and pushing ${image_uri} in project ${project_id}..."
  gcloud builds submit "${REPO_ROOT}" \
    --project="${project_id}" \
    --region="${REGION}" \
    --config="${tmp_cloudbuild}" \
    --substitutions="_ROOT_CERTS=${ROOT_CERTS_PEM}"

  rm -f "${tmp_cloudbuild}"
}

build_and_push_agent \
  "${AGENT_B_PROJECT_ID}" \
  "specialist-agent" \
  "agents/specialist_agent/Dockerfile"

build_and_push_agent \
  "${AGENT_A_PROJECT_ID}" \
  "coordinator-agent" \
  "agents/coordinator_agent/Dockerfile"

echo "==> Successfully built and pushed both agent images!"
