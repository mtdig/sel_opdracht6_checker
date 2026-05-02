FROM debian:trixie-slim
 
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    curl \
    jq \
    mariadb-client \
    openssh-client \
    sshpass \
    iputils-ping \
    netcat-openbsd \
    ca-certificates \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Install Bitwarden CLI pre-built binary
RUN curl -fsSL "https://github.com/bitwarden/clients/releases/download/cli-v2026.4.1/bw-linux-2026.4.1.zip" \
    -o /tmp/bw.zip \
    && unzip -q /tmp/bw.zip -d /usr/local/bin/ \
    && chmod +x /usr/local/bin/bw \
    && rm /tmp/bw.zip
 
COPY checker.sh /checker.sh
COPY secrets.env.enc /secrets.env.enc
RUN chmod +x /checker.sh
 
ENTRYPOINT ["/checker.sh"]
 