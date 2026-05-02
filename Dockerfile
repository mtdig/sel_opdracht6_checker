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
    && rm -rf /var/lib/apt/lists/*

# install Node.js and bitwarden cli via npm --> TODO: replace with not npm because reasons
RUN apt-get update && apt-get install -y --no-install-recommends nodejs npm \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g @bitwarden/cli 2>/dev/null
 
COPY checker.sh /checker.sh
COPY secrets.env.enc /secrets.env.enc
RUN chmod +x /checker.sh
 
ENTRYPOINT ["/checker.sh"]
 