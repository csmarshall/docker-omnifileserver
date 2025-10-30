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

# Detect docker-compose vs docker compose
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
elif docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
else
    echo "Error: Neither 'docker-compose' nor 'docker compose' found"
    echo "Please install Docker Compose: https://docs.docker.com/compose/install/"
    exit 1
fi

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
    local comment="${5:-$name}"

    if [[ -z "$name" || -z "$path" || -z "$permissions" || -z "$users" ]]; then
        error "Usage: $0 add-share <name> <path> <rw|ro> <users> [comment]"
    fi

    # Validate permissions
    if [[ "$permissions" != "rw" && "$permissions" != "ro" ]]; then
        error "Permissions must be 'rw' or 'ro'"
    fi

    # Check if share already exists
    if grep -q "^${name}:" "$SHARES_CONF"; then
        error "Share '$name' already exists"
    fi

    # Check if path is absolute
    if [[ "$path" =~ ^/ ]]; then
        # Absolute path - verify it exists
        if [[ ! -d "$path" ]]; then
            warn "Warning: Absolute path '$path' does not exist"
            read -p "Create it now? (y/N) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                mkdir -p "$path" || error "Failed to create directory '$path'"
                success "Created directory '$path'"
            else
                warn "Directory not created. Ensure it exists before starting services."
            fi
        fi
    else
        # Relative path - should be under ./shares/
        if [[ ! "$path" =~ ^/shares/ ]]; then
            warn "Warning: Relative path should typically be /shares/something"
        fi
    fi

    # Add share to config
    echo "$name:$path:$permissions:$users:$comment" >> "$SHARES_CONF"
    success "Added share '$name' -> $path ($permissions)"
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
        read -p "Continue anyway? This may overwrite existing setup. (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Initialization cancelled."
            exit 0
        fi
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
    declare -A config_values
    for config in "${CONFIG_VARS[@]}"; do
        IFS='|' read -r name default desc options <<< "$config"

        # Evaluate default (expand variables like ${SERVER_NAME})
        eval "default_value=\"$default\""

        # Show description and options if available
        echo ""
        echo "$desc"
        if [[ -n "$options" ]]; then
            echo "Options: $options"
        fi

        # Prompt with default
        read -p "${name} [${default_value}]: " user_value

        # Use default if empty
        final_value="${user_value:-$default_value}"
        config_values["$name"]="$final_value"

        # Append to .env
        echo "${name}=${final_value}" >> "$ENV_FILE"
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

    read -p "Directory name in shares/ (default: $first_share): " first_dir
    first_dir="${first_dir:-$first_share}"

    echo "Permissions:"
    echo "  rw - Read/write access"
    echo "  ro - Read-only access"
    read -p "Permissions (rw/ro, default: rw): " first_perms
    first_perms="${first_perms:-rw}"

    if [[ "$first_perms" != "rw" && "$first_perms" != "ro" ]]; then
        error "Permissions must be 'rw' or 'ro'"
    fi

    read -p "Description (default: $first_share): " first_comment
    first_comment="${first_comment:-$first_share}"

    # Create share directory
    mkdir -p "$SCRIPT_DIR/shares/$first_dir"

    # Save share
    echo "$first_share:/shares/$first_dir:$first_perms:$first_user:$first_comment" >> "$SHARES_CONF"

    success "✓ Share '$first_share' created at shares/$first_dir"
    echo ""

    # Step 5: Set permissions
    echo "Step 5: Setting permissions..."
    chown -R "${first_uid}:${first_gid}" "$SCRIPT_DIR/shares/$first_dir" 2>/dev/null || {
        warn "Could not set ownership (may need sudo). You can fix this later with:"
        echo "  sudo chown -R ${first_uid}:${first_gid} $SCRIPT_DIR/shares/$first_dir"
    }
    chmod 755 "$SCRIPT_DIR/shares/$first_dir"
    success "✓ Permissions set"
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
        $DOCKER_COMPOSE up -d
        success "✓ Services started"
        echo ""

        # Show status
        echo "Checking status..."
        sleep 2
        $DOCKER_COMPOSE ps
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
        $DOCKER_COMPOSE down
        $DOCKER_COMPOSE up -d
        success "Services restarted"
    else
        warn "Changes generated but not applied. Run '$DOCKER_COMPOSE up -d' to apply."
    fi
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
  add-share <name> <path> <rw|ro> <users> [comment]
      Add a new share (synced to both Samba and AFP)
      Example: $0 add-share media /shares/media ro alice,bob "Media Library"

  remove-share <name>
      Remove a share
      Example: $0 remove-share media

  list-shares
      List all configured shares

Apply Changes:
  apply
      Regenerate docker-compose.yml and optionally restart services

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
    apply)
        apply
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        error "Unknown command: $1\n\nRun '$0 help' for usage information"
        ;;
esac
