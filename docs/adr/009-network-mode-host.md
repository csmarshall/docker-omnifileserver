# ADR-009: Network Mode Host for mDNS/Avahi Service Discovery

**Status**: Superseded by ADR-019

**Date**: 2025-01-30

---

**⚠️ This ADR has been superseded by [ADR-019: Host Avahi for Service Discovery](019-host-avahi-for-service-discovery.md)**

**What was wrong:**
- Running Avahi in both containers causes hostname conflicts ("Rosa-35")
- Service discovery fails when both containers advertise the same hostname
- The assumption that "different service types = no conflict" was incorrect

**The fix (ADR-019):**
- Disable Avahi in both containers
- Run Avahi on the host system
- Use `./manage.sh setup-avahi` wizard for guided setup
- One Avahi daemon advertising multiple services (SMB + AFP)

---

## Context

File servers need to be discoverable on the network for user convenience:
- macOS Finder's "Network" sidebar shows available servers
- Windows "Network" explorer shows available shares
- This discovery uses mDNS/Avahi (Bonjour on macOS, Zero-conf on Linux)

Docker containers can use different network modes:
1. **Bridge mode** (default): Container gets its own IP on a Docker bridge network
2. **Host mode**: Container shares the host's network namespace

mDNS/Avahi requires:
- Multicast packets (224.0.0.251:5353)
- Ability to respond to broadcast discovery requests
- Access to host network interfaces

**Key architectural decision**: ServerContainers images (both Samba and Netatalk) have **Avahi built-in**. Each container runs its own Avahi daemon advertising its own service.

## Considered Options

### Option 1: Bridge mode with port forwarding
Container on bridge network, forward SMB (445) and AFP (548) ports.

**Pros:**
- Network isolation (more secure)
- Standard Docker networking

**Cons:**
- **mDNS doesn't work**: Multicast packets don't cross Docker bridge
- No automatic service discovery
- Users must manually type server addresses
- Would need additional Avahi solution (see Option 3)

### Option 2: Host mode (CHOSEN)
Both containers use `network_mode: host`, each running its own Avahi daemon.

**Pros:**
- mDNS/Avahi "just works" - multicast reaches physical network
- Each container's built-in Avahi advertises its service
- Servers appear automatically in Finder/Network browsers
- No port forwarding needed
- No coordination between containers needed
- Simpler deployment (just two containers, no extras)

**Cons:**
- Less network isolation
- Container binds to host's network interfaces directly
- Port conflicts if host runs Samba/Netatalk already

### Option 3: Separate unified Avahi container (REJECTED)
Run a third container for Avahi that advertises both SMB and AFP services.

**Why rejected:**
- **Extra container to manage** (three instead of two)
- **Requires coordination**: Samba/Netatalk would need to register services with shared Avahi
  - ServerContainers images aren't designed for this
  - Would need IPC or shared volumes for service registration
- **Different vendor concern**: Would need to find/build a separate Avahi container
  - ServerContainers Samba and Netatalk already have Avahi built-in
  - Using a third vendor's Avahi image adds dependency and complexity
- **No real benefit**: Still need host network for one container (the Avahi one)
- **More failure points**: If Avahi container dies, both services become undiscoverable

### Option 4: Unified control plane for Avahi (REJECTED)
Build custom orchestration to have containers share Avahi daemon.

**Why rejected:**
- **Massive complexity**: Would need custom scripts/daemons for IPC
- **Fight against ServerContainers design**: Images have Avahi built-in
- **Not how the images are designed to work**
- **Maintenance burden**: We'd own the glue code
- **No clear benefit**: Two Avahi instances on host network work fine

## Decision

Use `network_mode: host` for both Samba and Netatalk containers.

**Each container runs its own Avahi daemon**:
- Samba container: Avahi advertises SMB service
- Netatalk container: Avahi advertises AFP service
- Both daemons coexist peacefully on host network
- No coordination needed between containers

This approach:
- Leverages ServerContainers' built-in Avahi (no extra work)
- Avoids complexity of shared/unified Avahi
- Keeps containers independent
- "Just works" with ServerContainers design

Trade-off accepted:
- We lose network isolation
- But we gain automatic service discovery (primary feature)
- Two Avahi instances is fine (they advertise different services)

## Consequences

### Positive

- **Automatic discovery**: Servers appear in network browsers
- **Zero client config**: Users don't need to know IP addresses
- **macOS integration**: Appears in Finder sidebar automatically
- **Windows integration**: Appears in Network explorer
- **Built-in Avahi works**: No extra containers needed
- **Simpler architecture**: No port forwarding or IPC complexity
- **Independent containers**: No coordination between Samba/Netatalk needed
- **Vendor consistency**: Both containers from ServerContainers with matching design
- **No custom orchestration**: Use images as designed

### Negative

- **Reduced isolation**: Containers can access all host network interfaces
- **Port conflicts**: Can't run host Samba/Netatalk alongside
- **Security trade-off**: Compromised container has more network access
- **Less portable**: Doesn't work well with Docker networks/overlay
- **Two Avahi daemons**: Slightly more resource usage (negligible)

### Mitigations

- Document that host must not be running Samba/Netatalk already
- Use ServerContainers images (trusted, well-maintained)
- File permissions still protect data (containers run as specific UIDs)
- Target audience (home/small office) values convenience over isolation
- Advanced users can modify docker-compose.yml for bridge mode if needed
- Two Avahi instances is not a problem (each advertises different service)

## Why Two Avahi Instances is Fine

**Each Avahi daemon advertises a different service**:
- Samba Avahi: `_smb._tcp` service type
- Netatalk Avahi: `_afpovertcp._tcp` service type

**No conflicts**:
- Different service names
- Different port numbers (445 vs 548)
- Both listening on same multicast group (standard mDNS)
- Avahi is designed to handle multiple daemons on same network

**Why not share one Avahi**:
- Would require custom integration (not how images work)
- No performance benefit (Avahi is lightweight)
- Adds failure coupling (one Avahi dies = both services invisible)

## Principles

- **User experience over architectural purity**: Discovery is a key feature
- **Convenience over isolation**: Target audience values "it just works"
- **Pragmatic trade-offs**: Accept security reduction for functionality gain
- **Use tools as designed**: ServerContainers includes Avahi, use it
- **Avoid unnecessary coordination**: Keep containers independent

## For AI Assistants

When users report:
- "Server doesn't appear in Finder/Network" → Check if network_mode: host is set
- "Port 445 already in use" → Host has Samba running, must stop it first
- "Can't connect to server" → Verify containers are using host network
- "Why two Avahi daemons?" → Explain each advertises different service, no conflict

NEVER suggest:
- Adding a separate Avahi container (adds complexity for no benefit)
- Unifying Avahi across containers (fights ServerContainers design)
- Changing to bridge mode without explaining mDNS discovery will break

If user wants more isolation:
1. Warn that automatic discovery will stop working
2. Suggest they can manually change network_mode in generated docker-compose.yml
3. Explain they'll need to manually connect via IP address (smb://192.168.x.x)

## Security Considerations

This is acceptable risk because:
- Target audience is home/small office (not enterprise)
- Containers still have filesystem isolation
- ServerContainers images are trusted and maintained
- Users value convenience over paranoid security
- Alternative (no discovery) significantly degrades UX

For paranoid users:
- They can modify generated docker-compose.yml
- Or use bridge mode and manually connect via IP
- Or use a dedicated file server VM/machine

## References

- ServerContainers Samba image (includes Avahi)
- ServerContainers Netatalk image (includes Avahi)
- docker-compose.yml `network_mode: host` setting
- [Docker network modes documentation](https://docs.docker.com/network/)
- [Avahi/mDNS specification](https://www.avahi.org/)
- ADR-003 (Use ServerContainers images)
