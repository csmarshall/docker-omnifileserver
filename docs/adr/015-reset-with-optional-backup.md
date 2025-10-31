# ADR-015: Reset Configuration with Optional Backup

**Status**: Accepted

**Date**: 2025-01-30

## Context

Users need a way to completely reset their OmniFileServer configuration to start fresh. This might be needed when:
- Testing the initial setup wizard multiple times
- Recovering from configuration errors
- Migrating to a different setup
- Decommissioning the server

We needed to decide:
1. Should reset be a separate command or integrated into init?
2. Should we offer backup before deletion?
3. What exactly should be reset?
4. How do we make it safe (prevent accidental data loss)?

## Considered Options

### Option 1: Separate Reset Command Only

```bash
./manage.sh reset
```

**Pros:**
- Explicit and clear action
- Follows Unix single-purpose command principle
- Easy to find in help text

**Cons:**
- Users might not discover it when running init on existing config
- Extra command to remember

### Option 2: Reset Only in Init Wizard

When init detects existing config, offer reset option.

**Pros:**
- Contextual - appears exactly when needed
- Fewer top-level commands
- Natural workflow: try init → see config exists → choose reset → continue

**Cons:**
- Not discoverable if user wants to reset without re-initializing
- Can't reset and stop (must continue to init)

### Option 3: Both Standalone Command AND Init Integration (CHOSEN)

Standalone command:
```bash
./manage.sh reset
```

Integrated into init wizard when existing config detected:
```
Warning: Configuration already exists!

Options:
  1. Cancel and keep existing configuration
  2. Reset configuration (with optional backup) and start fresh
  3. Continue anyway (may cause conflicts)

Choose [1]:
```

**Pros:**
- ✅ Discoverable both ways (help text + init wizard)
- ✅ Flexible: Can reset-and-stop OR reset-and-reinit
- ✅ Natural workflow when testing/redoing setup
- ✅ Explicit command for advanced users
- ✅ Contextual help for new users

**Cons:**
- Two ways to do the same thing (acceptable trade-off)

### Option 4: Alias Commands (reset-config, reset-init)

Rejected: Unnecessary complexity. A single `reset` command is clear enough.

## Decision

**Implement both standalone `reset` command AND integration into `init` wizard.**

### Reset Command Does:

1. **Confirmation**: Requires typing 'yes' (not just y/n)
2. **Optional Backup**: Prompts to create timestamped archive
3. **Archive Contents**: .env, .env.passwords, users.conf, shares.conf, docker-compose.yml, shares/, config/
4. **Archive Naming**: `omnifileserver-config-backup-YYYYMMDD-HHMMSS.tar.gz` (config-backup to distinguish from share data backups)
5. **Stop Containers**: Runs `docker compose down`
6. **Remove Files**: Deletes all config files
7. **Remove Directories**: Deletes shares/ and config/ directories
8. **Cleanup**: Removes .bak files from sed operations
9. **Restore Instructions**: Shows how to restore from archive if created

### Init Integration:

When `init` detects existing configuration:
- **Option 1**: Cancel (default, safe choice)
- **Option 2**: Reset with backup → continue to init
- **Option 3**: Continue anyway (may conflict)

## Implementation

```bash
# Command: reset
reset() {
    # Warning and confirmation (must type 'yes')
    # Optional backup prompt (Y/n)
    # Create timestamped tar.gz if yes
    # Stop containers
    # Remove all config files and directories
    # Show restore instructions
}

# In init() function
if [[ existing config detected ]]; then
    # Show 3 options
    # If option 2: call reset(), then continue init
fi
```

## Consequences

### Positive

- **Safe by default**: Requires explicit 'yes' confirmation
- **No data loss**: Optional backup preserves everything
- **Discoverable**: Two paths to find it (help, init)
- **Flexible**: Can reset-and-stop OR reset-and-reinit
- **Complete**: Removes everything for true fresh start
- **Timestamped backups**: Multiple backups don't conflict
- **Restore documentation**: Shows exact command to restore

### Negative

- **Two ways to reset**: Standalone + init (minor duplication)
- **Backup not automatic**: User must choose (but safer this way)

### Mitigations

- Help text documents both reset command and init integration
- Clear warnings before deletion
- Backup prompt defaults to Yes (safer choice)
- Restore instructions shown after reset

## Why Not Aliases?

Originally considered aliases like `reset-config` or `reset-init`, but:
- `reset` is clear enough on its own
- Aliases add command clutter
- Init integration covers the "reset and reinit" use case

## Safety Features

1. **Double confirmation**: Warning + 'yes' typing requirement
2. **List what will be deleted**: Shows exact consequences
3. **Backup prompt**: Defaults to creating backup (Y/n)
4. **Graceful failures**: Continues if containers already stopped
5. **Preserve backups**: Never deletes .tar.gz files

## Backup Format

Archive contains:
```
omnifileserver-config-backup-20250130-143522.tar.gz
├── .env
├── .env.passwords
├── users.conf
├── shares.conf
├── docker-compose.yml
├── shares/
│   └── (user data)
└── config/
    ├── samba/
    └── netatalk/
```

**Why tar.gz:**
- Standard Unix format
- Preserves permissions
- Single file (easy to move/store)
- Compressed (small)
- Built into all Unix systems (no dependencies)

**Why "config-backup" in filename:**
- Makes it clear this is configuration only, not share data
- Users may have separate backup strategies for share contents
- Prevents confusion about what's included in the archive

**Why not other formats:**
- `.zip`: Less standard on Unix, doesn't preserve permissions well
- `.tar.bz2`: Slower compression, tar.gz is fine for small configs
- Separate files: Hard to manage, easy to lose one
- Git commit: Assumes git repo exists, passwords shouldn't be committed

## Restore Process

Manual (documented in reset output):
```bash
cd /path/to/docker-omnifileserver
tar -xzf omnifileserver-config-backup-20250130-143522.tar.gz
./manage.sh apply  # Regenerate and restart
```

**Why manual restore:**
- Simple and transparent
- User sees exactly what's being restored
- Prevents accidental overwrites
- Standard tar command everyone knows

**Why not automated restore:**
- Would need another command (restore-backup)
- Risk of restoring over newer config
- User should consciously decide to restore
- One-liner is simple enough

## For AI Assistants

When users want to:
- **Start over**: Suggest `./manage.sh reset` or re-run `init` and choose option 2
- **Backup before changes**: Suggest running reset with backup (then restore if needed)
- **Test setup**: Show them reset → init workflow
- **Fix broken config**: Reset and start fresh rather than manual fixes

Don't suggest:
- Manual deletion of files (error-prone)
- Editing docker-compose.yml directly (violates ADR-008)
- Complex restore procedures (tar -xzf is enough)

## Principles

- **Safety first**: Confirm before destruction
- **Preserve data option**: Always offer backup
- **Complete reset**: All or nothing, no partial resets
- **Discoverable**: Available where users need it
- **Simple restore**: Standard tools, no custom logic

## References

- manage.sh reset() function (lines 696-803)
- manage.sh init() function (integration at lines 365-396)
- Help text documentation
- ADR-008: Generated docker-compose.yml (never manual editing)
- ADR-001: Separate password and config files (what gets backed up)
