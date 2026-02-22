FROM alpine:3.20

LABEL org.opencontainers.image.title="alpine-base-template" \
      org.opencontainers.image.description="Lightweight Alpine-based starter image" \
      org.opencontainers.image.source="https://github.com/your-org/alpine-base-template"

RUN apk add --no-cache \
    bash \
    ca-certificates \
    curl \
    iproute2 \
    iputils \
    tzdata

WORKDIR /app

COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sh"]
