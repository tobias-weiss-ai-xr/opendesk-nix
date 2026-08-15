# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightText: 2024-2025 Univention GmbH
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# openDesk Edu fork of the intercom-service (ICS) image.
# Base: upstream ICS 2.23.11 (Univention) on a standard Node Alpine base instead
# of the 2GB UCS base image (see
# articles/extending-intercom-service-community-consensus-en.md).
# Fork adds: /oc/ (OpenCloud proxy), /sogo/ (CalDAV/CardDAV proxy), /health.
#
# The image is built from the UPSTREAM 2.23.11 tree (gitlab.opencode.de/
# bmi/opendesk/component-code/crossfunctional/univention/univention_ics) with
# THIS directory's files copied over it as an overlay. See README.md.
#
# Build:
#   docker build -t ghcr.io/opendesk-edu/intercom-service:2.23.11 .
# Push (SCS air-gap):
#   docker save ghcr.io/opendesk-edu/intercom-service:2.23.11 | \
#     ssh scs@172.25.24.36 "docker load"
#   ssh scs@172.25.24.36 "docker tag ghcr.io/opendesk-edu/intercom-service:2.23.11 \
#     172.17.0.6:5001/ghcr.io/opendesk-edu/intercom-service:2.23.11 && docker push \
#     172.17.0.6:5001/ghcr.io/opendesk-edu/intercom-service:2.23.11"

FROM node:20-alpine

WORKDIR /app

# Runtime deps only (devDependencies are the upstream test/CI toolchain).
COPY package.json yarn.lock ./
RUN yarn install --production --frozen-lockfile 2>/dev/null || npm install --omit=dev --no-audit --no-fund

COPY . /app

# Run as non-root (matches the Helm chart securityContext runAsUser/Group 1000)
USER 1000

EXPOSE 8080

CMD ["node", "app.js"]
