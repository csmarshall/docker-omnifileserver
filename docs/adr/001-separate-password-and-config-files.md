# ADR-001: Separate Password and Configuration Files

**Status**: Accepted

**Date**: 2025-01-30

## Context

The OmniFileServer requires both general configuration settings (server name, workgroup, log levels) and sensitive credentials (user passwords). Storing these together poses security risks:

- Configuration files are often tracked in git for deployment consistency
- Passwords should never be committed to version control
- File permissions need to differ (config can be world-readable, passwords must be restricted)
- Different backup/sharing strategies are needed for each type

## Decisions

1. **Split configuration into two files**:
   - `.env` - General configuration (chmod 644, optionally tracked in git)
   - `.env.passwords` - Passwords only (chmod 600, NEVER tracked in git)

2. **Store passwords in format**: `PASSWORD_username=password`

3. **Gitignore strategy**:
   - `.env.passwords` - Always ignored
   - `.env` - Ignored by default (contains machine-specific config)
   - `.env.example` - Tracked (template showing all available options)

4. **Load both files via Docker Compose CLI**:
   - `docker compose --env-file .env --env-file .env.passwords up`
   - This enables variable substitution for both general config and passwords

## Consequences

### Positive

- Passwords never accidentally committed to git
- Different permission models for different security needs
- Clear separation of concerns
- Easy to share configuration templates without exposing credentials
- Automated tools can safely process .env without seeing passwords

### Negative

- Two files to manage instead of one
- Must remember to use both --env-file flags
- Slightly more complex setup for new users

### Mitigations

- `manage.sh` wrapper handles both --env-file flags automatically
- Clear documentation in .env.example
- `manage.sh init` creates both files with correct permissions
- `.gitignore` provides safety net

## Principles

- Security by default: Passwords are isolated and protected
- Convenience through automation: manage.sh handles complexity
- Documentation over memorization: .env.example shows all options

## For AI Assistants

When modifying configuration:
- NEVER commit .env or .env.passwords files
- Always use manage.sh for password operations (creates secure prompts)
- When adding new config vars, update .env.example
- Ensure DOCKER_COMPOSE variable includes both --env-file flags

## References

- [Docker Compose environment variables documentation](https://docs.docker.com/compose/environment-variables/)
- `.gitignore` for ignore patterns
- `manage.sh` for implementation
