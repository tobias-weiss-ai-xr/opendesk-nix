---
capability: multi-registry
---

## ADDED Requirements

### Requirement: GitHub Container Registry Support
The system MUST support deployment to GitHub Container Registry.

#### Scenario: Push to GitHub Container Registry
Given a Docker image
When push to GitHub Container Registry is triggered
Then image MUST be pushed to ghcr.io
And image MUST be accessible from ghcr.io
And image MUST use correct namespace

#### Scenario: GitHub authentication works
Given GITHUB_TOKEN environment variable is set
When pushing to GitHub Container Registry
Then authentication MUST succeed
And token MUST NOT be exposed in logs

---

### Requirement: Image Signing
All container images MUST be signed with Cosign.

#### Scenario: Image signed with Cosign
Given a Docker image
When signing is triggered
Then image MUST be signed using Cosign
And signature MUST be created
And signature MUST be associated with image

#### Scenario: Keyless signing works
Given keyless signing is configured
When image signing runs
Then Fulcio MUST be used for identity verification
And Rekor MUST be used for signature transparency
And signature MUST be created without private key

#### Scenario: Signature verification works
Given a signed image in registry
When verification runs
Then signature MUST be retrieved from registry
And signature MUST be verified using Cosign
And verification result MUST be returned

---

### Requirement: Multi-Registry Push
A single build MUST be capable of pushing the same image to multiple registries.

#### Scenario: Push to all registries
Given a Docker image
When multi-registry push is triggered
Then image MUST be pushed to GitLab Container Registry
And image MUST be pushed to GitHub Container Registry
And image MUST be pushed to Zot Registry
And all pushes MUST use same tag

#### Scenario: Parallel push for performance
Given multiple registries configured
When multi-registry push runs
Then pushes to different registries MUST run in parallel
And total push time MUST be optimized

---

## MODIFIED Requirements

### Requirement: Registry Configuration Enhanced
The existing registry.nix MUST be extended to support multiple registries.

#### Scenario: Existing GitLab registry still works
Given existing registry.nix configuration for GitLab
When enhanced version is deployed
Then GitLab registry push MUST still work
And existing authentication MUST still work

#### Scenario: Existing Zot registry still works
Given existing registry.nix configuration for Zot
When enhanced version is deployed
Then Zot registry push MUST still work
And existing authentication MUST still work
