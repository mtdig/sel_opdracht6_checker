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
 
COPY checker.sh /checker.sh
COPY secrets.env.enc /secrets.env.enc
RUN chmod +x /checker.sh
 
ENTRYPOINT ["/checker.sh"]
 