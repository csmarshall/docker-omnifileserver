# ADR-012: Protocol-Specific Shares

**Status**: Accepted

**Date**: 2025-01-30

## Context

Initially, OmniFileServer synced all shares to both SMB and AFP protocols (see ADR-004). Every share appeared on both Windows/SMB clients and Mac/AFP clients.

However, users may want:
- **Windows-only shares**: Documents that Mac users shouldn't access
- **Mac-only shares**: Time Machine backups (only AFP supports Time Machine well)
- **Performance optimization**: Reduce config size by not advertising shares to protocols that won't use them
- **Access control by protocol**: Different shares for different client types

The question: Should we continue with "all shares on all protocols" or allow protocol selection per share?

## Problem Statement

**Use cases that don't work with synced shares**:

1. **Time Machine backups (AFP-only)**
   - Time Machine works best over AFP
   - No reason to advertise backup volume to SMB clients
   - Backup volume clutters Windows Network view

2. **Protocol-specific workflows**
   - Design team uses Macs exclusively → AFP-only share reduces clutter for Windows users
   - Finance team uses Windows → SMB-only share hides it from Mac users

3. **Mixed-environment security**
   - Contractor has Mac, should only see specific AFP shares
   - Internal team has Windows, different share access via SMB

## Decision

Add **protocols** field to shares.conf format:
```
name:path:permissions:users:comment:protocols
```

Where `protocols` can be:
- `smb,afp` - Share on both protocols (default for backward compatibility)
- `smb` - SMB/CIFS only (Windows, Linux, modern macOS)
- `afp` - AFP only (legacy macOS, Time Machine)

Implementation:
- `generate-compose.sh` filters shares based on protocol field
- Shares with `smb` appear only in Samba container config
- Shares with `afp` appear only in Netatalk container config
- Shares with `smb,afp` appear in both (default)
- Interactive wizard in `manage.sh add-share` prompts for protocol choice

## Consequences

### Positive

- **Time Machine support**: Can create AFP-only backup volumes
- **Reduced clutter**: Windows users don't see Mac-specific shares (and vice versa)
- **Flexible access control**: Different shares for different client types
- **Performance**: Slightly less config in each container
- **User choice**: Power users can optimize their setup
- **Still simple**: Default is both protocols (existing behavior)

### Negative

- **More complexity**: Shares can now be out of sync between protocols
- **User confusion**: "Why don't I see this share?" → Check protocols field
- **More configuration**: One more field to think about
- **Breaking change**: Old shares.conf format needs migration (but has default)

### Mitigations

- Default to `smb,afp` if field not specified (backward compatible)
- Interactive wizard makes protocol selection clear (menu with explanations)
- Help text and examples show all three options
- shares.conf header documents the field
- `manage.sh list-shares` shows protocols for each share

## Comparison to Alternatives

### Option 1: Separate config files (REJECTED)
Have `shares-smb.conf` and `shares-afp.conf`.

**Why rejected:**
- More files to manage
- Hard to maintain shares that should be on both
- Breaks single-source-of-truth principle
- More complex for common case (both protocols)

### Option 2: Always sync all shares (REJECTED)
Keep current behavior (ADR-004), don't add protocol field.

**Why rejected:**
- Doesn't support Time Machine use case
- Can't hide shares from specific protocols
- Less flexible for power users
- Still have problem mentioned in ADR-004

### Option 3: Add this feature (CHOSEN)
Single config file, optional protocols field, defaults to both.

**Why chosen:**
- Backward compatible (defaults to both)
- Supports Time Machine use case
- Simple for basic use (don't specify field)
- Powerful for advanced use (specify protocols)
- Maintains single config file

## Relation to ADR-004

This **extends** ADR-004 (Single Configuration Synced to Multiple Protocols):
- **ADR-004 principle**: Single config file for shares (MAINTAINED)
- **ADR-004 default**: Shares appear on both protocols (MAINTAINED as default)
- **New capability**: OPTIONAL filtering per share

We're not abandoning the sync principle - we're making it configurable per share while keeping sync as the default.

## Usage Examples

```bash
# Both protocols (default, backward compatible)
media:/shares/media:ro:all:Media Library:smb,afp

# SMB-only (Windows/Linux)
windows-docs:/shares/windows:rw:alice:Windows Documents:smb

# AFP-only (Time Machine)
timemachine:/shares/timemachine:rw:bob:Time Machine Backup:afp
```

## Principles

- **Opt-in complexity**: Default is simple (both protocols)
- **Backward compatibility**: Old config keeps working
- **User control**: Power users can optimize
- **Clear communication**: UI explains protocol choices

## For AI Assistants

When users ask about protocol-specific shares:
- Default is BOTH protocols (`smb,afp`)
- Use `smb` for Windows-specific shares
- Use `afp` for Mac-specific or Time Machine shares
- Empty/missing protocols field means both (backward compat)

When implementing:
- Filter in `generate_share_envs()` function
- Check `if [[ ! "${protocols}" =~ ${service_protocol} ]]; then continue; fi`
- Always provide protocol field in new shares (even if `smb,afp`)

Common mistakes:
- Writing `smb afp` instead of `smb,afp` (comma-separated!)
- Expecting old shares without field to break (they default to both)
- Creating share without protocols and wondering why it's on both (feature, not bug)

## References

- `shares.conf` format documentation
- `generate-compose.sh` generate_share_envs() function
- `manage.sh add-share` interactive wizard
- ADR-004 (Single Configuration Synced to Multiple Protocols)
