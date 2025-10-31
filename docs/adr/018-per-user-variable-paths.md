# ADR-018: Per-User Variable Paths with %U

**Status**: Accepted

**Date**: 2025-01-30

## Context

Users need to create shares that map to different paths depending on who logs in. This is **different from home directories** in an important way:

**Home directories (existing feature):**
- Share name = username
- alice sees share "alice" → /home/alice
- bob sees share "bob" → /home/bob
- One share per user, name matches user

**Custom user-specific shares (this feature):**
- Share name = custom (e.g., "storage")
- alice sees share "storage" → /storage/users/alice
- bob sees share "storage" → /storage/users/bob
- One share visible to all users, content differs per user

**Use cases:**
- `/storage/users/%U` - Personal storage directories
- `/backup/users/%U` - User-specific backup locations
- `/projects/%U/work` - Per-user project workspaces
- `/media/personal/%U` - Individual media libraries

**The problem:**
- Samba uses `%U` for username variable
- Netatalk uses `$u` for username variable
- Different syntax for the same concept
- Path validation fails on variable paths

## Decision

**Support `%U` variable in share paths, automatically convert to `$u` for Netatalk.**

### How It Works

1. **User creates share with %U:**
   ```bash
   ./manage.sh add-share storage /storage/users/%U rw all "User Storage"
   ```

2. **System detects variable path:**
   - Sees `%U` in path
   - Validates base directory (`/storage/users`) exists
   - User subdirectories created manually by admin

3. **Generate config with correct syntax:**
   - **Samba:** `SAMBA_VOLUME_CONFIG_storage=/shares/storage/users/%U`
   - **Netatalk:** `AFP_VOLUME_CONFIG_storage=/shares/storage/users/$u`

4. **Users see different paths:**
   - alice logs in → `/storage/users/alice`
   - bob logs in → `/storage/users/bob`

### Variable Syntax

| Protocol | Variable | Example |
|----------|----------|---------|
| Samba (SMB) | `%U` | `/storage/users/%U` |
| Netatalk (AFP) | `$u` | `/storage/users/$u` |

**Note:** Users always use `%U` in the path. System converts to `$u` for Netatalk automatically.

## Implementation

### Path Validation

**Variable paths:**
```bash
# Path: /storage/users/%U
# Validate: /storage/users (base directory)
# Skip: /storage/users/alice (created by admin)
```

**Fixed paths:**
```bash
# Path: /mnt/storage/media
# Validate: /mnt/storage/media (full path)
```

### Volume Mounting

**Variable path:**
```yaml
# shares.conf: storage:/storage/users/%U:rw:all
volumes:
  - /storage/users:/shares/storage/users  # Mount base directory
environment:
  - SAMBA_VOLUME_CONFIG_storage=/shares/storage/users/%U
  - AFP_VOLUME_CONFIG_storage=/shares/storage/users/$u
```

**Fixed path:**
```yaml
# shares.conf: media:/mnt/storage/media:ro:all
volumes:
  - /mnt/storage/media:/shares/mnt/storage/media
environment:
  - SAMBA_VOLUME_CONFIG_media=/shares/mnt/storage/media
  - AFP_VOLUME_CONFIG_media=/shares/mnt/storage/media
```

### Code Changes

**generate-compose.sh:**
- `collect_absolute_paths()`: Skip paths containing `%U`
- `collect_variable_path_bases()`: Extract base directories from `%U` paths
- `generate_volume_mounts()`: Mount base directories for variable paths
- `generate_share_envs()`: Convert `%U` to `$u` for Netatalk

**manage.sh:**
- `add-share`: Detect `%U`, validate base directory only
- Shows message explaining variable expansion
- Reminds user to create subdirectories manually

## Consequences

### Positive

- **Flexible per-user storage**: One share, different content per user
- **Automatic variable conversion**: Users don't need to know protocol differences
- **Base path validation**: Catches missing parent directories
- **Clean syntax**: Standard `%U` variable (familiar from Samba docs)
- **Works alongside fixed paths**: Can mix variable and fixed shares

### Negative

- **Manual subdirectory creation**: Admin must create `/storage/users/alice`, `/storage/users/bob`
- **No automatic UID/GID detection**: Can't auto-detect ownership for variable paths
- **Only %U supported**: No other variables (e.g., `%G` for groups)
- **Base path limitation**: Must be `base/%U`, can't do `%U/subdir` or complex patterns

### Mitigations

- **Clear messaging**: Tool explains when it detects `%U`
- **Base directory validation**: Prevents missing parent directory
- **Documentation**: Help text shows examples
- **Error messages**: Tells user to create subdirectories

## Differences from Home Directories

| Feature | Home Directories | Variable Paths |
|---------|-----------------|----------------|
| **Share name** | = username | Custom name |
| **Visibility** | Only to that user | All users (content differs) |
| **Path pattern** | Fixed base + username | Custom pattern with %U |
| **Configuration** | `enable-homes /home` | `add-share storage /storage/%U` |
| **Samba config** | `homes` special share | Custom share with %U |
| **Number of shares** | One per user (auto) | One share (variable content) |

**When to use each:**

**Home directories:**
- Traditional Unix home directories
- User wants "their own" share
- `/home/alice` accessible as share "alice"

**Variable paths:**
- Custom storage structure
- Want specific share name (not username)
- Multiple variable shares per user
- Example: "storage" and "backup" both variable

## Examples

### Example 1: User Storage

```bash
# Setup
sudo mkdir -p /storage/users/{alice,bob}
sudo chown 1000:1000 /storage/users/alice
sudo chown 1001:1001 /storage/users/bob

./manage.sh add-user alice 1000 1000
./manage.sh add-user bob 1001 1001
./manage.sh add-share storage /storage/users/%U rw all "User Storage"
./manage.sh apply
```

**Result:**
- alice connects → sees "storage" → `/storage/users/alice`
- bob connects → sees "storage" → `/storage/users/bob`

### Example 2: Multiple Variable Shares

```bash
# Different per-user locations
./manage.sh add-share storage /storage/users/%U rw all "Storage"
./manage.sh add-share backup /backup/users/%U rw all "Backup"
./manage.sh add-share projects /home/%U/projects rw all "Projects"
```

**Result:**
- alice sees three shares: storage, backup, projects
- Each maps to different alice-specific path

### Example 3: Mixed Fixed and Variable

```bash
# Shared media (fixed) + personal storage (variable)
./manage.sh add-share media /mnt/media ro all "Shared Media"
./manage.sh add-share storage /storage/users/%U rw all "Personal Storage"
```

**Result:**
- Everyone sees same `/mnt/media` for "media" share
- Everyone sees their own `/storage/users/%U` for "storage" share

## Limitations

### Only %U Supported

Currently only username variable is supported. Other Samba variables not implemented:

- `%G` - Primary group
- `%H` - Home directory
- `%S` - Share name
- `%m` - Client machine name

**Why:** These are less common, add complexity. Can add later if needed.

### Pattern Limitations

Only supports pattern: `<base>/%U`

**Supported:**
- `/storage/users/%U` ✅
- `/home/%U` ✅
- `/backup/personal/%U` ✅

**Not supported:**
- `/%U/storage` ❌ (variable not at end)
- `/storage/%U/work/%U` ❌ (multiple variables)
- `/storage/%U-%G` ❌ (multiple variables)

**Why:** Base directory extraction assumes `/%U` at end. Could be enhanced later.

### No Automatic Subdirectory Creation

System does not create user subdirectories automatically.

**Admin must:**
```bash
sudo mkdir -p /storage/users/alice
sudo chown 1000:1000 /storage/users/alice
```

**Why:**
- Don't know which users need directories (users in users.conf might not all need storage)
- Don't know desired ownership/permissions
- Don't want to create directories speculatively
- Admin knows their directory structure best

**Future enhancement:** Could add `./manage.sh create-user-dirs <share>` command.

## Security Considerations

**Path traversal:**
- Variable expanded by Samba/Netatalk (trusted code)
- No user input directly in path expansion
- Username sanitized by authentication layer

**Permission boundaries:**
- Each user sees only their subdirectory
- Samba/Netatalk enforce access control
- Depends on filesystem permissions being correct

**Shared base directory:**
- `/storage/users` readable by all users
- Could see other users' directory names (not contents)
- If this is a concern, use separate base directories

## Alternatives Considered

### Option 1: Extend Home Directories Feature

Add ability to configure multiple home directory bases.

**Rejected because:**
- Home directories are conceptually "username shares"
- Variable paths are "custom name shares"
- Different use cases, mixing them is confusing
- Code would be more complex

### Option 2: Separate Variable Syntax

Require users to specify both Samba and Netatalk syntax.

```bash
./manage.sh add-share storage "/storage/%U;/storage/\$u" rw all
```

**Rejected because:**
- Too complex for users
- Easy to make mistakes
- Should be tool's job to handle protocol differences

### Option 3: Only Support Samba Variables

Don't convert for Netatalk, only works on SMB.

**Rejected because:**
- Breaks protocol parity
- Users expect both protocols to work
- Conversion is trivial (`%U` → `$u`)

### Option 4: No Variable Paths

Tell users to use home directories or create separate shares.

**Rejected because:**
- Home directories don't fit all use cases
- Creating per-user shares is tedious
- This is a common pattern in file servers

## For AI Assistants

When users want per-user paths:
- Ask if they want home directories or custom variable share
- Home directories: `./manage.sh enable-homes /home`
- Variable share: `./manage.sh add-share name /path/%U rw all`

Don't suggest:
- Creating separate share for each user (tedious)
- Manual docker-compose editing (violates ADR-008)
- Complex variable patterns (not supported)

Do suggest:
- Creating base directory first
- Creating user subdirectories with correct ownership
- Using `%U` syntax (tool converts to `$u` automatically)

## Future Enhancements

**Possible additions:**

1. **More variables**: `%G` (group), `%H` (home)
2. **Complex patterns**: `%U/work`, `%U-%G`
3. **Auto-create subdirs**: `./manage.sh create-user-dirs storage`
4. **Template support**: `./manage.sh add-share --template user-storage`

**Not implemented now:**
- Current feature solves 90% of use cases
- Can add if users request
- Keep it simple first

## Principles

- **Protocol abstraction**: Hide Samba vs Netatalk differences
- **Convention over configuration**: Use `%U`, tool figures out the rest
- **Validate what we can**: Check base directory, skip variable parts
- **Clear communication**: Tell user what's happening with variables

## References

- [Samba Variable Substitutions](https://www.samba.org/samba/docs/current/man-html/smb.conf.5.html#VARIABLESUBSTITUTIONS)
- [Netatalk Volume Variables](http://netatalk.sourceforge.net/3.1/htmldocs/afp.conf.5.html)
- manage.sh: add-share command (variable path detection)
- generate-compose.sh: collect_variable_path_bases()
- ADR-007: OS Auto-Detection for Home Directories (related feature)
