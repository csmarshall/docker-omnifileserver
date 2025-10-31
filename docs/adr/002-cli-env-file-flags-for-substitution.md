# ADR-002: Use Docker Compose CLI --env-file Flags for Variable Substitution

**Status**: Accepted

**Date**: 2025-01-30

## Context

Docker Compose supports variable substitution (e.g., `${PASSWORD_charles}`) in docker-compose.yml files, but loading variables for substitution vs passing them to containers involves different mechanisms:

1. **Variable substitution** (parsing docker-compose.yml): Needs variables available when Docker Compose reads the file
2. **Container environment** (inside running container): Uses `env_file:` directive in docker-compose.yml

We needed both mechanisms because:
- Password variables must be substituted into `ACCOUNT_username=username;${PASSWORD_username}`
- The containers also need certain environment variables at runtime

## Considered Options

### Option 1: Single .env file (auto-read by Docker Compose)
- Docker Compose automatically reads `.env` from project directory
- Pro: Simple, no CLI flags needed
- Con: Can't separate passwords from general config

### Option 2: Merge all config into .env.passwords
- Put everything in one file, chmod 600
- Pro: Simple, single file
- Con: Loses benefit of separate config/secrets (can't share templates)

### Option 3: Use `env_file:` directive for substitution
- Attempted: `env_file: - .env.passwords` in docker-compose.yml
- Pro: Seems logical
- Con: **Doesn't work** - `env_file:` only loads vars INTO containers, not for parsing compose file

### Option 4: Use CLI --env-file flags (CHOSEN)
- `docker compose --env-file .env --env-file .env.passwords up`
- Pro: Loads multiple files for substitution, maintains separation
- Con: Must remember flags or use wrapper script

## Decision

Use Docker Compose CLI `--env-file` flags to load both configuration files for variable substitution:

```bash
DOCKER_COMPOSE="docker compose -f $COMPOSE_FILE --env-file $ENV_FILE --env-file $PASSWORDS_FILE"
```

All Docker Compose operations go through this command stored in the `DOCKER_COMPOSE` variable.

## Consequences

### Positive

- Maintains separation of passwords and config
- Both files available for `${VAR}` substitution
- Works with absolute paths (solves symlink directory issues)
- Clear and explicit about what files are being loaded
- Wrapper script makes it transparent to users

### Negative

- Can't run `docker compose` directly; must use `./manage.sh apply` or full command
- Slightly longer command line
- Less discoverable (users might not know about the flags)

### Mitigations

- `manage.sh` wrapper handles all Docker Compose operations
- Generated docker-compose.yml includes comment with full command
- Documentation clearly explains the approach

## Principles

- Explicit over implicit: Show clearly which files are loaded
- Wrapper for complexity: manage.sh hides implementation details
- Documentation in code: Comments in generated files

## For AI Assistants

When working with Docker Compose:
- NEVER use `docker compose` directly
- ALWAYS use `$DOCKER_COMPOSE` variable or `./manage.sh apply`
- The DOCKER_COMPOSE variable is defined early in manage.sh
- Generated docker-compose.yml header comment shows the full command
- Both --env-file flags are REQUIRED for password substitution to work

## References

- [Docker Compose environment variables](https://docs.docker.com/compose/environment-variables/)
- [Docker Compose --env-file flag](https://docs.docker.com/compose/environment-variables/set-environment-variables/)
- `manage.sh` lines 15-27 (DOCKER_COMPOSE variable definition)
- `generate-compose.sh` header comment generation
