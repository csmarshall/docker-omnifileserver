# Home File Server (Docker)

A containerized file server solution providing **SMB/CIFS** (Samba) and **AFP** (Netatalk) shares with automatic service discovery via **Avahi/mDNS**.

## Features

- 🗂️ **SMB/CIFS shares** - Compatible with Windows, macOS, Linux
- 🍎 **AFP shares** - Native macOS file sharing protocol
- 📡 **mDNS/Avahi** - Automatic network discovery (shows up in Finder/Network)
- 🐳 **Docker-based** - Easy deployment and migration
- 🔒 **User authentication** - Multiple user accounts with access control

## Requirements

### System Requirements
- Docker Engine 20.10+
- Docker Compose 2.0+
- Host OS: Linux (recommended), macOS (limited), Windows (not recommended)

### Network Requirements
- **`network_mode: host`** - All containers use host networking for:
  - Proper SMB/AFP port access
  - mDNS/Avahi multicast support
  - Service discovery to work correctly
- Open firewall ports:
  - **139/tcp, 445/tcp** - SMB/CIFS
  - **548/tcp** - AFP
  - **5353/udp** - mDNS (Avahi)

### Storage Requirements
- Sufficient disk space for shared files
- Proper filesystem permissions for Docker to access share directories

## Directory Structure

```
docker-homefileserver/
├── manage.sh              # Management script (add users, shares, apply changes)
├── generate-compose.sh    # Generates docker-compose.yml from config files
├── users.conf             # User definitions (without passwords)
├── shares.conf            # Share definitions
├── .env                   # Passwords (git-ignored, chmod 600)
├── .gitignore             # Protects sensitive files
├── docker-compose.yml     # Generated service definitions
├── README.md              # This file
├── config/                # Persistent configuration (auto-generated)
│   ├── avahi/            # Avahi service definitions
│   ├── samba/            # Samba generated configs
│   └── netatalk/         # Netatalk generated configs
└── shares/                # Actual shared data
    ├── shared/           # Example: Read-write shared folder
    └── media/            # Example: Read-only media library
```

## Setup Instructions

### Quick Start (Recommended)

Run the interactive setup wizard:

```bash
./manage.sh init
```

This will guide you through:
1. Creating directory structure
2. Adding your first user (with secure password prompt)
3. Creating your first share
4. Generating configuration
5. Starting Docker services

**That's it!** The wizard handles everything for you.

### Manual Setup

If you prefer manual configuration:

#### 1. Create Share Directories

Create directories for your shares:
```bash
mkdir -p shares/shared shares/media
# Add more as needed
```

Set appropriate permissions:
```bash
# Option 1: Set ownership to match container UIDs
sudo chown -R 1000:1000 shares/

# Option 2: Use permissive permissions (less secure)
chmod -R 755 shares/
```

#### 2. Add Users

Use the management script to add users. Passwords are prompted securely:

```bash
# Add user with default UID/GID (1000:1000)
./manage.sh add-user alice

# Add user with specific UID/GID
./manage.sh add-user bob 1001 1001 "Bob Jones"

# List all users
./manage.sh list-users
```

**Security features:**
- Passwords are prompted securely (not visible, not in command history)
- Passwords stored in `.env` file with `chmod 600` permissions
- `.env` file is git-ignored automatically
- Users are automatically synced to both SMB and AFP

#### 3. Add Shares

Add shares that will be available on both SMB and AFP:

```bash
# Read-write share for specific users
./manage.sh add-share shared /shares/shared rw alice,bob "Shared Files"

# Read-only share for all users
./manage.sh add-share media /shares/media ro all "Media Library"

# Personal share for one user
./manage.sh add-share alice-private /shares/alice rw alice "Alice's Files"

# List all shares
./manage.sh list-shares
```

#### 4. Generate Config and Start Services

Apply changes and start services:

```bash
# Generate docker-compose.yml and optionally restart services
./manage.sh apply
```

This will:
- Generate `docker-compose.yml` from your config
- Use your machine's hostname for server identification
- Configure RackMac icon for macOS clients
- Prompt to restart Docker services

#### 5. Verify Services

```bash
# Check containers are running
docker-compose ps

# Check logs
docker-compose logs -f

# Test SMB from Linux/macOS
smbclient -L localhost -N

# Test AFP from macOS Finder
# Open Finder → Go → Connect to Server → afp://hostname
```

## Usage

### Connecting from Clients

**Windows:**
- Open File Explorer → Network
- Or: `\\hostname\sharename` in address bar

**macOS (SMB):**
- Finder → Network → Browse
- Or: Finder → Go → Connect to Server → `smb://hostname`

**macOS (AFP):**
- Finder → Network → Browse
- Or: Finder → Go → Connect to Server → `afp://hostname`

**Linux:**
```bash
# Mount SMB share
sudo mount -t cifs //hostname/sharename /mnt/point -o username=alice

# Or use file manager to browse network
```

### Managing the Server

#### User Management

```bash
# Add a new user
./manage.sh add-user username [uid] [gid] [description]

# Remove a user
./manage.sh remove-user username

# List all users
./manage.sh list-users
```

#### Share Management

```bash
# Add a new share
./manage.sh add-share name /shares/path rw|ro users "Description"

# Remove a share
./manage.sh remove-share name

# List all shares
./manage.sh list-shares
```

#### Applying Changes

After modifying users or shares, apply changes:

```bash
./manage.sh apply
```

This regenerates `docker-compose.yml` and prompts to restart services.

#### Docker Operations

**Start services:**
```bash
docker-compose up -d
```

**Stop services:**
```bash
docker-compose down
```

**Restart services:**
```bash
docker-compose restart
```

**View logs:**
```bash
docker-compose logs -f [service_name]
```

**Update images:**
```bash
docker-compose pull
docker-compose up -d
```

## Configuration Options

### Configuration Files

**users.conf** - User definitions (format: `username:uid:gid:description`)
- Passwords are stored separately in `.env` for security
- UIDs/GIDs should match your host system

**shares.conf** - Share definitions (format: `name:path:rw|ro:users:comment`)
- Automatically synced to both SMB and AFP
- Users can be comma-separated or 'all'

**.env** - Password storage (auto-managed by scripts)
- Format: `PASSWORD_username=password`
- Automatically chmod 600 for security
- Git-ignored by default

### Server Identification

The server name is automatically set to `<hostname> File Server`:
- Uses your machine's hostname
- Appears in network browsers (Finder, File Explorer)
- macOS shows RackMac (rack server) icon

To customize, modify `generate-compose.sh`:
```bash
SERVER_NAME="My Custom Name"
```

### Advanced Configuration

**Manual docker-compose.yml editing:**
After running `./manage.sh apply`, you can manually edit `docker-compose.yml` for advanced settings. Note: Changes will be overwritten on next `apply`.

**Custom config files:**
Mount custom config files by editing the generated docker-compose.yml:
```yaml
volumes:
  - ./custom-smb.conf:/etc/samba/smb.conf:ro
  - ./custom-afp.conf:/etc/netatalk/afp.conf:ro
```

**macOS icon options:**
Edit `generate-compose.sh` and change `fruit_model`:
- `RackMac` - Rack-mounted server icon (default)
- `Xserve` - Xserve icon
- `TimeCapsule` - Time Capsule icon
- `MacPro` - Mac Pro icon

## Security Considerations

### Password Security
- ✅ **Passwords are never in command history** - prompted securely with `read -s`
- ✅ **Passwords are not in users.conf** - stored separately in `.env`
- ✅ **`.env` has chmod 600** - only readable by owner
- ✅ **`.env` is git-ignored** - won't be committed to repositories
- 🔐 **Use strong, unique passwords** for each user

### Access Control
- 🚫 **Avoid running as root** - use UID/GID mapping matching your host system
- 🛡️ **Use firewall rules** to restrict access to trusted networks only
- 📁 **Set proper permissions** on share directories (recommend 755 or 770)
- 👥 **Limit user access** - only grant share access to users who need it

### Maintenance
- 📝 **Regularly update Docker images** for security patches:
  ```bash
  docker-compose pull && docker-compose up -d
  ```
- 🔍 **Monitor logs** for suspicious activity:
  ```bash
  docker-compose logs -f
  ```
- 🔒 **Backup `.env` securely** if you need disaster recovery

## Troubleshooting

### Shares not appearing on network

1. Check Avahi container is running: `docker-compose logs avahi`
2. Verify host networking mode is enabled
3. Ensure firewall allows mDNS (port 5353/udp)
4. Check if Avahi is installed/running on host (may conflict)

### Cannot connect to shares

1. Verify services are running: `docker-compose ps`
2. Check logs: `docker-compose logs samba` or `docker-compose logs netatalk`
3. Test ports: `netstat -tulpn | grep -E '445|548'`
4. Verify credentials are correct
5. Check filesystem permissions on share directories

### Permission denied errors

1. Check UID/GID mapping in config
2. Verify share directory ownership: `ls -la shares/`
3. Adjust permissions: `chmod` or `chown` as needed

### After config changes, not taking effect

1. Restart services: `docker-compose restart`
2. Or recreate containers: `docker-compose down && docker-compose up -d`

## Migration to Another Host

1. Stop services: `docker-compose down`
2. Copy entire `docker-homefileserver/` directory to new host:
   ```bash
   rsync -av docker-homefileserver/ newhost:/path/to/docker-homefileserver/
   ```
   **Important:** This includes `.env` file with passwords
3. Ensure Docker and Docker Compose are installed on new host
4. On new host, verify `.env` permissions:
   ```bash
   chmod 600 .env
   ```
5. If hostname changed, regenerate config:
   ```bash
   ./manage.sh apply
   ```
6. Start services: `docker-compose up -d`

## References

- [servercontainers/samba](https://github.com/ServerContainers/samba)
- [servercontainers/netatalk](https://github.com/ServerContainers/netatalk)
- [servercontainers/avahi](https://github.com/ServerContainers/avahi)

## License

This configuration is provided as-is for personal and educational use.
