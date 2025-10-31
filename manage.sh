#!/bin/bash

set -e

# Prevent shell timeout during interactive prompts
unset TMOUT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USERS_CONF="$SCRIPT_DIR/users.conf"
SHARES_CONF="$SCRIPT_DIR/shares.conf"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
ENV_FILE="$SCRIPT_DIR/.env"
PASSWORDS_FILE="$SCRIPT_DIR/.env.passwords"

# Detect docker-compose vs docker compose and build full command with paths
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker-compose"
elif docker compose version &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker compose"
else
    echo "Error: Neither 'docker-compose' nor 'docker compose' found"
    echo "Please install Docker Compose: https://docs.docker.com/compose/install/"
    exit 1
fi

# Build full docker-compose command with explicit paths and env files
DOCKER_COMPOSE="$DOCKER_COMPOSE_CMD -f $COMPOSE_FILE --env-file $ENV_FILE --env-file $PASSWORDS_FILE"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
error() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

success() {
    echo -e "${GREEN}$1${NC}"
}

warn() {
    echo -e "${YELLOW}$1${NC}"
}

# Check if running as root
is_root() {
    [[ "${EUID:-$(id -u)}" -eq 0 ]]
}

# Show command with sudo prefix if not root
show_sudo_cmd() {
    local cmd="$1"
    if is_root; then
        echo "  ${cmd}"
    else
        echo "  sudo ${cmd}"
    fi
}

# Ensure config files exist
touch "$USERS_CONF" "$SHARES_CONF" "$ENV_FILE" "$PASSWORDS_FILE"

# Set secure permissions on passwords file
chmod 600 "$PASSWORDS_FILE" 2>/dev/null || true
# General env file can be more permissive
chmod 644 "$ENV_FILE" 2>/dev/null || true

# Command: add-user
add_user() {
    local username="$1"
    local uid="${2:-1000}"
    local gid="${3:-1000}"
    local description="${4:-$username}"

    if [[ -z "$username" ]]; then
        error "Usage: $0 add-user <username> [uid] [gid] [description]"
    fi

    # Check if user already exists
    if grep -q "^${username}:" "$USERS_CONF"; then
        error "User '$username' already exists"
    fi

    # Prompt for password securely
    echo -n "Enter password for user '$username': "
    read -s password
    echo
    echo -n "Confirm password: "
    read -s password_confirm
    echo

    if [[ "$password" != "$password_confirm" ]]; then
        error "Passwords do not match"
    fi

    if [[ -z "$password" ]]; then
        error "Password cannot be empty"
    fi

    # Add user to config (without password)
    echo "$username:$uid:$gid:$description" >> "$USERS_CONF"

    # Add password to .env.passwords file
    echo "" >> "$PASSWORDS_FILE"
    echo "# User: $username" >> "$PASSWORDS_FILE"
    echo "PASSWORD_${username}=${password}" >> "$PASSWORDS_FILE"

    success "Added user '$username' (UID:$uid, GID:$gid)"
    warn "Password stored securely in .env.passwords file (chmod 600)"
    warn "Run '$0 apply' to apply changes"
}

# Command: remove-user
remove_user() {
    local username="$1"

    if [[ -z "$username" ]]; then
        error "Usage: $0 remove-user <username>"
    fi

    # Check if user exists
    if ! grep -q "^${username}:" "$USERS_CONF"; then
        error "User '$username' not found"
    fi

    # Remove user from config
    sed -i.bak "/^${username}:/d" "$USERS_CONF"

    # Remove password from .env.passwords file
    if [[ -f "$PASSWORDS_FILE" ]]; then
        sed -i.bak "/^# User: ${username}$/d" "$PASSWORDS_FILE"
        sed -i.bak "/^PASSWORD_${username}=/d" "$PASSWORDS_FILE"
    fi

    success "Removed user '$username'"
    warn "Run '$0 apply' to apply changes"
}

# Command: list-users
list_users() {
    echo "Current Users:"
    echo "---"
    if [[ -s "$USERS_CONF" ]]; then
        grep -v "^#" "$USERS_CONF" | grep -v "^$" | while IFS=: read -r username uid gid description; do
            echo "  $username (UID:$uid, GID:$gid) - $description"
        done
    else
        echo "  (no users configured)"
    fi
}

# Command: change-password
change_password() {
    local username="$1"

    if [[ -z "$username" ]]; then
        error "Usage: $0 change-password <username>"
    fi

    # Check if user exists
    if ! grep -q "^${username}:" "$USERS_CONF"; then
        error "User '$username' not found"
    fi

    # Prompt for new password securely
    echo -n "Enter new password for user '$username': "
    read -s password
    echo
    echo -n "Confirm new password: "
    read -s password_confirm
    echo

    if [[ "$password" != "$password_confirm" ]]; then
        error "Passwords do not match"
    fi

    if [[ -z "$password" ]]; then
        error "Password cannot be empty"
    fi

    # Update password in .env.passwords file
    if [[ -f "$PASSWORDS_FILE" ]]; then
        # Remove old password
        sed -i.bak "/^PASSWORD_${username}=/d" "$PASSWORDS_FILE"
        # Add new password
        echo "PASSWORD_${username}=${password}" >> "$PASSWORDS_FILE"
        success "Password updated for user '$username'"
        warn "Run '$0 apply' to apply changes"
    else
        error "Password file not found: $PASSWORDS_FILE"
    fi
}

# Command: add-share
add_share() {
    local name="$1"
    local path="$2"
    local permissions="$3"
    local users="$4"
    local comment="$5"
    local protocols="$6"

    # Interactive wizard mode if no arguments provided
    if [[ -z "$name" ]]; then
        echo "╔════════════════════════════════════════════════════════════╗"
        echo "║              Add New Share - Interactive Wizard           ║"
        echo "╚════════════════════════════════════════════════════════════╝"
        echo ""

        # Share name
        read -r -p "Share name (no spaces): " name
        if [[ -z "${name}" ]]; then
            error "Share name cannot be empty"
        fi

        # Check if share already exists
        if grep -q "^${name}:" "${SHARES_CONF}"; then
            error "Share '${name}' already exists"
        fi

        # Path
        echo ""
        echo "Share path options:"
        echo "  1. Relative path under ./shares/ (e.g., /shares/documents)"
        echo "  2. Absolute path to existing directory (e.g., /mnt/storage)"
        read -r -p "Enter path: " path
        if [[ -z "${path}" ]]; then
            error "Path cannot be empty"
        fi

        # Permissions
        echo ""
        read -r -p "Permissions (rw=read-write, ro=read-only) [rw]: " permissions
        permissions="${permissions:-rw}"
        if [[ "${permissions}" != "rw" && "${permissions}" != "ro" ]]; then
            error "Permissions must be 'rw' or 'ro'"
        fi

        # Users
        echo ""
        read -r -p "Allowed users (comma-separated or 'all'): " users
        if [[ -z "${users}" ]]; then
            error "Users cannot be empty"
        fi

        # Comment
        echo ""
        read -r -p "Description [${name}]: " comment
        comment="${comment:-${name}}"

        # Protocols
        echo ""
        echo "Select protocols for this share:"
        echo "  1. Both SMB and AFP (Windows + Mac)"
        echo "  2. SMB only (Windows/Linux)"
        echo "  3. AFP only (Mac)"
        read -r -p "Choice [1]: " protocol_choice
        protocol_choice="${protocol_choice:-1}"

        case "${protocol_choice}" in
            1)
                protocols="smb,afp"
                ;;
            2)
                protocols="smb"
                ;;
            3)
                protocols="afp"
                ;;
            *)
                error "Invalid choice. Must be 1, 2, or 3"
                ;;
        esac

        echo ""
        echo "Summary:"
        echo "  Name: ${name}"
        echo "  Path: ${path}"
        echo "  Permissions: ${permissions}"
        echo "  Users: ${users}"
        echo "  Description: ${comment}"
        echo "  Protocols: ${protocols}"
        echo ""
        read -r -p "Add this share? (Y/n) " -n 1
        echo
        if [[ ${REPLY} =~ ^[Nn]$ ]]; then
            warn "Share not added"
            return
        fi
    else
        # Command-line mode - validate all required parameters
        if [[ -z "${path}" || -z "${permissions}" || -z "${users}" ]]; then
            error "Usage: $0 add-share <name> <path> <rw|ro> <users> [comment] [protocols]\n\nOr run without arguments for interactive wizard:\n  $0 add-share"
        fi

        comment="${comment:-${name}}"
        protocols="${protocols:-smb,afp}"

        # Validate permissions
        if [[ "${permissions}" != "rw" && "${permissions}" != "ro" ]]; then
            error "Permissions must be 'rw' or 'ro'"
        fi

        # Check if share already exists
        if grep -q "^${name}:" "${SHARES_CONF}"; then
            error "Share '${name}' already exists"
        fi
    fi

    # Check if path is absolute
    if [[ "${path}" =~ ^/ ]]; then
        # Absolute path - verify it exists
        if [[ ! -d "${path}" ]]; then
            warn "Warning: Absolute path '${path}' does not exist"
            read -r -p "Create it now? (y/N) " -n 1
            echo
            if [[ ${REPLY} =~ ^[Yy]$ ]]; then
                mkdir -p "${path}" || error "Failed to create directory '${path}'"
                success "Created directory '${path}'"
            else
                warn "Directory not created. Ensure it exists before starting services."
            fi
        fi
    else
        # Relative path - should be under ./shares/
        if [[ ! "${path}" =~ ^/shares/ ]]; then
            warn "Warning: Relative path should typically be /shares/something"
        fi
    fi

    # Add share to config
    echo "${name}:${path}:${permissions}:${users}:${comment}:${protocols}" >> "${SHARES_CONF}"
    success "Added share '${name}' -> ${path} (${permissions}, protocols: ${protocols})"
    warn "Run '$0 apply' to apply changes"
}

# Command: remove-share
remove_share() {
    local name="$1"

    if [[ -z "$name" ]]; then
        error "Usage: $0 remove-share <name>"
    fi

    # Check if share exists
    if ! grep -q "^${name}:" "$SHARES_CONF"; then
        error "Share '$name' not found"
    fi

    # Remove share from config
    sed -i.bak "/^${name}:/d" "$SHARES_CONF"
    success "Removed share '$name'"
    warn "Run '$0 apply' to apply changes"
}

# Command: list-shares
list_shares() {
    echo "Current Shares:"
    echo "---"
    if [[ -s "$SHARES_CONF" ]]; then
        grep -v "^#" "$SHARES_CONF" | grep -v "^$" | while IFS=: read -r name path permissions users comment; do
            echo "  $name -> $path [$permissions] (users: $users) - $comment"
        done
    else
        echo "  (no shares configured)"
    fi
}

# Command: init
init() {
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║          Home File Server - Initial Setup                 ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    # Check if already initialized
    if [[ -f "$COMPOSE_FILE" ]] || grep -q "^[^#]" "$USERS_CONF" 2>/dev/null || grep -q "^[^#]" "$SHARES_CONF" 2>/dev/null; then
        warn "Warning: Configuration already exists!"
        echo ""
        echo "Options:"
        echo "  1. Cancel and keep existing configuration"
        echo "  2. Reset configuration (with optional backup) and start fresh"
        echo "  3. Continue anyway (may cause conflicts)"
        echo ""
        read -p "Choose [1]: " -n 1 -r
        echo

        case "${REPLY:-1}" in
            1|"")
                echo "Initialization cancelled."
                exit 0
                ;;
            2)
                echo ""
                reset
                echo ""
                echo "Continuing with initialization..."
                echo ""
                ;;
            3)
                warn "Continuing with existing configuration..."
                ;;
            *)
                error "Invalid choice"
                ;;
        esac
    fi

    echo "This wizard will help you set up your file server."
    echo ""

    # Step 1: Create directories
    echo "Step 1: Creating directory structure..."
    mkdir -p "$SCRIPT_DIR/shares"
    mkdir -p "$SCRIPT_DIR/config/samba"
    mkdir -p "$SCRIPT_DIR/config/netatalk"
    success "✓ Directories created"
    echo ""

    # Step 2: Server configuration
    echo "Step 2: Configure server settings"
    echo "Press Enter to accept defaults shown in [brackets]"
    echo ""

    # Source configuration defaults
    source "$SCRIPT_DIR/config-defaults.sh"

    # Start .env file
    cat > "$ENV_FILE" << 'ENVEOF'
# Server Configuration
# Generated by manage.sh init on $(date)
ENVEOF

    # Iterate through config variables and prompt for each
    for config in "${CONFIG_VARS[@]}"; do
        IFS='|' read -r name default desc options <<< "$config"

        # Evaluate default (expand variables like ${SERVER_NAME})
        # shellcheck disable=SC2154
        eval "default_value=\"${default}\""

        # Show description and options if available
        echo ""
        echo "${desc}"
        if [[ -n "${options}" ]]; then
            echo "Options: ${options}"
        fi

        # Prompt with default
        read -r -p "${name} [${default_value}]: " user_value

        # Use default if empty
        final_value="${user_value:-${default_value}}"

        # Append to .env (quote value to handle spaces)
        echo "${name}=\"${final_value}\"" >> "$ENV_FILE"
    done

    echo "" >> "$ENV_FILE"
    success "✓ Configuration saved to .env"
    echo ""

    # Step 3: First user
    echo "Step 3: Create your first user account"
    echo "This user will have access to the file shares."
    echo ""
    read -p "Username: " first_user

    if [[ -z "$first_user" ]]; then
        error "Username cannot be empty"
    fi

    read -p "UID (default: 1000): " first_uid
    first_uid="${first_uid:-1000}"

    read -p "GID (default: 1000): " first_gid
    first_gid="${first_gid:-1000}"

    read -p "Description (default: $first_user): " first_desc
    first_desc="${first_desc:-$first_user}"

    # Get password
    echo -n "Password: "
    read -s first_password
    echo
    echo -n "Confirm password: "
    read -s first_password_confirm
    echo

    if [[ "$first_password" != "$first_password_confirm" ]]; then
        error "Passwords do not match"
    fi

    if [[ -z "$first_password" ]]; then
        error "Password cannot be empty"
    fi

    # Save user
    echo "$first_user:$first_uid:$first_gid:$first_desc" >> "$USERS_CONF"
    echo "" >> "$PASSWORDS_FILE"
    echo "# User: $first_user" >> "$PASSWORDS_FILE"
    echo "PASSWORD_${first_user}=${first_password}" >> "$PASSWORDS_FILE"

    success "✓ User '$first_user' created"
    echo ""

    # Step 4: First share
    echo "Step 4: Create your first share"
    echo ""
    read -p "Share name (e.g., 'shared'): " first_share

    if [[ -z "$first_share" ]]; then
        error "Share name cannot be empty"
    fi

    echo ""
    echo "Enter the absolute path to the directory you want to share."
    echo "Examples: /mnt/storage/media, /storage/scanner, /home/alice/Documents"
    read -p "Absolute path on host: " first_path

    if [[ -z "$first_path" ]]; then
        error "Path cannot be empty"
    fi

    # Validate it's an absolute path
    if [[ ! "${first_path}" =~ ^/ ]]; then
        error "Path must be absolute (start with /). Got: ${first_path}"
    fi

    echo "Permissions:"
    echo "  rw - Read/write access"
    echo "  ro - Read-only access"
    read -p "Permissions (rw/ro, default: rw): " first_perms
    first_perms="${first_perms:-rw}"

    if [[ "$first_perms" != "rw" && "$first_perms" != "ro" ]]; then
        error "Permissions must be 'rw' or 'ro'"
    fi

    read -r -p "Description (default: ${first_share}): " first_comment
    first_comment="${first_comment:-${first_share}}"

    # Protocol selection
    echo ""
    echo "Select protocols for this share:"
    echo "  1. Both SMB and AFP (Windows + Mac)"
    echo "  2. SMB only (Windows/Linux)"
    echo "  3. AFP only (Mac)"
    read -r -p "Choice [1]: " first_protocol_choice
    first_protocol_choice="${first_protocol_choice:-1}"

    local first_protocols
    case "${first_protocol_choice}" in
        1)
            first_protocols="smb,afp"
            ;;
        2)
            first_protocols="smb"
            ;;
        3)
            first_protocols="afp"
            ;;
        *)
            warn "Invalid choice. Defaulting to both protocols (smb,afp)"
            first_protocols="smb,afp"
            ;;
    esac

    # Validate path exists, offer to create if not
    if [[ ! -d "${first_path}" ]]; then
        warn "Warning: Path '${first_path}' does not exist"
        read -r -p "Create it now? (y/N) " -n 1
        echo
        if [[ ${REPLY} =~ ^[Yy]$ ]]; then
            if mkdir -p "${first_path}" 2>/dev/null; then
                success "✓ Created directory '${first_path}'"
            else
                warn "Failed to create directory (permission denied). Run these commands:"
                show_sudo_cmd "mkdir -p ${first_path}"
                show_sudo_cmd "chown -R ${first_uid}:${first_gid} ${first_path}"
                echo ""
                warn "Create the directory manually, then run '$0 init' again or continue anyway."
            fi
        else
            warn "Directory not created. Ensure it exists before starting services."
        fi
    fi

    # Save share (path is used as-is for both host and container)
    echo "${first_share}:${first_path}:${first_perms}:${first_user}:${first_comment}:${first_protocols}" >> "${SHARES_CONF}"
    success "✓ Share '${first_share}' -> ${first_path} (protocols: ${first_protocols})"
    echo ""

    # Step 5: Set permissions
    echo "Step 5: Setting permissions..."
    echo ""
    echo "The configured user UID/GID must match the file ownership on the host."
    echo "User: ${first_user} (UID:${first_uid}, GID:${first_gid})"
    echo "Path: ${first_path}"
    echo ""

    # Try to set permissions
    if [[ -d "${first_path}" ]]; then
        if chown -R "${first_uid}:${first_gid}" "${first_path}" 2>/dev/null; then
            chmod 755 "${first_path}"
            success "✓ Permissions set successfully"
        else
            warn "Could not set ownership (permission denied). Run these commands:"
            show_sudo_cmd "chown -R ${first_uid}:${first_gid} ${first_path}"
            show_sudo_cmd "chmod 755 ${first_path}"
        fi
    else
        warn "Directory does not exist yet. Set permissions after creating it:"
        show_sudo_cmd "chown -R ${first_uid}:${first_gid} ${first_path}"
        show_sudo_cmd "chmod 755 ${first_path}"
    fi
    echo ""

    # Step 6: Generate config
    echo "Step 6: Generating docker-compose.yml..."
    if ! "$SCRIPT_DIR/generate-compose.sh"; then
        error "Failed to generate docker-compose.yml"
    fi
    success "✓ Configuration generated at $SCRIPT_DIR/docker-compose.yml"
    echo ""
    echo "💡 Tip: To organize files by type, you can symlink the compose file:"
    echo "   mkdir -p /opt/sw/docker-compose/omnifileserver"
    echo "   ln -s $SCRIPT_DIR/docker-compose.yml /opt/sw/docker-compose/omnifileserver/"
    echo ""

    # Step 7: Start services
    echo "Step 7: Start Docker services"
    read -p "Start services now? (Y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        cd "$SCRIPT_DIR"
        echo "Running: $DOCKER_COMPOSE up -d"
        if $DOCKER_COMPOSE up -d; then
            success "✓ Services started"
            echo ""

            # Show status
            echo "Checking status..."
            sleep 2
            echo "Running: $DOCKER_COMPOSE ps"
            $DOCKER_COMPOSE ps
        else
            warn "Failed to start services (permission denied). Run this command:"
            show_sudo_cmd "$DOCKER_COMPOSE up -d"
        fi
    else
        warn "Services not started. Run '$DOCKER_COMPOSE up -d' when ready."
    fi

    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                    Setup Complete! 🎉                      ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Your file server is ready!"
    echo ""
    echo "Server Name: $(hostname) File Server"
    echo "User: $first_user"
    echo "Share: $first_share (at /shares/$first_dir)"
    echo ""
    echo "Next steps:"
    echo "  • Connect from clients using smb://$(hostname) or afp://$(hostname)"
    echo "  • Add more users: ./manage.sh add-user <username>"
    echo "  • Add more shares: ./manage.sh add-share <name> <path> <rw|ro> <users>"
    echo "  • View logs: docker-compose logs -f"
    echo ""
}

# Command: enable-homes
enable_homes() {
    local base_path="${1}"

    # Auto-detect OS and set default home directory if not provided
    if [[ -z "${base_path}" ]]; then
        local os_type
        os_type=$(uname)
        case "${os_type}" in
            Darwin)
                base_path="/Users"
                ;;
            Linux)
                base_path="/home"
                ;;
            *)
                error "Unknown OS type: ${os_type}\nPlease specify home directory manually:\n  $0 enable-homes <base-path>"
                ;;
        esac
        echo "Auto-detected OS: ${os_type}"
        echo "Using default home directory: ${base_path}"
        echo ""
    fi

    # Validate path exists
    if [[ ! -d "${base_path}" ]]; then
        error "Directory '${base_path}' does not exist"
    fi

    echo "Enabling home directory shares..."
    echo "Base path: ${base_path}"
    echo ""

    # Update or add to .env file
    if grep -q "^HOME_DIRECTORIES_ENABLED=" "${ENV_FILE}" 2>/dev/null; then
        sed -i.bak "s|^HOME_DIRECTORIES_ENABLED=.*|HOME_DIRECTORIES_ENABLED=yes|" "${ENV_FILE}"
        sed -i.bak "s|^HOME_DIRECTORIES_BASE=.*|HOME_DIRECTORIES_BASE=${base_path}|" "${ENV_FILE}"
    else
        {
            echo ""
            echo "# Home directory shares"
            echo "HOME_DIRECTORIES_ENABLED=yes"
            echo "HOME_DIRECTORIES_BASE=${base_path}"
        } >> "${ENV_FILE}"
    fi

    success "✓ Home directories enabled"
    echo ""
    echo "Each user will see their home directory as a share:"
    echo "  - Samba (SMB): \\\\\\\\server\\\\username"
    echo "  - Netatalk (AFP): afp://server/username"
    echo ""
    warn "Run '$0 apply' to regenerate configuration and restart services"
}

# Command: disable-homes
disable_homes() {
    echo "Disabling home directory shares..."

    if grep -q "^HOME_DIRECTORIES_ENABLED=" "${ENV_FILE}" 2>/dev/null; then
        sed -i.bak "s|^HOME_DIRECTORIES_ENABLED=.*|HOME_DIRECTORIES_ENABLED=no|" "${ENV_FILE}"
        success "✓ Home directories disabled"
    else
        warn "Home directories are not currently enabled"
    fi

    echo ""
    warn "Run '$0 apply' to regenerate configuration and restart services"
}

# Command: apply
apply() {
    echo "Generating docker-compose.yml from configuration..."

    if ! "$SCRIPT_DIR/generate-compose.sh"; then
        error "Failed to generate docker-compose.yml"
    fi

    success "Generated docker-compose.yml at $SCRIPT_DIR/docker-compose.yml"

    # Show symlink tip on first run
    if [[ ! -L "/opt/sw/docker-compose/omnifileserver/docker-compose.yml" ]] && [[ -d "/opt/sw/docker-compose" ]]; then
        echo ""
        echo "💡 Tip: To organize by file type, symlink the compose file:"
        echo "   mkdir -p /opt/sw/docker-compose/omnifileserver"
        echo "   ln -s $SCRIPT_DIR/docker-compose.yml /opt/sw/docker-compose/omnifileserver/"
    fi

    # Ask if user wants to restart services
    echo ""
    read -p "Restart services to apply changes? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Restarting services..."
        cd "$SCRIPT_DIR"
        echo "Running: $DOCKER_COMPOSE down"
        $DOCKER_COMPOSE down
        echo "Running: $DOCKER_COMPOSE up -d"
        if $DOCKER_COMPOSE up -d; then
            success "Services restarted"
        else
            warn "Failed to start services (permission denied). Run this command:"
            show_sudo_cmd "$DOCKER_COMPOSE up -d"
        fi
    else
        warn "Changes generated but not applied. Run '$DOCKER_COMPOSE up -d' to apply."
    fi
}

# Command: reset
reset() {
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                  RESET CONFIGURATION                       ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    warn "⚠️  WARNING: This will remove ALL configuration and data!"
    echo ""
    echo "The following will be deleted:"
    echo "  • Configuration files (.env, .env.passwords, users.conf, shares.conf)"
    echo "  • Generated docker-compose.yml"
    echo "  • shares/ directory and all files"
    echo "  • config/ directory (Samba and Netatalk configs)"
    echo "  • Running containers will be stopped and removed"
    echo ""

    # Confirm reset
    read -r -p "Are you sure you want to reset? (type 'yes' to confirm): " confirm
    if [[ "${confirm}" != "yes" ]]; then
        warn "Reset cancelled"
        return
    fi

    echo ""

    # Ask about archiving
    read -r -p "Create backup archive before deleting? (Y/n): " -n 1
    echo

    local archive_created=false
    if [[ ! ${REPLY} =~ ^[Nn]$ ]]; then
        # Create timestamped archive
        local timestamp
        timestamp=$(date +%Y%m%d-%H%M%S)
        local archive_name="omnifileserver-config-backup-${timestamp}.tar.gz"

        echo "Creating backup archive: ${archive_name}"

        # Build list of files/dirs to archive (only if they exist)
        local items_to_archive=()
        [[ -f "${ENV_FILE}" ]] && items_to_archive+=(".env")
        [[ -f "${PASSWORDS_FILE}" ]] && items_to_archive+=(".env.passwords")
        [[ -f "${USERS_CONF}" ]] && items_to_archive+=("users.conf")
        [[ -f "${SHARES_CONF}" ]] && items_to_archive+=("shares.conf")
        [[ -f "${COMPOSE_FILE}" ]] && items_to_archive+=("docker-compose.yml")
        [[ -d "${SCRIPT_DIR}/shares" ]] && items_to_archive+=("shares/")
        [[ -d "${SCRIPT_DIR}/config" ]] && items_to_archive+=("config/")

        if [[ ${#items_to_archive[@]} -eq 0 ]]; then
            warn "No files to archive (nothing configured yet)"
        else
            # Create archive
            cd "${SCRIPT_DIR}" || error "Failed to cd to ${SCRIPT_DIR}"
            if tar -czf "${archive_name}" "${items_to_archive[@]}" 2>/dev/null; then
                success "✓ Backup created: ${SCRIPT_DIR}/${archive_name}"
                archive_created=true
            else
                warn "Failed to create archive, continuing with reset..."
            fi
        fi
        echo ""
    fi

    # Stop and remove containers
    if [[ -f "${COMPOSE_FILE}" ]]; then
        echo "Stopping and removing containers..."
        cd "${SCRIPT_DIR}" || error "Failed to cd to ${SCRIPT_DIR}"
        echo "Running: ${DOCKER_COMPOSE} down"
        ${DOCKER_COMPOSE} down 2>/dev/null || warn "Could not stop containers (may not be running)"
    fi

    # Remove files
    echo "Removing configuration files..."
    [[ -f "${ENV_FILE}" ]] && rm -f "${ENV_FILE}" && echo "  • Removed .env"
    [[ -f "${PASSWORDS_FILE}" ]] && rm -f "${PASSWORDS_FILE}" && echo "  • Removed .env.passwords"
    [[ -f "${USERS_CONF}" ]] && rm -f "${USERS_CONF}" && echo "  • Removed users.conf"
    [[ -f "${SHARES_CONF}" ]] && rm -f "${SHARES_CONF}" && echo "  • Removed shares.conf"
    [[ -f "${COMPOSE_FILE}" ]] && rm -f "${COMPOSE_FILE}" && echo "  • Removed docker-compose.yml"

    # Remove directories
    if [[ -d "${SCRIPT_DIR}/shares" ]]; then
        echo "  • Removing shares/ directory..."
        rm -rf "${SCRIPT_DIR}/shares"
    fi

    if [[ -d "${SCRIPT_DIR}/config" ]]; then
        echo "  • Removing config/ directory..."
        rm -rf "${SCRIPT_DIR}/config"
    fi

    # Remove backup files from sed operations
    rm -f "${SCRIPT_DIR}"/*.bak 2>/dev/null

    echo ""
    success "✓ Reset complete!"

    if [[ "${archive_created}" == "true" ]]; then
        echo ""
        echo "Your configuration backup is saved at:"
        echo "  ${SCRIPT_DIR}/omnifileserver-config-backup-${timestamp}.tar.gz"
        echo ""
        echo "To restore from backup:"
        echo "  cd ${SCRIPT_DIR}"
        echo "  tar -xzf omnifileserver-config-backup-${timestamp}.tar.gz"
    fi

    echo ""
    echo "To set up again, run: $0 init"
}

# Command: help
show_help() {
    cat << EOF
Home File Server Management Tool

Usage: $0 <command> [arguments]

Initial Setup:
  init
      Interactive setup wizard for first-time configuration
      Creates directories, first user, first share, and starts services
      Example: $0 init

User Management:
  add-user <username> [uid] [gid] [description]
      Add a new user (synced to both Samba and AFP)
      Password will be prompted securely (not visible in command history)
      Example: $0 add-user alice 1000 1000 "Alice Smith"

  remove-user <username>
      Remove a user
      Example: $0 remove-user alice

  list-users
      List all configured users

  change-password <username>
      Change password for an existing user
      Password will be prompted securely
      Example: $0 change-password alice

Share Management:
  add-share [<name> <path> <rw|ro> <users> [comment] [protocols]]
      Add a new share with protocol selection
      Interactive wizard mode (recommended): $0 add-share
      Command-line mode: $0 add-share media /shares/media ro alice,bob "Media Library" "smb,afp"
      Protocols: smb,afp (both), smb (Windows/Linux only), afp (Mac only)

  remove-share <name>
      Remove a share
      Example: $0 remove-share media

  list-shares
      List all configured shares

Home Directory Shares:
  enable-homes [base-path]
      Enable per-user home directory shares
      Each user gets their own home directory as a share
      Auto-detects OS if base-path not provided (/home for Linux, /Users for macOS)
      Example: $0 enable-homes            # Auto-detect
      Example: $0 enable-homes /home      # Manual Linux
      Example: $0 enable-homes /Users     # Manual macOS

  disable-homes
      Disable home directory shares

Apply Changes:
  apply
      Regenerate docker-compose.yml and optionally restart services

Reset Configuration:
  reset
      Remove all configuration and optionally create a backup archive
      Stops containers, removes all config files, shares/, config/, and compose file
      Optionally creates timestamped config backup: omnifileserver-config-backup-YYYYMMDD-HHMMSS.tar.gz
      Example: $0 reset

Help:
  help
      Show this help message

Notes:
  - Passwords are stored securely in .env file (not in CLI history or users.conf)
  - UIDs should match host system for proper file permissions
  - Users can be comma-separated or 'all' for share access
  - Always run 'apply' after making changes
  - Add .env to .gitignore to avoid committing passwords
EOF
}

# Main command dispatcher
case "${1:-help}" in
    init)
        init
        ;;
    add-user)
        shift
        add_user "$@"
        ;;
    remove-user)
        shift
        remove_user "$@"
        ;;
    list-users)
        list_users
        ;;
    change-password)
        shift
        change_password "$@"
        ;;
    add-share)
        shift
        add_share "$@"
        ;;
    remove-share)
        shift
        remove_share "$@"
        ;;
    list-shares)
        list_shares
        ;;
    enable-homes)
        shift
        enable_homes "$@"
        ;;
    disable-homes)
        disable_homes
        ;;
    apply)
        apply
        ;;
    reset)
        reset
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        error "Unknown command: $1\n\nRun '$0 help' for usage information"
        ;;
esac
