# ADR-017: Auto-Detect UID/GID from Host System Users

**Status**: Accepted

**Date**: 2025-01-30

## Context

ADR-016 established that file share users must have UIDs/GIDs matching host filesystem ownership for containers to access files properly. This creates a usability problem:

**Manual UID/GID lookup is tedious:**
```bash
# User must do this every time
$ id alice
uid=501(alice) gid=20(staff)

# Then remember to type those numbers
$ ./manage.sh add-user alice 501 20
```

**Common mistakes:**
- Using default 1000:1000 when host user is 501:20 → permission denied
- Typos when manually entering UIDs
- Not understanding why permissions fail
- Forgetting to check host ownership before creating user

**The fundamental requirement (from ADR-016):**
Container UID must match host file ownership, or file access fails. We need to make this easy and correct by default.

## Decision

**Auto-detect UID/GID from host system when username matches.**

### How It Works

1. **User enters username** (e.g., `alice`)
2. **Script checks host system** using `id alice` command
3. **If user exists on host:**
   - Detect UID and GID (e.g., 501, 20)
   - Show message: `✓ Detected system user 'alice' (UID:501, GID:20)`
   - Use detected values as defaults
   - User can press Enter to accept or type custom values
4. **If user doesn't exist on host:**
   - Fall back to 1000:1000 as defaults
   - No error, silent fallback

### Implementation

```bash
detect_host_user() {
    local username="$1"
    if user_info=$(id -u "${username}" 2>/dev/null); then
        local uid="${user_info}"
        local gid=$(id -g "${username}" 2>/dev/null)
        echo "${uid} ${gid}"
        return 0
    fi
    return 1
}
```

Used in:
- `./manage.sh add-user <username>` - Auto-detects when username provided
- `./manage.sh init` - Auto-detects for first user

### User Experience

**Before (manual):**
```
Username: alice
UID (default: 1000): 501    ← User must look this up
GID (default: 1000): 20     ← And type it manually
```

**After (auto-detect):**
```
Username: alice

✓ Detected system user 'alice' (UID:501, GID:20)
Using detected values as defaults (press Enter to accept, or type custom values)

UID [501]: [Enter]
GID [20]: [Enter]
```

**Non-matching username:**
```
Username: fileserver

UID [1000]: [Enter]  ← Falls back to 1000, no detection message
GID [1000]: [Enter]
```

## Password Warning

Also added soft guidance about password separation:

```
💡 Note: This password is for file sharing access only.
   Consider using a different password than alice's system login (if any).
   File share passwords are stored in plaintext in .env.passwords (chmod 600).
```

**Why a suggestion, not a demand:**
- Users may have valid reasons to reuse passwords (home lab, testing)
- "Consider" is gentler than "You must"
- Explains *why* (plaintext storage) so users can decide
- Security is about informed choices, not mandatory rules

## Consequences

### Positive

- **Correct by default**: Most users just press Enter and get working permissions
- **Less confusion**: No need to understand `id` command or UID/GID concepts upfront
- **Fewer errors**: Automatic matching prevents most permission denied issues
- **Educational**: Shows detected values, teaches users about UID/GID
- **Still flexible**: Users can override if needed (service accounts, custom UIDs)
- **Password awareness**: Soft warning educates without being preachy

### Negative

- **Assumption risk**: Auto-detection assumes matching usernames means matching purpose
  - System user `alice` (UID 501) → File share user `alice` (UID 501)
  - This is correct 99% of the time, but not always
- **False confidence**: User might not realize UID matters if auto-detection "just works"
- **No validation**: Doesn't check if files actually exist with that ownership
- **Silent fallback**: If `id` command fails, falls back to 1000 without warning
  - This is intentional (not finding user isn't an error)
  - But user might expect detection to work when it didn't

### Mitigations

- Detection message clearly shows what was detected
- User can always override by typing different values
- Documentation explains UID/GID matching requirement (README, ADR-016)
- Error messages at runtime will still show permission denied if wrong UID

## When Auto-Detection Is Wrong

**Scenario 1: Different username, same UID**
```bash
# System user: bob (UID 501)
# Want file share user: media (UID 501 to access bob's files)
$ ./manage.sh add-user media 501 501  # Must manually specify
```

**Scenario 2: Service accounts**
```bash
# Want dedicated UID for Samba (e.g., 2000)
$ ./manage.sh add-user samba-service 2000 2000  # Must manually specify
```

**Scenario 3: Remote/NFS ownership**
```bash
# Files from NAS owned by UID 5001 (not a local user)
$ ./manage.sh add-user nas-user 5001 5001  # Must manually specify
```

**Scenario 4: User exists but wrong UID**
```bash
# System user alice (UID 1001), but files owned by UID 501
# Detected: 1001 (wrong!)
# Must override: ./manage.sh add-user alice 501 501
```

In all these cases, user can override the defaults. Auto-detection helps the common case, doesn't prevent the uncommon ones.

## Why This Doesn't Break Separation

**Important**: This doesn't violate the file share users ≠ system users principle.

**They remain separate:**
- **Authentication**: System users use PAM/SSH, file share users use Samba/AFP passwords
- **Password storage**: System passwords in `/etc/shadow` (hashed), file share in `.env.passwords` (plaintext)
- **User database**: System users in `/etc/passwd`, file share users in `users.conf`

**Only UID/GID are shared:**
- Numeric IDs for file permissions (kernel level)
- Both authentication systems use same UID → both can access same files
- This is *intentional* and *correct* for the use case

**The password warning makes this clear:**
- "This password is for file sharing access only"
- "Consider using a different password than alice's system login"
- Reinforces that these are separate authentication systems

## Alternative Approaches Considered

### Option 1: No Auto-Detection (Rejected)

Require users to always manually specify UID/GID.

**Rejected because:**
- Too tedious for common case
- High error rate (typos, wrong values)
- Poor user experience
- Doesn't guide users to correct configuration

### Option 2: Require Matching (Rejected)

Auto-detect, but *require* username to match host user.

```bash
if ! id "$username" &>/dev/null; then
    error "User '$username' does not exist on host system"
fi
```

**Rejected because:**
- Too restrictive (breaks service accounts, NFS users, custom UIDs)
- Forces specific naming conventions
- Doesn't allow flexibility for advanced use cases

### Option 3: Interactive UID Picker (Rejected)

Show list of all system users, let user pick one.

**Rejected because:**
- Complex UI for simple task
- Confusing (list of 50+ system users)
- Still doesn't handle non-system UIDs
- Over-engineered

### Option 4: Automatic UID Scanning (Rejected)

Scan all files in share directory, detect most common UID.

**Rejected because:**
- Share directory might not exist yet
- Multiple file owners (which one to pick?)
- Expensive operation (scanning filesystem)
- Confusing magic behavior

## Connection to ADR-016

ADR-016 established:
- All paths must be absolute (no ./shares/ assumptions)
- UIDs must match host file ownership
- Users must understand UID/GID alignment

ADR-017 makes this practical:
- Auto-detection reduces friction
- Correct defaults for common case
- Educational messaging reinforces concepts

Together: ADR-016 defines the requirement, ADR-017 makes it usable.

## Principles

- **Sensible defaults**: Correct configuration should be the easy path
- **Discoverability**: Show what's happening (detection message)
- **Flexibility**: Don't lock users into one approach
- **Education over enforcement**: Explain why, let users decide
- **Progressive disclosure**: Simple for beginners, powerful for experts

## For AI Assistants

When users create file share users:
- Auto-detection happens automatically (no action needed)
- If user complains about permission denied:
  - Check if detected UID matches file ownership
  - Suggest running `ls -ln /path/to/files` to see numeric ownership
  - Explain how to override with manual UID/GID

Don't suggest:
- "Just run as root" (defeats UID mapping)
- "Chmod 777 everything" (terrible security)
- "Create a system user" (not necessary)

Do suggest:
- "Check file ownership: ls -ln /your/share/path"
- "Override UID if needed: ./manage.sh add-user alice 501 20"
- "Use matching UIDs for file access"

## Security Note

**Password separation is a suggestion, not a mandate:**

The warning says "Consider using a different password" because:
- **Home/small office**: Often acceptable to reuse passwords
- **Testing/development**: Definitely acceptable
- **High security**: User should decide based on their threat model

**Why we explain instead of enforce:**
- Users resent mandatory arbitrary rules
- Understanding why makes better security decisions
- Home users are administrators of their own systems
- Enterprise users have their own policies

## Future Enhancements

**Possible improvements** (not implemented):

1. **Ownership validation**: Check if share path exists, verify file ownership matches configured UID
2. **Warning on mismatch**: If detected UID doesn't match file ownership, warn user
3. **NFS/remote detection**: Handle NFS ID mapping, remote filesystems
4. **Group membership**: Detect additional groups user belongs to

**Why not now:**
- Current implementation solves 90% of use cases
- Complexity vs benefit trade-off
- Can add later if users request it

## References

- ADR-016: Absolute Paths Only (No Project ./shares/ Directory)
- README.md: "Understanding Users and Permissions" section
- `id` command: man 1 id
- manage.sh: detect_host_user() function (lines 64-80)
- manage.sh: add-user command (uses auto-detection)
- manage.sh: init wizard Step 3 (uses auto-detection)
