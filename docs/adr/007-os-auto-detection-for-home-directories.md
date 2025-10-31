# ADR-007: OS Auto-Detection for Home Directories

**Status**: Accepted

**Date**: 2025-01-30

## Context

Users want to share their home directories via SMB and AFP, where each logged-in user sees their own home directory as a share. Different operating systems use different home directory locations:
- Linux: `/home/username`
- macOS: `/Users/username`
- Other Unix: varies

Requiring users to know and specify the correct path adds friction.

## Decision

Auto-detect the operating system using `uname` and set appropriate defaults:

```bash
case "$(uname)" in
    Darwin)  # macOS
        HOME_DIRECTORIES_BASE="/Users"
        ;;
    Linux)
        HOME_DIRECTORIES_BASE="/home"
        ;;
    *)
        HOME_DIRECTORIES_BASE="/home"  # fallback
        ;;
esac
```

**Command Usage**:
- `./manage.sh enable-homes` - Auto-detects OS, uses appropriate default
- `./manage.sh enable-homes /custom/path` - Manual override still supported

**Implementation in both**:
- `manage.sh` (for enable-homes command)
- `generate-compose.sh` (for default if not set in .env)

## Consequences

### Positive

- Zero-config for 99% of users (works out of the box)
- Explicit OS awareness (no guessing)
- Still allows manual override for edge cases
- Cross-platform script works identically on Linux and macOS

### Negative

- Assumes standard home directory locations
- May not work for custom setups (e.g., /Users mapped elsewhere)
- Adds OS-specific logic

### Mitigations

- Manual override available: `enable-homes /custom/path`
- Validates path exists before enabling
- Clear error message if path doesn't exist
- Documented in help text

## Principles

- Convention over configuration: Sensible defaults
- Cross-platform awareness: Detect and adapt
- Escape hatches: Always allow manual override

## For AI Assistants

When working with home directories:
- Trust the OS detection (it works for standard setups)
- If user reports issues, first check if `/home` or `/Users` exists
- For non-standard setups, advise manual path: `enable-homes /path`
- The HOME_DIRECTORIES_BASE setting is stored in .env after first enable-homes

Implementation details:
- Samba uses `%U` variable: `path=/home/%U` expands to `/home/alice` for user alice
- Netatalk uses `[Homes]` section with `basedir regex = /home`

## References

- `manage.sh` enable_homes() function
- `generate-compose.sh` OS detection for HOME_DIRECTORIES_BASE
- ServerContainers Samba docs on %U variable
- Netatalk afp.conf docs on [Homes] section
