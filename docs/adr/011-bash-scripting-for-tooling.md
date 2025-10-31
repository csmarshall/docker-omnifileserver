# ADR-011: Bash Scripts for Tooling

**Status**: Accepted

**Date**: 2025-01-30

## Context

OmniFileServer needs management tooling to:
- Add/remove users and shares
- Generate docker-compose.yml from config files
- Manage Docker Compose lifecycle (apply changes, restart services)
- Provide interactive wizards for setup

We had to choose a language/technology for these tools.

## Considered Options

### Option 1: Python
**Pros:**
- Rich standard library
- Easy string manipulation and file I/O
- Good for complex logic
- Many libraries available (PyYAML for YAML generation)

**Cons:**
- Requires Python runtime installed
- Version compatibility issues (Python 2 vs 3)
- Virtual environments add complexity
- Extra dependency for users to install
- Slower startup time than bash

### Option 2: Go
**Pros:**
- Fast execution
- Single static binary (easy distribution)
- Strong typing helps prevent bugs
- Good for complex applications

**Cons:**
- Requires Go compiler or distributing binaries
- Overkill for simple text file manipulation
- Longer development time
- Higher barrier for contributors
- Not naturally present on all systems

### Option 3: Node.js
**Pros:**
- Modern async handling
- Rich npm ecosystem
- JSON/YAML libraries

**Cons:**
- Requires Node.js runtime
- node_modules complexity
- Not typically installed on servers
- Slower startup for CLI tools
- npm dependency management overhead

### Option 4: Bash (CHOSEN)
**Pros:**
- **Already installed**: Present on all Linux/macOS/WSL systems
- **Zero dependencies**: No runtime to install
- **Shell-native**: Natural for running docker-compose commands
- **Fast startup**: Immediate execution
- **Simple distribution**: Just copy .sh files
- **Familiar**: Most server admins know bash
- **Direct OS interaction**: File ops, permissions, user prompts
- **Portable**: Works on macOS, Linux, BSD, WSL

**Cons:**
- Verbose for complex logic
- Error handling requires discipline
- No strong typing
- Harder to unit test

## Decision

Use **Bash scripts** for all tooling:
- `manage.sh` - main CLI interface
- `generate-compose.sh` - docker-compose.yml generator
- `config-defaults.sh` - configuration variable definitions

Requirements:
- Use `#!/bin/bash` (not `/bin/sh` - need bash features)
- Use `set -e` (exit on error)
- Run shellcheck for validation
- Quote all variables with `${var}` syntax
- Document complex logic with comments

## Consequences

### Positive

- **Zero installation**: Works out of the box on target platforms
- **Self-contained**: No package managers or dependencies
- **Fast**: Immediate execution, no runtime startup
- **Transparent**: Users can read and modify scripts
- **Shell-friendly**: Natural for Docker/system commands
- **Portable**: Works on macOS (Darwin) and Linux equally
- **Low barrier**: Easy for users to customize
- **Simple deployment**: `git clone` and run

### Negative

- **Limited structure**: No classes/modules like Python/Go
- **String manipulation**: More verbose than Python
- **Error prone**: Easy to make quoting/escaping mistakes
- **Testing**: Harder to unit test than compiled languages
- **Complex logic**: Gets unwieldy for very complex operations

### Mitigations

- Use shellcheck for validation (catches common errors)
- Keep scripts focused (manage.sh for CLI, generate-compose.sh for generation)
- Heavy use of functions for organization
- Extensive comments explaining complex logic
- Use `set -e` to fail fast on errors
- Quote all variable references
- Test on both macOS and Linux

## When This Choice Works

Bash is ideal for this project because:

1. **File manipulation focus**: Reading/writing simple config files
2. **Docker Compose wrapper**: Just need to run docker-compose with right flags
3. **System integration**: File permissions (chmod), directories (mkdir)
4. **Interactive prompts**: `read -p` for user input
5. **Target audience**: Users running servers already have bash
6. **Simple logic**: Not building complex algorithms or data structures

## When Bash Would Be Wrong

If project needed:
- Complex data transformations
- Database access
- Web APIs / HTTP requests
- Heavy parsing (JSON, XML)
- Concurrent operations
- Cross-platform GUI

We don't need any of these, so Bash is appropriate.

## Principles

- **Minimize dependencies**: Use what's already there
- **Appropriate tool for the job**: Bash excels at shell scripting
- **User convenience**: Zero-install is powerful
- **Transparency**: Scripts are readable and modifiable

## For AI Assistants

When modifying scripts:
- ALWAYS run shellcheck before committing
- ALWAYS quote variables: `"${var}"` not `$var`
- ALWAYS use `${var}` syntax, not `$var` (more explicit)
- Use `set -e` at top of scripts
- Use `local` for function variables
- Use `-r` flag on `read` to prevent backslash mangling
- Test on both macOS and Linux before claiming "it works"
- Keep functions focused and well-named
- Comment complex logic
- Use heredocs for multi-line text generation

Bash gotchas to avoid:
- Unquoted variables (word splitting)
- Missing `read -r` (backslashes get eaten)
- Forgetting `local` in functions (global scope pollution)
- Using `[` instead of `[[` (less robust)
- Not checking command exit codes

## Good Bash Practices Used

1. **Absolute paths**: `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`
2. **Error handling**: `set -e` and explicit error checking
3. **Functions**: Organized code, reusable
4. **Colored output**: Green for success, red for errors, yellow for warnings
5. **User prompts**: `read -s` for passwords (hidden input)
6. **Safe defaults**: Prompt before destructive operations
7. **Heredocs**: For generating multi-line files cleanly

## References

- [Bash Reference Manual](https://www.gnu.org/software/bash/manual/)
- [ShellCheck](https://www.shellcheck.net/) - used for validation
- [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- manage.sh (main implementation)
- generate-compose.sh (generation logic)
- ADR-005 (absolute paths with SCRIPT_DIR)
