# ADR-008: Generated docker-compose.yml (Never Manual Editing)

**Status**: Accepted

**Date**: 2025-01-30

## Context

Docker Compose requires a `docker-compose.yml` file to define services, but we need:
- Dynamic configuration based on users.conf and shares.conf
- Absolute paths that vary per machine (for portability)
- Environment variable references from .env and .env.passwords
- Share and user configurations synced from single source files
- Consistent user management across both Samba and Netatalk protocols

**Key constraint**: Since we're using containers, we can't rely on OS-level user accounts. Both Samba and Netatalk need users defined via environment variables, and these must be kept in perfect sync (same usernames, same passwords, same UIDs).

We had to decide: Should docker-compose.yml be:
1. A template that users manually edit?
2. A generated artifact created from config files?

## Considered Options

### Option 1: Manual docker-compose.yml (static template)
Users edit docker-compose.yml directly to add shares/users.

**Pros:**
- Direct control over Docker config
- Standard Docker Compose workflow

**Cons:**
- Users must know Docker Compose syntax
- **CRITICAL**: Hard to keep Samba and Netatalk user configs in sync
  - Samba uses: `ACCOUNT_alice=alice;password`
  - Netatalk uses: `ACCOUNT_alice=alice;1000;1000;password`
  - Easy to get UIDs wrong or passwords mismatched between protocols
- Can't use OS users (containers are isolated)
- Easy to make mistakes (typos, format errors)
- Can't easily move between machines (hardcoded paths)
- No single source of truth

### Option 2: Generated docker-compose.yml with manage.sh input (CHOSEN)
The `generate-compose.sh` script creates docker-compose.yml from config files that are managed through `manage.sh`.

**Pros:**
- **Single input (manage.sh) ensures consistency**: One command adds user to both protocols
- Config files are simple (colon-separated, easy to read)
- Guaranteed consistency between Samba and Netatalk (same users, same passwords, same UIDs)
- Machine-specific paths inserted automatically
- Single source of truth (users.conf, shares.conf)
- Validation happens during generation
- User doesn't need to understand Docker Compose env var syntax

**Cons:**
- Can't manually tweak docker-compose.yml
- Must run generate-compose.sh after config changes
- One more step in the workflow

## Decision

**docker-compose.yml is ALWAYS generated, NEVER manually edited.**

**manage.sh is the ONLY input interface for user and share management.**

This ensures:
- Users added via `manage.sh add-user` appear in BOTH Samba and Netatalk with identical credentials
- No drift between protocol configurations
- No container/OS user account confusion (containers can't see host users anyway)
- Passwords stay synchronized automatically

Implementation:
1. User runs `./manage.sh add-user alice`
2. manage.sh updates `users.conf` (alice:1000:1000:Alice) and `.env.passwords` (PASSWORD_alice=secretpass)
3. `generate-compose.sh` reads these files
4. Generates `docker-compose.yml` with:
   - Samba: `ACCOUNT_alice=alice;${PASSWORD_alice}`
   - Netatalk: `ACCOUNT_alice=alice;1000;1000;${PASSWORD_alice}`
   - Both reference the same password variable
5. `manage.sh apply` regenerates and restarts services
6. Both containers get identical user credentials

## Consequences

### Positive

- **Single source of truth**: users.conf and shares.conf are authoritative
- **Consistency guaranteed**: Both protocols always stay in sync
- **No manual sync needed**: One command updates both protocols
- **Container-appropriate**: Doesn't rely on OS users (which containers can't access)
- **Machine portability**: Paths auto-adjusted per host
- **Error prevention**: Generate script validates configs and ensures correct env var syntax
- **Simple config files**: No Docker Compose knowledge required
- **Safe migrations**: Just copy config files, regenerate compose
- **Password security**: Passwords separated, never duplicated in multiple places

### Negative

- **No manual tweaking**: Can't directly edit docker-compose.yml
- **Extra step required**: Must regenerate after config changes
- **Learning curve**: Users must understand "generated file" concept
- **Debugging harder**: Generated file harder to inspect (but commented)

### Mitigations

- `manage.sh apply` automates regeneration
- Header comment in generated file explains how it was created
- Generated file is human-readable (well-formatted, commented)
- .gitignore prevents accidental commits of machine-specific config
- README clearly explains the workflow
- manage.sh validates inputs before writing to config files

## Principles

- **Automation over manual work**: Generate don't duplicate
- **Single source of truth**: Config files are authoritative
- **Consistency enforcement**: One input, multiple outputs (always in sync)
- **Container-native design**: Don't rely on host OS features containers can't access
- **Fail-safe defaults**: Gitignore prevents mistakes
- **Explicit over implicit**: Header comment shows what to do

## For AI Assistants

CRITICAL RULES:
- NEVER suggest manually editing docker-compose.yml
- NEVER commit docker-compose.yml to git (it's in .gitignore)
- ALWAYS use `manage.sh add-user`, never manually edit users.conf
- ALWAYS use `manage.sh add-share`, never manually edit shares.conf (unless you're adding protocol field)
- ALWAYS run generate-compose.sh or `./manage.sh apply` after config changes
- When users ask "how do I add a user?", answer: use `manage.sh add-user`
- When users ask "how do I add a share?", answer: use `manage.sh add-share`
- When debugging, read docker-compose.yml to see what was generated, but modify the source config files

The workflow is:
1. Use manage.sh commands (add-user, add-share, etc.)
2. Run `./manage.sh apply`
3. Services restart with new config, both protocols in sync

## Why This Matters for Multi-Protocol Support

Without this architecture:
- User adds alice to Samba: `ACCOUNT_alice=alice;password123`
- User forgets to add alice to Netatalk: `ACCOUNT_alice=alice;1000;1000;password123`
- Result: alice can access via SMB but not AFP (or vice versa)
- Or: alice has different passwords on each protocol
- Or: alice has mismatched UIDs, causing file permission issues

With this architecture:
- User runs `./manage.sh add-user alice`
- Both protocols get alice with identical credentials automatically
- Impossible to have drift or inconsistency

## References

- `generate-compose.sh` (generation logic)
- `manage.sh apply` command (regenerates and restarts)
- `manage.sh add-user` command (single input for both protocols)
- `.gitignore` (excludes docker-compose.yml)
- ADR-004 (single config synced to multiple protocols)
- ADR-005 (explains absolute path strategy used in generation)
- ADR-006 (manage.sh wrapper for all operations)
