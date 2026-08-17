# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
# SPDX-License-Identifier: Apache-2.0

# multi-stage build for argunix-builder
# Stage 1: Build argunix-builder using Rust
FROM ghcr.io/rust-lang/rust:1-slim AS builder

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config \
    libssh2-1-dev \
    openssl \
    libssl-dev \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Clone argunix repository
WORKDIR /usr/src
RUN git clone https://codeberg.org/tfc/argunix.git --depth 1 --branch main
WORKDIR /usr/src/argunix

# Build release binary
RUN cargo build --release --package argunix-builder --bin argunix-builder

# Stage 2: Create runtime image
FROM debian:12-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libssh2-1 \
    openssl \
    ca-certificates \
    libssl3 \
    nix \
    && rm -rf /var/lib/apt/lists/*

# Create argunix-builder user
RUN useradd -r -s /bin/false argunix-builder

# Copy binary from builder stage
COPY --from=builder /usr/src/argunix/target/release/argunix-builder /usr/local/bin/argunix-builder

# Configure Nix
COPY docker/nix.conf /etc/nix/nix.conf
COPY docker/profile /nix/etc/profile.d/argunix-builder.sh
RUN chmod +x /nix/etc/profile.d/argunix-builder.sh

# Create directories
RUN mkdir -p \
    /var/lib/argunix-builder \
    /nix/var/nix/gcroots/argunix \
    /run/nixd

RUN chown -R argunix-builder:argunix-builder \
    /var/lib/argunix-builder

# Switch to argunix-builder user
USER argunix-builder
WORKDIR /var/lib/argunix-builder

# Expose builder enrollment port (can connect to coordinator on 45678)
EXPOSE 45678

ENTRYPOINT ["/usr/local/bin/argunix-builder"]
CMD ["--config", "/var/lib/argunix-builder/config.yaml"]
