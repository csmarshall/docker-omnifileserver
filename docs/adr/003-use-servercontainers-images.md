# ADR-003: Use Pre-Built ServerContainers Images

**Status**: Accepted

**Date**: 2025-01-30

## Context

The project needs to run both Samba (SMB/CIFS) and Netatalk (AFP) file servers in Docker containers with:
- Avahi/mDNS service discovery for network browsing
- macOS compatibility (Time Machine, Finder icons)
- User/password management
- Share configuration via environment variables

We needed to decide between building custom containers or using existing images.

## Considered Options

### Option 1: Build custom Dockerfile
- Install Samba + Netatalk + Avahi in one container
- Pro: Full control, single container
- Con: Complex maintenance, must handle updates, larger attack surface

### Option 2: Use separate official images
- Official Samba image + Official Netatalk image
- Con: Official images often lack features (no Avahi integration, limited env var config)

### Option 3: Use ServerContainers images (CHOSEN)
- `ghcr.io/servercontainers/samba`
- `ghcr.io/servercontainers/netatalk`
- Pro: Built-in Avahi, env var configuration, macOS features, actively maintained
- Con: Dependency on third-party maintainer

## Decision

Use ServerContainers pre-built images from ghcr.io:
- Both images include built-in Avahi/mDNS support
- Configuration entirely via environment variables
- Support for macOS-specific features (Finder icons via `fruit_model`, Time Machine)
- Regular updates and Alpine-based (small, secure)
- Proven track record in community

**No separate Avahi container needed** - both images handle mDNS internally.

## Consequences

### Positive

- Zero container build/maintenance overhead
- Battle-tested configurations
- Avahi "just works" without extra containers
- Environment variable configuration is scriptable
- Alpine base = small images, quick starts

### Negative

- Dependency on ServerContainers maintainer
- Limited to what images support (can't add arbitrary features)
- Must use environment variable configuration format they define

### Mitigations

- Images are well-maintained and popular
- Configuration formats are stable
- If needed, could fork and maintain our own builds
- Document all env var formats in generate-compose.sh

## Principles

- Don't build what already exists: Use proven solutions
- Minimize maintenance burden: Pre-built > DIY
- Community over custom: Leverage others' expertise

## For AI Assistants

When adding features:
- Check ServerContainers image documentation for supported env vars
- Samba docs: https://github.com/ServerContainers/samba
- Netatalk docs: https://github.com/ServerContainers/netatalk
- DO NOT attempt to modify containers (use env vars only)
- If feature isn't supported, document limitation rather than trying to work around it

## References

- [ServerContainers Samba](https://github.com/ServerContainers/samba)
- [ServerContainers Netatalk](https://github.com/ServerContainers/netatalk)
- [ghcr.io container registry](https://ghcr.io)
