# Attic Binary Cache Deployment Guide

**Phase 2 Implementation**  
**Date:** 2026-08-10

---

## Overview

This guide describes how to deploy the Attic binary cache server on the SCS K3s cluster.

---

## Prerequisites

- Ceph RGW instance accessible from SCS network
- Nix installed on deployment machine
- Access to SCS cluster network
- Signing key for binary cache

---

## Step 1: Generate Signing Key

```bash
# Generate Ed25519 signing key
nix-store --generate-binary-cache-key \
  attic.scs.hrz@uni-marburg.de-1.private \
  attic.scs.hrz@uni-marburg.de-1.public

# View public key (for distribution to clients)
cat attic.scs.hrz@uni-marburg.de-1.public
# Example output: attic.scs.hrz@uni-marburg.de-1:abc123def456...

# Secure private key
chmod 600 attic.scs.hrz@uni-marburg.de-1.private
```

---

## Step 2: Create Ceph RGW Bucket

```bash
# Using radosgw-admin (on Ceph monitor node)
radosgw-admin bucket create --bucket=attic-cache \
  --uid=attic --max-objects=0

# Create user for Attic
radosgw-admin user create --uid=attic \
  --display-name="Attic Binary Cache" \
  --access-key=ATTIC_ACCESS_KEY \
  --secret-key=ATTIC_SECRET_KEY

# Set bucket quota (optional)
radosgw-admin quota set --quota-type=bucket \
  --max-size=500GB --uid=attic --bucket=attic-cache
```

---

## Step 3: Deploy Attic Server

### Option A: NixOS Configuration

```nix
# configurations/attic-server.nix
{
  imports = [
    ./modules/attic-server.nix
    ./modules/binary-cache-client.nix
  ];

  services.attic-server = {
    enable = true;
    listenAddress = "0.0.0.0";
    listenPort = 8080;
    storageBackend = "ceph";
    s3Endpoint = "http://ceph.rgw.sc