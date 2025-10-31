# ADR-000: Project Purpose, Naming, and Design Philosophy (READ THIS FIRST)

**Status**: Accepted

**Date**: 2025-01-30

## Context

File sharing in mixed-environment networks (macOS, Windows, Linux) is complex:

- **Multiple protocols needed**: SMB/CIFS for Windows/modern macOS, AFP for legacy macOS
- **Configuration complexity**: Each protocol has different config syntax, user management, share definitions
- **Deployment challenges**: Installing and configuring Samba, Netatalk, and Avahi manually is error-prone
- **Maintenance burden**: Keeping user lists and shares synchronized across protocols
- **Portability issues**: Hard to migrate file server configs between hosts

**The core problem**: Setting up a simple file server that "just works" for both Windows and Mac clients requires significant Linux/Unix expertise and ongoing maintenance.

## Project Purpose

**docker-omnifileserver** provides a unified, Docker-based file server that:

1. **Supports multiple protocols** from a single configuration
   - SMB/CIFS (Windows, modern macOS, Linux)
   - AFP (legacy macOS, Time Machine)
   - mDNS/Avahi service discovery (network browsing)

2. **Simplifies management** through a single CLI tool
   - One command to add users (synced across both protocols)
   - One command to add shares (synced across both protocols)
   - One command to deploy changes

3. **Maximizes portability** via Docker containers
   - No host system modifications
   - Easy migration between machines
   - Reproducible deployments

4. **Prioritizes security** by design
   - Password separation from configuration
   - Secure prompts (passwords not in shell history)
   - Proper file permissions (chmod 600 for secrets)

## Naming Decision

### Project Name: "docker-omnifileserver"

**"Omni"** (from Latin "omnis" = all/every):
- **All protocols**: SMB + AFP from unified config
- **All platforms**: Serves Windows, macOS, Linux clients
- **All-in-one**: Single management interface for everything

**"docker-"** prefix:
- Signals Docker-based deployment
- Follows naming convention (docker-compose, docker-nginx, etc.)
- Searchable/discoverable on GitHub/Docker Hub

**Alternative names considered**:
- ~~universal-fileserver~~ - Too generic
- ~~multi-protocol-nas~~ - Implies hardware (this is software only)
- ~~unified-smb-afp~~ - Too technical, focuses on implementation not benefit
- ~~omnihomefileserver~~ - Too narrow (not just for homes)

### Internal branding: "OmniFileServer"

The user-facing name (in prompts, documentation) is "OmniFileServer" without the docker- prefix for cleaner UX.

## Target Audience

**Primary**: Home users and small offices who:
- Have mixed Mac/Windows environments
- Want simple, reliable file sharing
- Prefer Docker for easy management
- Don't need enterprise features (AD integration, clustering, etc.)

**Secondary**: Hobbyists and developers who:
- Run home labs or personal servers
- Want portable, reproducible file server configs
- Appreciate clean, well-documented tools

**NOT for**:
- Large enterprises (use enterprise NAS or dedicated servers)
- Users who need Windows ACL support (use pure Samba)
- Users who need only one protocol (simpler tools exist)
- Users without Docker knowledge (need to understand basic Docker concepts)

## Design Principles

1. **Convention over configuration**
   - Sensible defaults for 99% of use cases
   - Auto-detection (OS, home directories)
   - No configuration required for basic setup

2. **Security by default**
   - Passwords separated from config
   - Secure prompts, never echo passwords
   - Proper file permissions enforced
   - Never commit secrets to git

3. **Single source of truth**
   - Config files (users.conf, shares.conf, .env)
   - docker-compose.yml is ALWAYS generated, never manual
   - One command syncs everything

4. **Portability first**
   - Absolute paths with $SCRIPT_DIR
   - Works from any directory
   - Survives symlinks
   - No assumptions about working directory

5. **User experience over implementation simplicity**
   - Interactive wizards for common tasks
   - Clear error messages
   - Helpful prompts with defaults
   - Hide complexity behind manage.sh

6. **Explicit over implicit**
   - Show what files are loaded (comments in generated compose)
   - Clear logging of what's being done
   - Document decisions in ADRs

## Scope and Non-Goals

### In Scope
- SMB and AFP protocol support
- User and share management
- Home directory sharing
- Service discovery (mDNS/Avahi)
- macOS-specific features (Finder icons, Time Machine support)
- Protocol-specific shares (SMB-only or AFP-only)

### Out of Scope (at least initially)
- NFS protocol (different use case)
- Active Directory integration (enterprise feature)
- Web UI (CLI-first philosophy)
- Cloud sync (Dropbox, Nextcloud, etc.)
- RAID/storage management (use host OS)
- User quotas (use host filesystem quotas)
- Clustering/high availability (single-node design)

### Might Add Later
- NFS support (if requested by users)
- Read-only Docker volumes (security hardening)
- Metrics/monitoring integration
- Backup automation helpers

## High-Level Architecture

```
User
  ↓
manage.sh (CLI interface)
  ↓
Config Files (users.conf, shares.conf, .env)
  ↓
generate-compose.sh
  ↓
docker-compose.yml (generated, gitignored)
  ↓
Docker Compose
  ↓
┌─────────────────┬─────────────────┐
│  Samba Container│Netatalk Container│
│   (SMB/CIFS)    │      (AFP)       │
│   + Avahi       │    + Avahi       │
└─────────────────┴─────────────────┘
  ↓
Network (mDNS service discovery)
  ↓
Clients (Windows, macOS, Linux)
```

**Key architectural decisions** (see other ADRs for details):
- Two containers vs one (isolation, updates)
- Pre-built images vs custom Dockerfile (maintenance)
- Bash scripts vs other languages (portability)
- Generated compose file vs manual (consistency)

## For AI Assistants

This is ADR-000 - the foundational document. Read this FIRST before making changes to understand:
- The project's purpose and target audience
- What's in scope vs out of scope
- Core design principles to maintain
- Naming conventions

When adding features:
1. Ask: Does this align with the target audience?
2. Check: Is this in scope or should it be declined?
3. Consider: Does this follow the design principles?
4. Document: Create an ADR if it's a significant decision

The name "OmniFileServer" should NOT be changed without serious consideration and user agreement.

## References

- README.md (user-facing documentation)
- manage.sh (implementation of design principles)
- All other ADRs (specific technical decisions)
- Original discussion about naming (conversation history)
