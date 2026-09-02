FROM nginxinc/nginx-unprivileged:1.30-alpine

LABEL org.opencontainers.image.title="Skatteetaten training waiting page" \
      org.opencontainers.image.description="Unofficial training page for a Kubernetes security lab"

COPY --chown=nginx:nginx app/ /usr/share/nginx/html/

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --quiet --output-document=/dev/null http://127.0.0.1:8080/ || exit 1
