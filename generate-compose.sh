#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USERS_CONF="$SCRIPT_DIR/users.conf"
SHARES_CONF="$SCRIPT_DIR/shares.conf"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
ENV_FILE="$SCRIPT_DIR/.env"

# Load passwords from .env file
declare -A PASSWORDS
if [[ -f "$ENV_FILE" ]]; then
    while IFS='=' read -r key value; do
        if [[ "$key" =~ ^PASSWORD_ ]]; then
            username="${key#PASSWORD_}"
            PASSWORDS["$username"]="$value"
        fi
    done < <(grep "^PASSWORD_" "$ENV_FILE")
fi

# Read users and generate environment variables
generate_user_envs() {
    local service="$1"  # "samba" or "netatalk"

    grep -v "^#" "$USERS_CONF" | grep -v "^$" | while IFS=: read -r username uid gid description; do
        local password="${PASSWORDS[$username]}"
        if [[ -z "$password" ]]; then
            echo "# WARNING: No password found for user $username" >&2
            password="CHANGEME"
        fi

        if [[ "$service" == "samba" ]]; then
            echo "      - ACCOUNT_${username}=${username};${password}"
        else
            echo "      - ACCOUNT_${username}=${username};${uid};${gid};${password}"
        fi
    done
}

# Read shares and generate environment variables
generate_share_envs() {
    local service="$1"  # "samba" or "netatalk"

    grep -v "^#" "$SHARES_CONF" | grep -v "^$" | while IFS=: read -r name path permissions users comment; do
        local readonly="no"
        local afp_mode="rw"

        if [[ "$permissions" == "ro" ]]; then
            readonly="yes"
            afp_mode="ro"
        fi

        if [[ "$service" == "samba" ]]; then
            # Format: sharename;path;browseable;readonly;guest;users;admins;writelist;comment
            echo "      - SAMBA_VOLUME_CONFIG_${name}=${path};yes;${readonly};no;${users};;;${comment}"
        else
            # Format: sharename;path;mode;allow:users
            echo "      - AFP_VOLUME_CONFIG_${name}=${path};${afp_mode};allow:${users}"
        fi
    done
}

# Get hostname for server identification
HOSTNAME=$(hostname)
SERVER_NAME="${HOSTNAME} File Server"

# Generate docker-compose.yml
cat > "$COMPOSE_FILE" << EOF
version: '3.8'

services:
  avahi:
    image: servercontainers/avahi
    container_name: homefileserver-avahi
    network_mode: host
    volumes:
      - ./config/avahi:/external/avahi
    environment:
      - AVAHI_ENABLE_REFLECTOR=yes
    restart: unless-stopped

  samba:
    image: servercontainers/samba
    container_name: homefileserver-samba
    network_mode: host
    volumes:
      - ./shares:/shares
      - ./config/samba:/config
    environment:
      # Basic server info
      - SAMBA_CONF_SERVER_STRING=${SERVER_NAME}
      - SAMBA_CONF_WORKGROUP=WORKGROUP

      # Avahi/mDNS service discovery
      - AVAHI_NAME=${SERVER_NAME}
      - AVAHI_DISABLE_PUBLISHING=0

      # Advanced options
      - SAMBA_CONF_LOG_LEVEL=1
      - SAMBA_GLOBAL_CONFIG_fruit_metadata=stream
      - SAMBA_GLOBAL_CONFIG_fruit_model=RackMac
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

cat >> "$COMPOSE_FILE" << EOF
    restart: unless-stopped

  netatalk:
    image: servercontainers/netatalk
    container_name: homefileserver-netatalk
    network_mode: host
    volumes:
      - ./shares:/shares
      - ./config/netatalk:/config
    environment:
      # Basic server info
      - AFP_NAME=${SERVER_NAME}
      - AFP_WORKGROUP=WORKGROUP

      # Avahi/mDNS service discovery
      - AVAHI_NAME=${SERVER_NAME}
      - AVAHI_DISABLE_PUBLISHING=0

      # Advanced options
      - AFP_LOGLEVEL=info

      # User accounts (generated from users.conf)
EOF

# Add Netatalk users
generate_user_envs "netatalk" >> "$COMPOSE_FILE"

cat >> "$COMPOSE_FILE" << 'EOF'

      # AFP share definitions (generated from shares.conf)
EOF

# Add Netatalk shares
generate_share_envs "netatalk" >> "$COMPOSE_FILE"

cat >> "$COMPOSE_FILE" << 'EOF'
    restart: unless-stopped
EOF

echo "Generated docker-compose.yml successfully"
