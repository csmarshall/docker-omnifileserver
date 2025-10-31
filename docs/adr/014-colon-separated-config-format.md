# ADR-014: Colon-Separated Config File Format

**Status**: Accepted

**Date**: 2025-01-30

## Context

OmniFileServer needs configuration files for:
- User definitions (users.conf)
- Share definitions (shares.conf)

These files are:
- Read by bash scripts (generate-compose.sh)
- Edited by users (directly or via manage.sh)
- Simple structured data (flat records)

We had to choose a format for these config files.

## Considered Options

### Option 1: JSON
```json
{
  "users": [
    {"username": "alice", "uid": 1000, "gid": 1000, "description": "Alice"}
  ],
  "shares": [
    {"name": "media", "path": "/shares/media", "permissions": "ro", "users": "all"}
  ]
}
```

**Pros:**
- Structured, well-defined
- Easy to parse in many languages
- Validation possible

**Cons:**
- **Verbose**: Lots of braces, quotes, commas
- **Not human-friendly**: Hard to read/write by hand
- **No comments**: Can't document inline
- **Bash parsing is painful**: Would need `jq` dependency
- **Overkill**: We have simple flat records

### Option 2: YAML
```yaml
users:
  - username: alice
    uid: 1000
    gid: 1000
    description: Alice

shares:
  - name: media
    path: /shares/media
    permissions: ro
    users: all
```

**Pros:**
- Human-readable
- Supports comments
- Less verbose than JSON

**Cons:**
- **Indentation-sensitive**: Easy to break
- **Bash parsing requires `yq` or Python**: External dependency
- **Overkill**: We don't need nesting
- **YAML complexity**: Multiple ways to represent same thing

### Option 3: TOML
```toml
[[users]]
username = "alice"
uid = 1000
gid = 1000
description = "Alice"

[[shares]]
name = "media"
path = "/shares/media"
permissions = "ro"
users = "all"
```

**Pros:**
- Clear structure
- Supports comments
- Easier than YAML

**Cons:**
- **Not widely known**: Less familiar to users
- **Bash parsing**: No native support, needs external tool
- **Still overkill**: We don't need the structure

### Option 4: Colon-separated (Unix-style) (CHOSEN)

**users.conf:**
```
# username:uid:gid:description
alice:1000:1000:Alice Smith
bob:1001:1001:Bob Jones
```

**shares.conf:**
```
# name:path:permissions:users:comment:protocols
media:/shares/media:ro:all:Media Library:smb,afp
docs:/shares/docs:rw:alice,bob:Documents:smb,afp
```

**Pros:**
- **Simple**: One line per record
- **Unix tradition**: Like /etc/passwd, /etc/group
- **Comments supported**: Lines starting with #
- **Bash-native parsing**: Just `while IFS=: read -r field1 field2...`
- **No dependencies**: No external tools needed
- **Human-readable**: Easy to understand
- **Easy to edit**: Simple text editor
- **Flat structure**: Perfect for our data model

**Cons:**
- **Delimiter limitations**: Can't use colon in field values
- **No nesting**: Can't represent complex structures
- **Manual parsing**: Need to handle quoting/escaping
- **No schema**: No built-in validation

## Decision

Use **colon-separated format** (like /etc/passwd) for users.conf and shares.conf.

Format rules:
- One record per line
- Fields separated by colons `:`
- Comments start with `#`
- Empty lines ignored
- First line is format documentation comment
- No escaping needed (fields don't contain colons)

Parsing in bash:
```bash
while IFS=: read -r username uid gid description; do
    # Process fields
done < users.conf
```

## Consequences

### Positive

- **Zero dependencies**: Works with pure bash
- **Simple to understand**: One line = one record
- **Easy to edit**: Any text editor
- **Fast parsing**: Bash native, no external process
- **Unix familiarity**: Follows /etc/passwd pattern
- **Comments**: Document format inline
- **Diff-friendly**: Git diffs show line-by-line changes
- **Grep-friendly**: Easy to search with grep

### Negative

- **No validation**: Syntax errors not caught until parse time
- **Delimiter conflicts**: Can't use `:` in field values (but we don't need to)
- **Manual parsing**: Have to write IFS logic
- **No schema**: Tools can't auto-validate structure

### Mitigations

- Header comments document format in each file
- manage.sh validates inputs before writing to files
- generate-compose.sh does validation during parse
- Example entries in header comments
- No need for colons in our field values (they're simple strings/paths)

## Why This Is Appropriate

Our data is:
- **Flat records**: No nesting or complex relationships
- **Fixed schema**: Same fields for all users, all shares
- **Simple types**: Strings, numbers, comma-separated lists
- **Small datasets**: Dozens of users/shares, not thousands
- **Append-mostly**: Rarely edited manually after setup

Colon-separated format is perfect for this use case.

## Historical Precedent

Unix systems have used colon-separated formats for decades:
- `/etc/passwd`: username:x:uid:gid:gecos:home:shell
- `/etc/group`: groupname:x:gid:users
- `/etc/fstab`: device:mountpoint:fstype:options:dump:pass

This format has proven:
- Reliable for system-critical config
- Easy for humans to read and edit
- Simple for tools to parse
- Adequate for flat structured data

## Field Order Matters

Fields are ordered for:
- **Logical grouping**: Related fields together
- **Required first**: Essential fields before optional ones
- **Most used first**: Common queries work without reading all fields

Example:
```
sharename:path:permissions:users:comment:protocols
^         ^    ^           ^     ^       ^
required  req  required    req   optional optional
```

Can `grep "^media:"` to find share by name without parsing all fields.

## Principles

- **Simplicity**: Use the simplest thing that works
- **Unix philosophy**: Follow proven patterns
- **No unnecessary dependencies**: Bash can parse natively
- **Human-readable**: Config should be understandable by eye

## For AI Assistants

When parsing config files:
- ALWAYS use `IFS=:` to split on colons
- ALWAYS use `read -r` to prevent backslash interpretation
- ALWAYS skip lines starting with `#` or empty lines
- Handle missing optional fields with defaults (e.g., `${protocols:-smb,afp}`)

When generating config lines:
- NEVER include colons in field values
- ALWAYS include all required fields
- Use empty string for missing optional fields, not omit them entirely
- Or handle missing fields with `${var:-default}` pattern

Common mistakes:
- Forgetting `-r` on read (backslashes get mangled)
- Not setting IFS (splits on spaces instead of colons)
- Not skipping comment lines (trying to parse them as data)
- Assuming all fields exist (handle missing optional fields)

Good pattern:
```bash
grep -v "^#" file.conf | grep -v "^$" | while IFS=: read -r field1 field2 field3; do
    field3="${field3:-default_value}"
    # Use fields
done
```

## When This Format Would Be Wrong

Don't use colon-separated if:
- Nested structures needed (use JSON/YAML)
- Field values contain colons naturally (use different delimiter)
- Need schema validation (use JSON Schema)
- Data is queried programmatically by external tools (use SQLite/JSON)
- Thousands of records (use database)

Our use case doesn't have any of these constraints.

## References

- `/etc/passwd` format (man 5 passwd)
- `/etc/group` format (man 5 group)
- users.conf header comments (format documentation)
- shares.conf header comments (format documentation)
- `generate-compose.sh` parsing logic
- ADR-011 (Bash scripts - why this format works well with Bash)
