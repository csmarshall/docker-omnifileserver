#!/bin/bash
# Configuration variable definitions with defaults and descriptions
# Format: VAR_NAME|default_value|description|options (optional)

# This file defines all configurable variables for the file server
# Used by init wizard to prompt for settings

CONFIG_VARS=(
    # Server identification
    "SERVER_NAME|$(hostname) File Server|Server name shown in network browsers"
    "WORKGROUP|WORKGROUP|Windows workgroup/domain name"

    # macOS/Avahi settings
    "MODEL|RackMac|Icon shown in macOS Finder|RackMac,Xserve,TimeCapsule,MacPro,MacBook,MacBookPro,MacMini,iMac"
    "AVAHI_NAME|\${SERVER_NAME}|Name for mDNS/Avahi service discovery"

    # Logging
    "SAMBA_LOG_LEVEL|1|Samba log verbosity (0-10)|0,1,2,3"
    "AFP_LOG_LEVEL|info|AFP/Netatalk log level|default,error,warn,note,info,debug,maxdebug"

    # Advanced
    "SAMBA_SERVER_ROLE|standalone server|Samba server role|standalone server,member server,domain controller"
    "SAMBA_MAP_TO_GUEST|Bad User|Guest access behavior|Never,Bad User,Bad Password"
)

# Function to get default value for a variable
get_default() {
    local var_name="$1"
    for config in "${CONFIG_VARS[@]}"; do
        IFS='|' read -r name default desc options <<< "$config"
        if [[ "$name" == "$var_name" ]]; then
            # Expand variables in default (e.g., ${SERVER_NAME})
            eval echo "$default"
            return
        fi
    done
    echo ""
}

# Function to get description for a variable
get_description() {
    local var_name="$1"
    for config in "${CONFIG_VARS[@]}"; do
        IFS='|' read -r name default desc options <<< "$config"
        if [[ "$name" == "$var_name" ]]; then
            echo "$desc"
            return
        fi
    done
    echo ""
}

# Function to get options for a variable (if any)
get_options() {
    local var_name="$1"
    for config in "${CONFIG_VARS[@]}"; do
        IFS='|' read -r name default desc options <<< "$config"
        if [[ "$name" == "$var_name" ]]; then
            echo "$options"
            return
        fi
    done
    echo ""
}
