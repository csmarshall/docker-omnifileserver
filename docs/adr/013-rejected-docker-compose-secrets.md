# ADR-013: Rejected Docker Compose Secrets for Password Management

**Status**: Rejected

**Date**: 2025-01-30

## Context

Passwords must be passed to Samba and Netatalk containers. Docker provides several mechanisms:
1. Environment variables (via `environment:` or `env_file:`)
2. Docker secrets (files mounted at `/run/secrets/`)
3. Volume-mounted config files

We needed a secure way to handle passwords without exposing them in plaintext in docker-compose.yml.

## The Problem with Environment Variables

Environment variables are visible in:
- `docker inspect` output
- Process listings (`ps aux | grep`)
- Container logs (if misconfigured)
- docker-compose.yml (if embedded directly)

However, ServerContainers images **only accept passwords via environment variables**:
- Samba: `ACCOUNT_username=username;password`
- Netatalk: `ACCOUNT_username=username;uid;gid;password`

No support for reading passwords from files.

## Docker Compose Secrets Approach

Docker Compose secrets could theoretically work like this:

```yaml
secrets:
  alice_password:
    file: ./.env.passwords
  bob_password:
    file: ./.env.passwords

services:
  samba:
    secrets:
      - alice_password
      - bob_password
```

Secrets are mounted as files in `/run/secrets/alice_password`, etc.

## Why This Doesn't Work

### Reason 1: ServerContainers Images Don't Support Secrets

The images expect passwords as **environment variables**, not files:
```bash
# What they need:
ACCOUNT_alice=alice;password123

# What secrets give you:
/run/secrets/alice_password containing "password123"
```

**There's no bridge between these two**. The images have no code to:
- Read `/run/secrets/` files
- Export their contents as environment variables
- Construct `ACCOUNT_*` variables from secret files

### Reason 2: No Native Secret-to-EnvVar Feature

Docker Compose **does not** automatically convert secrets to environment variables. You'd need:

Option A: Modify the container images
- Fork ServerContainers images
- Add entrypoint script to read secrets and export as env vars
- **Rejected**: We'd own the maintenance burden (see ADR-003)

Option B: Wrapper script
- Add a script that runs before Samba/Netatalk starts
- Reads secrets, exports env vars, then execs the real process
- **Rejected**: Complex, fragile, fights against image design

Option C: Sidecar container
- Separate container reads secrets and injects into main containers
- **Rejected**: Massive complexity for no real benefit

### Reason 3: Secrets Don't Solve the Real Problem

Even if we could use secrets:
- Secrets are just files (like `.env.passwords`)
- Still need to protect the secret source file (chmod 600)
- Still need to gitignore the secret file
- Still need to manage secret content somehow

**Secrets add complexity without meaningful security benefit for our use case.**

## Our Solution: Separate .env.passwords File

Instead of Docker secrets, we use:
1. **Separate password file**: `.env.passwords` (chmod 600, gitignored)
2. **CLI --env-file flags**: Load for variable substitution
3. **Variable references**: `${PASSWORD_username}` in docker-compose.yml

This provides:
- ✅ Passwords not in docker-compose.yml
- ✅ Separate file for passwords (chmod 600)
- ✅ Gitignore prevents commits
- ✅ **Works with ServerContainers images** (they get env vars)
- ✅ Simple, understandable approach

## Decision

**REJECTED**: Docker Compose secrets for password management.

**ACCEPTED**: Separate `.env.passwords` file with `--env-file` flags (see ADR-001, ADR-002).

## Consequences of Rejection

### What We Lose
- Can't use Docker Swarm secrets integration (but we don't use Swarm)
- Can't use Docker Enterprise secret management (not our target)
- Passwords visible in `docker inspect` (acceptable trade-off)

### What We Keep
- Simple, understandable approach
- Works with ServerContainers images as-is
- No custom image builds or wrapper scripts
- Easy for users to manage (just edit .env.passwords)

## When Secrets Might Be Reconsidered

If any of these change:
1. ServerContainers adds native secret file support
2. Docker Compose adds automatic secret-to-env conversion
3. We switch to images that support reading passwords from files
4. We move to Docker Swarm (unlikely for home use)

Until then, separate .env files are the right choice.

## Principles

- **Use tools as designed**: ServerContainers expects env vars, give them env vars
- **Appropriate security**: Perfect security is the enemy of usable security
- **Target audience matters**: Home users, not enterprises with compliance requirements
- **Pragmatism over purity**: Simple solution that works > complex solution that's "proper"

## Security Considerations

**Are env vars secure enough?**

For our target audience (home/small office):
- ✅ `.env.passwords` is chmod 600 (only owner can read)
- ✅ File is gitignored (won't be committed)
- ✅ Passwords not embedded in docker-compose.yml
- ✅ `docker inspect` requires root access on host
- ✅ Alternatives (secrets) don't work with our images anyway

**What about `docker inspect` showing env vars?**
- Requires root/sudo access to Docker socket
- If attacker has that, game over anyway (can access volumes, secrets, everything)
- Home environment: User is the admin, no untrusted users

**For paranoid users:**
- They can fork and modify ServerContainers images to read from files
- They can use vault solutions (HashiCorp Vault, etc.)
- But then they own the complexity

## For AI Assistants

When users ask about Docker secrets:
- Explain ServerContainers images don't support them
- Show them the `.env.passwords` approach
- Explain it's secure enough for home/small office use
- Don't suggest complex workarounds (wrapper scripts, image forks)

If user insists on secrets:
- Warn they'll need to modify/fork the container images
- Point them to ServerContainers source code
- Explain they'll own maintenance going forward

NEVER suggest:
- "Just add a wrapper script" (adds fragility)
- "Fork the images and modify" (defeats purpose of ADR-003)
- "Use a sidecar container" (massive complexity)

## References

- [Docker Compose Secrets Documentation](https://docs.docker.com/compose/use-secrets/)
- [ServerContainers Samba - env var docs](https://github.com/ServerContainers/samba)
- [ServerContainers Netatalk - env var docs](https://github.com/ServerContainers/netatalk)
- ADR-001 (Separate password and config files)
- ADR-002 (CLI --env-file flags for substitution)
- ADR-003 (Use ServerContainers images)
