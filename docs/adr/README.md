# Architecture Decision Records (ADRs)

This directory contains Architecture Decision Records (ADRs) for the docker-omnifileserver project.

## What are ADRs?

ADRs document important architectural decisions made during the development of this project. Each ADR describes:
- The context that led to the decision
- The decision itself and alternatives considered
- The consequences (positive and negative) of the decision

## Format

We use a simplified MADR (Markdown Architectural Decision Record) format with these sections:

- **Status**: Proposed, Accepted, Deprecated, or Superseded
- **Date**: When the decision was made
- **Context**: The problem or situation requiring a decision
- **Decision(s)**: What was decided (may include "Considered Options")
- **Consequences**: Impacts of the decision (positive/negative/mitigations)
- **Principles**: Guiding principles behind the decision
- **For AI Assistants**: Specific guidance for AI maintainers
- **References**: Relevant code, documentation, or external resources

## Index of ADRs

| ADR | Title | Status |
|-----|-------|--------|
| [000](000-project-purpose-and-naming.md) | **Project Purpose, Naming, and Design Philosophy (READ THIS FIRST)** | Accepted |
| [001](001-separate-password-and-config-files.md) | Separate Password and Configuration Files | Accepted |
| [002](002-cli-env-file-flags-for-substitution.md) | Use Docker Compose CLI --env-file Flags for Variable Substitution | Accepted |
| [003](003-use-servercontainers-images.md) | Use Pre-Built ServerContainers Images | Accepted |
| [004](004-single-config-synced-to-multiple-protocols.md) | Single Configuration Synced to Multiple Protocols | Accepted |
| [005](005-absolute-paths-with-script-dir.md) | Absolute Paths with SCRIPT_DIR for Portability | Accepted |
| [006](006-manage-sh-wrapper-for-docker-compose.md) | manage.sh Wrapper for Docker Compose Operations | Accepted |
| [007](007-os-auto-detection-for-home-directories.md) | OS Auto-Detection for Home Directories | Accepted |
| [008](008-generated-docker-compose.md) | Generated docker-compose.yml (Never Manual Editing) | Accepted |
| [009](009-network-mode-host.md) | Network Mode Host for mDNS/Avahi Service Discovery | Accepted |
| [010](010-two-separate-containers.md) | Two Separate Containers vs One Combined | Accepted |
| [011](011-bash-scripting-for-tooling.md) | Bash Scripts for Tooling | Accepted |
| [012](012-protocol-specific-shares.md) | Protocol-Specific Shares | Accepted |
| [013](013-rejected-docker-compose-secrets.md) | Rejected Docker Compose Secrets for Password Management | Rejected |
| [014](014-colon-separated-config-format.md) | Colon-Separated Config File Format | Accepted |
| [015](015-reset-with-optional-backup.md) | Reset Configuration with Optional Backup | Accepted |
| [016](016-absolute-paths-only-no-project-shares.md) | Absolute Paths Only (No Project ./shares/ Directory) | Accepted |
| [017](017-auto-detect-uid-gid-from-host.md) | Auto-Detect UID/GID from Host System Users | Accepted |
| [018](018-per-user-variable-paths.md) | Per-User Variable Paths with %U | Accepted |

## Creating New ADRs

When making significant architectural decisions:

1. Copy the template from an existing ADR
2. Number sequentially (next number after highest existing)
3. Use descriptive filename: `NNN-short-title-with-hyphens.md`
4. Fill in all sections thoroughly
5. Update this README index
6. Commit the ADR with the code changes it describes

## For AI Assistants

When modifying the architecture:
1. Review relevant ADRs first to understand existing decisions
2. If proposing a change that contradicts an ADR, create a new ADR that supersedes it
3. Document new architectural decisions as ADRs
4. Keep ADRs concise but complete
5. Focus on *why* decisions were made, not just *what* was decided
