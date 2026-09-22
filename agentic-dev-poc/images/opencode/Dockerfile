FROM registry.access.redhat.com/ubi9/ubi-minimal@sha256:34880b64c07f28f64d95737f82f891516de9a3b43583f39970f7bf8e4cfa48b7

ARG OPENCODE_VERSION=1.18.31
USER 0
RUN microdnf install -y python3 python3-pip nodejs npm tar gzip shadow-utils findutils iproute util-linux-core \
    && npm install -g "opencode-ai@${OPENCODE_VERSION}" \
    && microdnf clean all \
    && mkdir -p /sandbox/work /opt/agentic-poc \
    && chmod 1777 /sandbox /sandbox/work
COPY images/opencode/wrapper.py /opt/agentic-poc/wrapper.py
COPY images/opencode/opencode.json /opt/agentic-poc/opencode.json
COPY fixtures /opt/agentic-poc/fixtures
RUN chmod 0555 /opt/agentic-poc/wrapper.py \
    && chmod -R a-w /opt/agentic-poc
ENV OPENCODE_CONFIG=/opt/agentic-poc/opencode.json \
    OPENCODE_MODEL=poc/glm-5.3-flash \
    HOME=/sandbox/opencode-home
WORKDIR /sandbox
USER 1001
