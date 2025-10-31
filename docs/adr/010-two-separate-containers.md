# ADR-010: Two Separate Containers vs One Combined

**Status**: Accepted

**Date**: 2025-01-30

## Context

OmniFileServer needs to run both Samba (SMB/CIFS) and Netatalk (AFP) to support Windows and macOS clients. We had to decide on the container architecture:

1. **One container**: Run both Samba and Netatalk in a single container
2. **Two containers**: Separate containers for Samba and Netatalk

Both approaches can work, but have different trade-offs around maintainability, isolation, and updates.

## Considered Options

### Option 1: Single combined container
Build a custom Dockerfile that installs both Samba and Netatalk.

**Pros:**
- One container to manage
- Shared Avahi daemon could advertise both services
- Slightly less resource overhead
- Simpler docker-compose.yml (one service)

**Cons:**
- **Must build custom image**: Can't use pre-built ServerContainers images
- **Maintenance burden**: We own the Dockerfile and must maintain it
- **Update complexity**: Must rebuild when either Samba or Netatalk needs updates
- **Larger image**: Contains both services (more attack surface)
- **Init system needed**: Need supervisord/s6 to run multiple daemons
- **Tighter coupling**: Can't restart one service without affecting the other
- **Single point of failure**: If container crashes, both protocols go down

### Option 2: Two separate containers (CHOSEN)
Use ServerContainers pre-built images, one for Samba and one for Netatalk.

**Pros:**
- **No custom builds**: Use trusted pre-built images
- **Independent updates**: Update Samba without touching Netatalk (and vice versa)
- **Service isolation**: Samba crash doesn't affect AFP
- **Smaller images**: Each contains only what it needs
- **Simpler containers**: One service per container (Docker best practice)
- **Separate restarts**: Can restart Samba without disrupting AFP users
- **Vendor maintenance**: ServerContainers handles image updates
- **Independent scaling**: Could run on different hosts (future possibility)

**Cons:**
- Two containers to manage (minor)
- Two Avahi daemons (negligible resource cost)
- Slightly more complex docker-compose.yml

## Decision

Use **two separate containers**: `ghcr.io/servercontainers/samba` and `ghcr.io/servercontainers/netatalk`.

Rationale:
- Aligns with Docker best practice ("one process per container")
- Leverages existing, well-maintained images
- Reduces maintenance burden on us
- Provides better isolation and fault tolerance
- Enables independent service management

## Consequences

### Positive

- **Zero build maintenance**: ServerContainers maintains the images
- **Battle-tested code**: Images are widely used and actively maintained
- **Independent failures**: Samba issue doesn't break AFP access
- **Granular control**: Restart/update services independently
- **Simpler containers**: No multi-process init system needed
- **Better updates**: Pull new image for one service without affecting the other
- **Standard Docker pattern**: One service per container is idiomatic

### Negative

- **Two containers**: docker-compose.yml has two service definitions
- **Slight resource overhead**: Two containers vs one (minimal in practice)
- **Coordination needed**: generate-compose.sh must create config for both
- **Two Avahi daemons**: Each container runs its own (but this is fine - see ADR-009)

### Mitigations

- generate-compose.sh handles coordination automatically
- manage.sh hides multi-container complexity from users
- Docker Compose manages both containers as one "stack"
- Resource overhead is negligible (tested: ~20MB extra RAM)
- Two Avahi instances coexist fine (advertise different services)

## Alternative Considered: Multi-Stage Build

Could build a combined image using multi-stage Docker build, installing both from Alpine packages.

**Why rejected:**
- Still own the build process
- Must track upstream Samba and Netatalk versions
- ServerContainers images have additional features (macOS integration, env var config)
- No benefit over using pre-built images

## Principles

- **Don't build what exists**: Leverage community work
- **Minimize maintenance**: Pre-built images > custom Dockerfiles
- **Isolation benefits**: Separate containers = better fault tolerance
- **Standard patterns**: Follow Docker best practices

## Real-World Benefits

**Scenario 1: Samba security update**
- With two containers: `docker pull ghcr.io/servercontainers/samba:latest && docker-compose up -d samba`
  - Only Samba restarts, AFP users unaffected
- With one container: Rebuild entire image, restart everything, both protocols down during update

**Scenario 2: Netatalk crashes**
- With two containers: AFP down, SMB still works, restart Netatalk independently
- With one container: Entire container might need restart, both protocols affected

**Scenario 3: Testing Samba beta**
- With two containers: Swap Samba image, test, rollback if needed
- With one container: Must rebuild entire image for testing

## For AI Assistants

When users ask:
- "Why not combine into one container?" → Explain maintenance burden and loss of isolation
- "Can I use one container?" → Yes, but you'll own the Dockerfile and updates
- "Isn't two containers wasteful?" → Minimal overhead, big benefits in maintainability

NEVER suggest:
- Building a custom combined Dockerfile (unless user explicitly wants to own maintenance)
- Merging the services into one container (loses all the benefits)

If user insists on single container:
- Warn about maintenance burden
- Point them to Samba and Netatalk installation docs
- Explain they'll lose automatic updates from ServerContainers

## References

- [Docker best practices: one process per container](https://docs.docker.com/develop/dev-best-practices/)
- [ServerContainers Samba image](https://github.com/ServerContainers/samba)
- [ServerContainers Netatalk image](https://github.com/ServerContainers/netatalk)
- ADR-003 (Use ServerContainers images)
- ADR-009 (Why two Avahi instances is fine)
