#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USERS_CONF="${SCRIPT_DIR}/users.conf"
SHARES_CONF="${SCRIPT_DIR}/shares.conf"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
ENV_FILE="${SCRIPT_DIR}/.env"
PASSWORDS_FILE="${SCRIPT_DIR}/.env.passwords"

# Source .env file if it exists to read configuration
if [[ -f "${ENV_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
fi

# Read users and generate environment variables
# Uses docker-compose variable substitution to read passwords from .env
generate_user_envs() {
    local service="$1"  # "samba" or "netatalk"

    # shellcheck disable=SC2034
    grep -v "^#" "${USERS_CONF}" | grep -v "^$" | while IFS=: read -r username uid gid description; do
        if [[ "$service" == "samba" ]]; then
            # Docker Compose will substitute ${PASSWORD_username} from .env
            echo "      - ACCOUNT_${username}=${username};\${PASSWORD_${username}}"
        else
            # Docker Compose will substitute ${PASSWORD_username} from .env
            echo "      - ACCOUNT_${username}=${username};${uid};${gid};\${PASSWORD_${username}}"
        fi
    done
}

# Collect absolute paths from shares.conf
# Skips variable paths (containing %U) since they're dynamic per-user
collect_absolute_paths() {
    grep -v "^#" "${SHARES_CONF}" | grep -v "^$" | while IFS=: read -r name path permissions users comment protocols; do
        # Skip variable paths (contain %U for per-user paths)
        if [[ "${path}" =~ %U ]]; then
            continue
        fi

        # Check if path is absolute (starts with /)
        if [[ "${path}" =~ ^/ ]]; then
            echo "${path}"
        fi
    done | sort -u
}

# Collect base directories for variable paths
# Extracts /storage/users from /storage/users/%U
collect_variable_path_bases() {
    grep -v "^#" "${SHARES_CONF}" | grep -v "^$" | while IFS=: read -r name path permissions users comment protocols; do
        # Only process variable paths
        if [[ "${path}" =~ %U ]]; then
            # Extract base path by removing /%U suffix
            local base_path="${path/\/%U/}"
            echo "${base_path}"
        fi
    done | sort -u
}

# Generate volume mounts for absolute paths
# Maps host paths to /shares/<path> in container
generate_volume_mounts() {
    collect_absolute_paths | while read -r abspath; do
        echo "      - ${abspath}:/shares${abspath}"
    done

    # Also mount base directories for variable paths
    collect_variable_path_bases | while read -r base_path; do
        echo "      - ${base_path}:/shares${base_path}"
    done
}

# Read shares and generate environment variables
generate_share_envs() {
    local service="$1"  # "samba" or "netatalk"

    grep -v "^#" "${SHARES_CONF}" | grep -v "^$" | while IFS=: read -r name path permissions users comment protocols; do
        # Default to both protocols if not specified
        protocols="${protocols:-smb,afp}"

        # Check if this service is enabled for this share
        local service_protocol
        if [[ "${service}" == "samba" ]]; then
            service_protocol="smb"
        else
            service_protocol="afp"
        fi

        # Skip if this protocol is not enabled for this share
        if [[ ! "${protocols}" =~ ${service_protocol} ]]; then
            continue
        fi

        local readonly="no"
        local afp_mode="rw"

        if [[ "${permissions}" == "ro" ]]; then
            readonly="yes"
            afp_mode="ro"
        fi

        # Determine container path (absolute paths get /shares prefix)
        local container_path="${path}"
        if [[ "${path}" =~ ^/ ]]; then
            container_path="/shares${path}"
        fi

        if [[ "${service}" == "samba" ]]; then
            # Samba uses %U for username variable (keep as-is)
            # Format: sharename;path;browseable;readonly;guest;users;admins;writelist;comment
            echo "      - SAMBA_VOLUME_CONFIG_${name}=${container_path};yes;${readonly};no;${users};;;${comment}"
        else
            # Netatalk uses $u for username variable (convert %U to $u)
            local afp_path="${container_path/\%U/\$u}"
            # Format: sharename;path;mode;allow:users
            echo "      - AFP_VOLUME_CONFIG_${name}=${afp_path};${afp_mode};allow:${users}"
        fi
    done
}

# Get configuration with defaults (can be overridden in .env)
HOSTNAME=$(hostname)
SERVER_NAME="${SERVER_NAME:-${HOSTNAME} File Server}"
WORKGROUP="${WORKGROUP:-WORKGROUP}"
SAMBA_LOG_LEVEL="${SAMBA_LOG_LEVEL:-1}"
AFP_LOG_LEVEL="${AFP_LOG_LEVEL:-info}"
FRUIT_MODEL="${FRUIT_MODEL:-MacPro7,1@ECOLOR=226,226,224}"
AVAHI_DISABLE_PUBLISHING="${AVAHI_DISABLE_PUBLISHING:-0}"
HOME_DIRECTORIES_ENABLED="${HOME_DIRECTORIES_ENABLED:-no}"

# Auto-detect home directory base based on OS if not set
if [[ -z "${HOME_DIRECTORIES_BASE}" ]]; then
    case "$(uname)" in
        Darwin)
            HOME_DIRECTORIES_BASE="/Users"
            ;;
        Linux)
            HOME_DIRECTORIES_BASE="/home"
            ;;
        *)
            HOME_DIRECTORIES_BASE="/home"  # fallback to Linux default
            ;;
    esac
fi

# Generate docker-compose.yml
cat > "$COMPOSE_FILE" << EOF
# Generated docker-compose.yml for OmniFileServer
# To run this configuration, use one of these commands:
#
# Via manage.sh (recommended):
#   ${SCRIPT_DIR}/manage.sh apply
#
# Direct docker compose command:
#   docker compose -f ${COMPOSE_FILE} --env-file ${ENV_FILE} --env-file ${PASSWORDS_FILE} up -d
#
# The --env-file flags are required for variable substitution in this file

services:
  samba:
    image: ghcr.io/servercontainers/samba
    container_name: omnifileserver-samba
    network_mode: host
    volumes:
      - ${SCRIPT_DIR}/shares:/shares
      - ${SCRIPT_DIR}/config/samba:/config
EOF

# Add absolute path volume mounts
generate_volume_mounts >> "$COMPOSE_FILE"

# Add home directory mount if enabled
if [[ "${HOME_DIRECTORIES_ENABLED}" == "yes" ]]; then
    echo "      - ${HOME_DIRECTORIES_BASE}:${HOME_DIRECTORIES_BASE}" >> "$COMPOSE_FILE"
fi

cat >> "$COMPOSE_FILE" << EOF
    # Passwords file path: ${SCRIPT_DIR}/.env.passwords
    env_file:
      - ${SCRIPT_DIR}/.env.passwords
    environment:
      # Basic server info
      - SAMBA_CONF_SERVER_STRING=${SERVER_NAME}
      - SAMBA_CONF_WORKGROUP=${WORKGROUP}

      # Avahi/mDNS service discovery
      - AVAHI_NAME=${SERVER_NAME}
      - AVAHI_DISABLE_PUBLISHING=${AVAHI_DISABLE_PUBLISHING}

      # Advanced options
      - SAMBA_CONF_LOG_LEVEL=${SAMBA_LOG_LEVEL}
      - SAMBA_GLOBAL_CONFIG_fruit_metadata=stream
      - SAMBA_GLOBAL_CONFIG_fruit_model=${FRUIT_MODEL}
      - SAMBA_GLOBAL_CONFIG_vfs_objects=catia fruit streams_xattr

      # User accounts (generated from users.conf)
EOF

# Add Samba users
generate_user_envs "samba" >> "$COMPOSE_FILE"

cat >> "$COMPOSE_FILE" << 'EOF'

      # Share definitions (generated from shares.conf)
EOF

# Add Samba shares
generate_share_envs "samba" >> "$COMPOSE_FILE"

# Add Samba home directories if enabled
if [[ "${HOME_DIRECTORIES_ENABLED}" == "yes" ]]; then
    cat >> "$COMPOSE_FILE" << 'SAMBA_HOMES'

      # Home directory shares (auto-generated per user)
      - SAMBA_GLOBAL_CONFIG_homes=yes;browseable=no
      - SAMBA_VOLUME_CONFIG_homes=${HOME_DIRECTORIES_BASE}/%U;yes;no;no;%U
SAMBA_HOMES
fi

cat >> "$COMPOSE_FILE" << EOF
    restart: unless-stopped

  netatalk:
    image: ghcr.io/servercontainers/netatalk
    container_name: omnifileserver-netatalk
    network_mode: host
    volumes:
      - ${SCRIPT_DIR}/shares:/shares
      - ${SCRIPT_DIR}/config/netatalk:/config
EOF

# Add absolute path volume mounts
generate_volume_mounts >> "$COMPOSE_FILE"

# Add home directory mount if enabled
if [[ "${HOME_DIRECTORIES_ENABLED}" == "yes" ]]; then
    echo "      - ${HOME_DIRECTORIES_BASE}:${HOME_DIRECTORIES_BASE}" >> "$COMPOSE_FILE"
fi

cat >> "$COMPOSE_FILE" << EOF
    # Passwords file path: ${SCRIPT_DIR}/.env.passwords
    env_file:
      - ${SCRIPT_DIR}/.env.passwords
    environment:
      # Basic server info
      - AFP_NAME=${SERVER_NAME}
      - AFP_WORKGROUP=${WORKGROUP}

      # Avahi/mDNS service discovery
      - AVAHI_NAME=${SERVER_NAME}
      - AVAHI_DISABLE_PUBLISHING=${AVAHI_DISABLE_PUBLISHING}

      # Advanced options
      - AFP_LOGLEVEL=${AFP_LOG_LEVEL}

      # User accounts (generated from users.conf)
EOF

# Add Netatalk users
generate_user_envs "netatalk" >> "$COMPOSE_FILE"

cat >> "$COMPOSE_FILE" << 'EOF'

      # AFP share definitions (generated from shares.conf)
EOF

# Add Netatalk shares
generate_share_envs "netatalk" >> "$COMPOSE_FILE"

# Add Netatalk home directories if enabled
if [[ "${HOME_DIRECTORIES_ENABLED}" == "yes" ]]; then
    cat >> "$COMPOSE_FILE" << 'NETATALK_HOMES'

      # Home directory shares (auto-generated per user)
      - NETATALK_GLOBAL_CONFIG_homes="basedir regex = ${HOME_DIRECTORIES_BASE}"
NETATALK_HOMES
fi

cat >> "$COMPOSE_FILE" << 'EOF'
    restart: unless-stopped
EOF

echo "Generated docker-compose.yml successfully"
