FROM python:3.12-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Trust Project 3 Central Egress Agent Gateway Root CA certificates
ARG AGENT_GATEWAY_ROOT_CERTIFICATES=""
RUN if [ -n "${AGENT_GATEWAY_ROOT_CERTIFICATES}" ]; then \
      printf "%s\n" "${AGENT_GATEWAY_ROOT_CERTIFICATES}" | awk ' \
        /-----BEGIN CERTIFICATE-----/ { n++; file=sprintf("/usr/local/share/ca-certificates/agent_gateway_%d.crt", n) } \
        file { print > file } \
        /-----END CERTIFICATE-----/ { close(file); file="" } \
      ' && update-ca-certificates; \
    fi

ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
    GRPC_DEFAULT_SSL_ROOTS_FILE_PATH=/etc/ssl/certs/ca-certificates.crt \
    GOOGLE_API_USE_CLIENT_CERTIFICATE=false \
    GOOGLE_API_USE_MTLS_ENDPOINT=never \
    PYTHONUNBUFFERED=1 \
    PORT=8080

COPY --from=ghcr.io/astral-sh/uv:0.6.6 /uv /uvx /bin/

COPY pyproject.toml ./
RUN uv sync --no-dev --no-install-project --default-index https://pypi.org/simple

COPY agents ./agents

EXPOSE 8080

CMD ["uv", "run", "--no-sync", "uvicorn", "agents.specialist_agent.server:app", "--host", "0.0.0.0", "--port", "8080"]
