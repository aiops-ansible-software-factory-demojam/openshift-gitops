FROM registry.access.redhat.com/ubi9/ubi-minimal@sha256:34880b64c07f28f64d95737f82f891516de9a3b43583f39970f7bf8e4cfa48b7

ARG OPENSHELL_VERSION=0.0.116
ARG OPENSHELL_SHA256=4fb4476d80a1875a0b83547ec3aba999cf0a2e2d75f95f2f709b622e2103520e
USER 0
RUN microdnf install -y python3 tar gzip ca-certificates shadow-utils coreutils \
    && microdnf clean all \
    && mkdir -p /opt/agentic-runner /data /home/runner \
    && chgrp -R 0 /opt/agentic-runner /data /home/runner \
    && chmod -R g=u /opt/agentic-runner /data /home/runner
ADD https://github.com/NVIDIA/OpenShell/releases/download/v${OPENSHELL_VERSION}/openshell-x86_64-unknown-linux-musl.tar.gz /tmp/openshell.tar.gz
RUN echo "${OPENSHELL_SHA256}  /tmp/openshell.tar.gz" | sha256sum -c - \
    && tar -C /usr/local/bin -xzf /tmp/openshell.tar.gz \
    && chmod 0555 /usr/local/bin/openshell \
    && rm /tmp/openshell.tar.gz
COPY runner /opt/agentic-runner
COPY images/runner/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0555 /usr/local/bin/entrypoint.sh
ENV PYTHONPATH=/opt/agentic-runner \
    HOME=/home/runner
WORKDIR /opt/agentic-runner
USER 1001
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
