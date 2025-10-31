# ADR-016: Absolute Paths Only (No Project ./shares/ Directory)

**Status**: Accepted

**Date**: 2025-01-30

## Context

OmniFileServer currently supports two types of share paths:
1. **Relative paths**: Created under `./shares/` in the project directory (e.g., `media` → `./shares/media`)
2. **Absolute paths**: Existing directories on the host (e.g., `/storage/scanner`)

The default behavior assumes users want to store data under `./shares/` in the project install directory. This is **unrealistic**:
- Nobody organizes their data under a tool's installation directory
- Real data lives in: `/mnt/storage`, `/home/user/Documents`, `/media/external`, etc.
- External drives, NAS mounts, and existing file structures are already organized elsewhere

The relative path feature adds complexity:
- Two code paths (relative vs absolute)
- Confusing for users (what's the difference between "media" and "/mnt/media"?)
- Creates empty `./shares/` subdirectory that nobody uses
- Encourages poor data organization

## Decision

**Use absolute paths exclusively for all shares.**

### What This Means

1. **All share paths are fully qualified absolute paths**
   - `/storage/scanner`
   - `/mnt/media/movies`
   - `/home/alice/Documents`

2. **Docker mounts use same path inside container**
   - Host: `/storage/scanner` → Container: `/storage/scanner`
   - No path translation, no `/shares/` prefix

3. **Remove `./shares/` directory concept**
   - Don't create `./shares/` subdirectory
   - Don't suggest relative paths
   - Don't offer relative path option in wizards

4. **Path validation required**
   - Before adding share, verify path exists on host
   - Warn if path doesn't exist
   - Offer to create directory (with sudo if needed)

5. **UID/GID must match host filesystem ownership**
   - User configures `alice:1000:1000`
   - Host files at `/storage/scanner` must be owned by `1000:1000`
   - If mismatch, container can't access files
   - Must validate or warn users about ownership

## Why This Matters: UID/GID Mapping

**The fundamental problem:**

Docker containers run processes as specific UIDs/GIDs. When a container mounts a host directory, **file permissions are numeric, not named**.

Example:
```
Host filesystem:
  /storage/scanner owned by UID 1001, GID 1003

User config:
  alice:1000:1000

Container:
  Samba process runs as UID 1000
  Tries to access /storage/scanner (owned by 1001:1003)
  RESULT: Permission denied
```

**What we need:**
- Users must configure UIDs/GIDs that **match their host file ownership**
- Or users must `chown` the host directories to match configured UIDs
- System must validate/warn about mismatches

**Why we can't auto-fix this:**
- Changing host file ownership requires root/sudo
- Tool shouldn't modify system file ownership automatically
- User must consciously decide what UIDs to use

## Implementation Changes

### 1. Remove Relative Path Support

**Before:**
```bash
# shares.conf
media:/shares/media:rw:all:Media:smb,afp
```

**After:**
```bash
# shares.conf
media:/mnt/storage/media:rw:all:Media:smb,afp
scanner:/storage/scanner:ro:alice:Scanner:smb
```

### 2. Update Init Wizard

**Before:**
```
Directory name in shares/ (default: shared): media
→ Creates ./shares/media
→ Saves as /shares/media
```

**After:**
```
Absolute path on host: /mnt/storage/media
→ Validates path exists
→ Saves as /mnt/storage/media
→ Mounts as /mnt/storage/media:/mnt/storage/media
```

### 3. Update add-share Command

**Before:**
```bash
./manage.sh add-share media /shares/media rw all
./manage.sh add-share docs /storage/docs rw alice
```

**After:**
```bash
./manage.sh add-share media /mnt/storage/media rw all
./manage.sh add-share docs /storage/docs rw alice
# All paths must be absolute
```

### 4. UID/GID Validation (Future Enhancement)

Check if configured UID can access share path:
```bash
# When adding share, check ownership
stat -c '%u:%g' /storage/scanner  # Returns 1001:1003

# Compare to configured users
alice:1000:1000  # MISMATCH! Warn user
```

Show warning:
```
⚠️  Warning: Path ownership mismatch
  Path: /storage/scanner
  Owned by: 1001:1003
  User 'alice' configured as: 1000:1000

  Alice will not be able to access this share!

  Fix options:
    1. Reconfigure alice to use UID 1001, GID 1003
    2. Change path ownership: sudo chown -R 1000:1000 /storage/scanner
```

### 5. generate-compose.sh Changes

**Before:**
```yaml
volumes:
  - ./shares:/shares  # Mount entire ./shares directory
  - /storage/scanner:/storage/scanner  # Mount absolute paths individually
```

**After:**
```yaml
volumes:
  - /mnt/storage/media:/mnt/storage/media
  - /storage/scanner:/storage/scanner
  # No ./shares mount, all paths explicit
```

## Consequences

### Positive

- **Realistic workflow**: Users share existing data locations
- **No data migration**: Don't need to move files to ./shares/
- **Simpler mental model**: All paths are absolute, no special cases
- **Clearer permissions**: UID/GID must match host, explicit
- **Less code**: Remove relative path handling
- **Better errors**: Can validate paths exist before applying

### Negative

- **Breaking change**: Existing configs using `/shares/` prefix will break
- **Must understand UIDs**: Users must know file ownership on their system
- **More upfront setup**: Can't just accept defaults, must provide real paths
- **Permission complexity**: Users must manage host filesystem permissions

### Migration Path

For existing users with `/shares/` paths in shares.conf:
1. Check if they actually have data in `./shares/`
2. If yes: Document how to update to absolute paths
3. If no: Just update shares.conf to use absolute paths

Migration command (future):
```bash
./manage.sh migrate-to-absolute-paths
# Scans shares.conf for /shares/ paths
# Prompts for new absolute paths
# Updates config
```

## Why This Is The Right Choice

**The install directory is for code, not data:**
- `/opt/sw/omnifileserver/` contains: manage.sh, generate-compose.sh, configs
- `/mnt/storage/` contains: actual user files (movies, documents, photos)
- These should be separate

**Docker is already path-agnostic:**
- Can mount any host path to any container path
- No reason to force paths under ./shares/
- Direct mounting is simpler and more transparent

**Users already have organized data:**
- External drives: `/media/usb-drive/`
- NAS mounts: `/mnt/nas/`
- Home directories: `/home/alice/`
- Don't make them reorganize for this tool

## Principles

- **Work with existing data**: Don't force reorganization
- **Explicit over implicit**: Show real paths, not abstractions
- **Respect host filesystem**: UIDs must match, tool doesn't auto-chown
- **Unix philosophy**: Paths are paths, no magic

## For AI Assistants

When users ask about sharing directories:
- ALWAYS ask for absolute path on host
- NEVER suggest creating directories under ./shares/
- Validate path exists before saving to shares.conf
- Warn about UID/GID mismatches if detectable
- Show exact `chown` commands if permissions need fixing

Don't suggest:
- "Just put files in ./shares/" (wrong paradigm)
- "We'll copy your files to the project directory" (wasteful)
- "Symlink to ./shares/" (unnecessary indirection)

Do suggest:
- "What's the absolute path to your media? (e.g., /mnt/storage/movies)"
- "Check file ownership with: ls -ld /your/path"
- "Ensure UIDs match: sudo chown -R 1000:1000 /your/path"

## Open Questions

1. **Automatic UID detection**: Should we stat the path and suggest matching UID?
2. **Docker user namespaces**: Could we use user namespaces to remap UIDs? (Complex, probably not)
3. **Migration tool**: Worth building for existing users?
4. **Default first share in init**: Still offer to create one? Where?

## References

- ADR-005: Absolute Paths with SCRIPT_DIR (for tool files, not data)
- shares.conf format documentation
- generate-compose.sh volume mount logic
- Docker volume documentation: https://docs.docker.com/storage/volumes/
- Linux file permissions: man 2 stat, man 1 chown
