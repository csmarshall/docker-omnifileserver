# ADR-004: Single Configuration Synced to Multiple Protocols

**Status**: Accepted

**Date**: 2025-01-30

## Context

Users want to share files via both SMB (Windows/modern macOS) and AFP (legacy macOS) protocols. Managing separate user lists and share definitions for each protocol would be error-prone and tedious.

## Decision

Use single source-of-truth configuration files that generate settings for both protocols:

1. **users.conf**: Single user list, synced to both Samba and Netatalk
   - Format: `username:uid:gid:description`
   - Passwords stored separately in `.env.passwords`
   - `generate-compose.sh` creates `ACCOUNT_username` env vars for both services

2. **shares.conf**: Single share list, synced to both protocols
   - Format: `name:path:permissions:users:comment`
   - `generate-compose.sh` creates both `SAMBA_VOLUME_CONFIG_*` and `AFP_VOLUME_CONFIG_*`

3. **manage.sh commands**: Work on both protocols simultaneously
   - `add-user` creates user in both services
   - `add-share` creates share in both services
   - Single `apply` command updates everything

## Consequences

### Positive

- Users defined once, work everywhere
- Shares defined once, appear in both protocols
- No sync issues or drift between protocols
- Simpler mental model for users
- Less configuration to maintain

### Negative

- Can't have protocol-specific users (same users in both)
- Can't have protocol-specific shares (same shares in both)
- If protocols need different settings, requires workarounds

### Future Considerations

- May add protocol filtering for shares later (e.g., `protocols:smb,afp` field)
- May add protocol-specific user features if needed
- Current design doesn't prevent these additions

## Principles

- Convention over configuration: Defaults work for common case
- DRY (Don't Repeat Yourself): Single source of truth
- Simplicity first: Add complexity only when needed

## For AI Assistants

When implementing user/share management:
- ALWAYS update both protocols when modifying users.conf or shares.conf
- The `generate_user_envs()` and `generate_share_envs()` functions handle the dual protocol logic
- DO NOT create separate config files for Samba vs Netatalk
- If adding protocol-specific features, do so via optional fields, not separate files

## References

- `users.conf` format
- `shares.conf` format
- `generate-compose.sh` functions: `generate_user_envs()`, `generate_share_envs()`
