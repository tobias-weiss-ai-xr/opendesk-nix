# Backup Tools Image for Kyverno Policy Backup
# Contains kubectl, aws-cli, gcloud, sops, and other backup utilities

FROM alpine:3.19

LABEL maintainer="openDesk Edu Team <tobias.weiss@hrz.uni-marburg.de>"
LABEL description="Backup tools for Kyverno policy backup and restore"

# Install dependencies
RUN apk add --no-cache \
    bash \
    curl \
    jq \
    openssl \
    ca-certificates

# Install kubectl
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && chmod +x kubectl \
    && mv kubectl /usr/local/bin/

# Install AWS CLI
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf awscliv2.zip aws

# Install Google Cloud SDK
RUN curl -O https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-468.0.0-linux-x86_64.tar.gz \
    && tar -xf google-cloud-cli-468.0.0-linux-x86_64.tar.gz \
    && ./google-cloud-sdk/install.sh --disable-interactive \
    && rm -rf google-cloud-cli-468.0.0-linux-x86_64.tar.gz

# Install SOPS (Secrets OPerationS)
RUN curl -LO "https://github.com/getsops/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64" \
    && chmod +x sops-v3.8.1.linux.amd64 \
    && mv sops-v3.8.1.linux.amd64 /usr/local/bin/sops

# Install age (encryption tool for SOPS)
RUN curl -LO "https://github.com/FiloSottile/age/releases/download/v1.1.1/age-v1.1.1-linux-amd64.tar.gz" \
    && tar -xzf age-v1.1.1-linux-amd64.tar.gz \
    && mv age/age-keygen age/age /usr/local/bin/ \
    && rm -rf age age-v1.1.1-linux-amd64.tar.gz

# Install yq (YAML processor)
RUN curl -LO "https://github.com/mikefarah/yq/releases/download/v4.40.5/yq_linux_amd64" \
    && chmod +x yq_linux_amd64 \
    && mv yq_linux_amd64 /usr/local/bin/yq

# Create backup directory
RUN mkdir -p /backup /encrypted && chmod 755 /backup /encrypted

# Set working directory
WORKDIR /backup

# Default command
CMD ["/bin/sh"]
