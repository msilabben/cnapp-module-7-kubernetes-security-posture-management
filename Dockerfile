# Serves the waiting page in app/, and when deployed with
# manifests/insecure-pod.yaml or manifests/hardened-pod.yaml also doubles as
# the target for the pod-security lab (tasks/pod_security.md). Two properties
# the lab needs:
#   1. A setuid-root binary (vulnbash), standing in for sudo/su/mount/pkexec.
#   2. Runs as a non-root user (UID 1000), so the lab has an escalation to
#      demonstrate.

FROM ubuntu:22.04

LABEL org.opencontainers.image.title="Training waiting page" \
      org.opencontainers.image.description="Unofficial training page and pod-security lab target for a Kubernetes security lab"

RUN apt-get update && apt-get install -y --no-install-recommends \
      nginx \
      curl \
      jq \
      util-linux \
      procps \
      ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# The vulnerable binary used in the lab. Owned by root, setuid bit set.
# 'bash -p' preserves the effective UID instead of dropping it.
RUN cp /bin/bash /usr/local/bin/vulnbash \
 && chown root:root /usr/local/bin/vulnbash \
 && chmod 4755 /usr/local/bin/vulnbash

RUN useradd --uid 1000 --create-home appuser

COPY nginx.conf /etc/nginx/nginx.conf
COPY --chown=appuser:appuser app/ /usr/share/nginx/html/

USER 1000
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl --fail --silent http://127.0.0.1:8080/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
