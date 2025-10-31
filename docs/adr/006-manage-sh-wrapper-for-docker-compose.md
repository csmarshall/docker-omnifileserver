# ADR-006: manage.sh Wrapper for Docker Compose Operations

**Status**: Accepted

**Date**: 2025-01-30

## Context

The system requires complex Docker Compose invocations with:
- Multiple --env-file flags
- Absolute path to compose file (-f flag)
- Pre-generation of docker-compose.yml from config files
- User/share management that updates config files

Direct docker-compose usage would require users to remember:
```bash
./generate-compose.sh && \
docker compose -f /full/path/docker-compose.yml \
  --env-file /full/path/.env \
  --env-file /full/path/.env.passwords \
  up -d
```

## Decision

Create `manage.sh` as the primary interface for all operations:

**User Management**:
- `./manage.sh add-user <username>` - Adds to users.conf + .env.passwords
- `./manage.sh remove-user <username>`
- `./manage.sh change-password <username>`
- `./manage.sh list-users`

**Share Management**:
- `./manage.sh add-share <name> <path> <perms> <users>`
- `./manage.sh remove-share <name>`
- `./manage.sh list-shares`

**Home Directories**:
- `./manage.sh enable-homes [path]` - Auto-detects OS if path not provided
- `./manage.sh disable-homes`

**Deployment**:
- `./manage.sh init` - Interactive setup wizard
- `./manage.sh apply` - Regenerate config and optionally restart services

Internal implementation:
```bash
DOCKER_COMPOSE="docker compose -f $COMPOSE_FILE --env-file $ENV_FILE --env-file $PASSWORDS_FILE"
```

## Consequences

### Positive

- Single command for all operations
- Hides Docker Compose complexity
- Ensures correct flags always used
- Validates inputs (checks files exist, permissions correct)
- Provides friendly error messages
- Interactive prompts for passwords (not in shell history)
- Auto-generates docker-compose.yml when needed

### Negative

- Users can't easily use docker-compose directly
- Need to learn manage.sh commands (but simpler than docker-compose flags)
- One more script to maintain

### Mitigations

- Comprehensive help: `./manage.sh help`
- Generated docker-compose.yml includes full command as comment
- Error messages suggest correct commands
- Can still use docker-compose directly if needed (command is documented)

## Principles

- User experience over implementation simplicity
- Convention over memorization
- Fail fast with helpful errors
- Security by default (password prompts, chmod 600)

## For AI Assistants

When implementing features:
- Add new operations to manage.sh, not separate scripts
- Always use $DOCKER_COMPOSE variable, never invoke docker-compose directly
- Use `error()` helper for fatal errors
- Use `success()` and `warn()` for colored output
- Always chmod 600 for .env.passwords
- Document new commands in `show_help()` function
- Use read -s for password prompts (hidden input)

## References

- `manage.sh` main dispatcher (case statement at end)
- `manage.sh` helper functions (error, success, warn)
- DOCKER_COMPOSE variable definition
