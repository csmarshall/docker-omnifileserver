# Docker Omni File Server

Unified management for multiple file-serving protocols (SMB/CIFS and AFP) via Docker. One config, multiple daemons.

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
docker-omnifileserver/
├── manage.sh              # Management script (add users, shares, apply changes)
├── generate-compose.sh    # Generates docker-compose.yml from config files
├── users.conf             # User definitions (without passwords)
├── shares.conf            # Share definitions
├── .env                   # General config (optional, 644)
├── .env.passwords         # Passwords only (chmod 600, git-ignored)
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

### Alternative Organization (Optional)

If you prefer to organize files by type (e.g., `/opt/sw/<project>` for configs, `/opt/sw/docker-compose/<project>` for compose files):

```bash
# Install to /opt/sw/omnifileserver/
cd /opt/sw
git clone https://github.com/yourusername/docker-omnifileserver.git omnifileserver
cd omnifileserver
./manage.sh init

# After init, symlink the compose file to your preferred location
mkdir -p /opt/sw/docker-compose/omnifileserver
ln -s /opt/sw/omnifileserver/docker-compose.yml /opt/sw/docker-compose/omnifileserver/

# Run docker-compose from either location
cd /opt/sw/docker-compose/omnifileserver
docker-compose up -d
```

**Structure:**
```
/opt/sw/omnifileserver/              # All configs in one place
├── manage.sh, generate-compose.sh
├── users.conf, shares.conf, .env
├── docker-compose.yml               # Generated here
├── config/                          # Runtime configs
└── shares/                          # Data (or symlink to /data)

/opt/sw/docker-compose/omnifileserver/
└── docker-compose.yml -> /opt/sw/omnifileserver/docker-compose.yml  # Symlink
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
- Passwords stored in `.env.passwords` file with `chmod 600` permissions
- `.env.passwords` is git-ignored (never committed)
- General config can go in `.env` (chmod 644, optionally tracked)
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

**Using absolute paths for existing directories:**

You can share directories from anywhere on your system:

```bash
# Share an existing directory with absolute path
./manage.sh add-share movies /mnt/storage/movies ro alice,bob "Movie Collection"

# Share from external drive
./manage.sh add-share backup /media/backup-drive rw alice "Backup Drive"
```

The script will:
- Automatically mount absolute paths as Docker volumes
- Verify the directory exists (offer to create if it doesn't)
- Work alongside relative paths (./shares/*) without conflict

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

#### 5. Set Up Service Discovery (Optional but Recommended)

Enable automatic server discovery in Finder and network browsers:

```bash
./manage.sh setup-avahi
```

This command:
- Auto-detects your OS (macOS/Linux)
- Checks if Avahi is installed
- Provides platform-specific installation instructions
- Shows exact commands to copy the service file

**What you get:**
- Server appears automatically in Finder's Network sidebar
- No need to manually type `smb://hostname`
- Modern Mac Pro rack-mount icon in macOS

**If you skip this step:**
- Services still work fine
- You'll need to manually connect: `smb://hostname` or `afp://hostname`
- Server won't appear automatically in network browsers

See the wizard output for your platform's specific instructions.

#### 6. Verify Services

```bash
# Check containers are running
docker-compose ps

# Check logs
docker-compose logs -f

# Test SMB from Linux/macOS
smbclient -L localhost -N

# Test AFP from macOS Finder
# Open Finder → Go → Connect to Server → afp://hostname

# Verify Avahi is advertising services (if you set it up)
# Linux:
avahi-browse -a

# macOS:
dns-sd -B _smb._tcp
dns-sd -B _afpovertcp._tcp
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

# Change a user's password
./manage.sh change-password username
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

## Understanding Users and Permissions

**Important:** File share users are NOT the same as system users.

### How User Authentication Works

When you create a user with `./manage.sh add-user alice 1000 1000`:

1. **Samba/AFP Authentication** - Creates a file sharing account
   - Alice can authenticate to SMB/AFP shares with her password
   - Password stored in **plaintext** in `.env.passwords` (protected by chmod 600)
   - User is NOT added to `/etc/passwd` (not a system user)

2. **File System Permissions** - Uses UID/GID for file access
   - Container processes run as the configured UID (1000 in this case)
   - When accessing files, the kernel checks numeric UID/GID, not username
   - The UID must match the ownership of files on the host filesystem

### Why UIDs Must Match

Docker containers share the host's kernel. File permissions are **numeric**, not name-based:

```bash
# Host filesystem
$ ls -ln /storage/scanner
drwxr-xr-x  2 1001  1003  /storage/scanner

# If you configure alice as UID 1000
→ Container process runs as UID 1000
→ Tries to access files owned by UID 1001
→ RESULT: Permission denied ❌

# If you configure alice as UID 1001
→ Container process runs as UID 1001
→ Accesses files owned by UID 1001
→ RESULT: Success ✅
```

**Key insight:** The username doesn't matter for file permissions - only the numeric UID/GID.

### Best Practices

**When sharing files owned by a system user:**

```bash
# 1. Find the system user's UID/GID
$ id alice
uid=501(alice) gid=20(staff)

# 2. Create file share user with matching UID/GID
$ ./manage.sh add-user alice 501 20

# 3. Files at /home/alice/ owned by 501:20 are now accessible
```

**When sharing files with custom ownership:**

```bash
# 1. Decide on UID/GID (e.g., 1000:1000)
$ ./manage.sh add-user media 1000 1000

# 2. Set ownership on share directory
$ sudo chown -R 1000:1000 /mnt/storage/media
```

### Usernames Can (and Should) Match

While usernames don't affect permissions, matching them helps organization:

- **System user:** `alice` (UID 501) - logs into the server
- **File share user:** `alice` (UID 501) - accesses shares via SMB/AFP
- Different authentication systems, same UID for file access
- Makes it clear who owns what files

### Password Security Model

**⚠️ File share passwords are stored in plaintext:**

```bash
# .env.passwords contents
PASSWORD_alice=mypassword123
PASSWORD_bob=bobsecret456
```

**Protection:**
- File permissions: `chmod 600` (only file owner can read)
- Git-ignored: Won't be committed to repositories
- Private: Not visible in command history (prompted securely)

**Why plaintext?**
- ServerContainers Samba/AFP images require passwords as environment variables
- Docker doesn't automatically hash environment variables
- This is a limitation of the underlying container images

**Security best practices:**
- ✅ Use **different passwords** for file sharing vs system login
- ✅ System passwords (in `/etc/shadow`) are hashed and very secure
- ✅ File share passwords (in `.env.passwords`) are plaintext but private
- ✅ If someone gains root access to your server, they can read both anyway
- ✅ For home/small office use, this security model is acceptable
- ⚠️ For enterprise use, consider additional security layers (VPN, encrypted filesystems)

### Further Reading

- [Understanding how uid and gid work in Docker containers](https://medium.com/@mccode/understanding-how-uid-and-gid-work-in-docker-containers-c37a01d01cf) - Excellent explanation of Docker UID/GID mapping
- [Understanding the Docker USER Instruction](https://www.docker.com/blog/understanding-the-docker-user-instruction/) - Official Docker documentation
- [Samba Users, Security, and Domains](https://www.oreilly.com/openbook/samba/book/ch06_01.html) - How Samba authentication works
- [Samba File Access Controls](https://www.samba.org/samba/docs/old/Samba3-HOWTO/AccessControls.html) - Unix permissions with Samba

## Configuration Options

### Configuration Files

**users.conf** - User definitions (format: `username:uid:gid:description`)
- Passwords are stored separately in `.env.passwords` (plaintext, chmod 600)
- UIDs/GIDs should match file ownership on your host system (see "Understanding Users and Permissions" above)

**shares.conf** - Share definitions (format: `name:path:rw|ro:users:comment`)
- Automatically synced to both SMB and AFP
- Users can be comma-separated or 'all'
- Supports both relative (`/shares/data`) and absolute paths (`/mnt/storage`)

**.env** - General configuration (optional)
- Format: `KEY=value`
- chmod 644 (can be tracked in git if desired)
- For non-sensitive settings

**.env.passwords** - Password storage (auto-managed by scripts)
- Format: `PASSWORD_username=password`
- chmod 600 for security (only owner can read)
- Git-ignored (never committed)
- Loaded via `env_file` directive in docker-compose.yml

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
Configure during `init` or change via `./manage.sh configure`:
- `MacPro7,1@ECOLOR=226,226,224` - 2019 Mac Pro rack-mount (default, recommended)
- `MacPro` - Classic Mac Pro tower
- `MacPro6,1` - 2013 Mac Pro (trash can)
- `Xserve` - Xserve (broken in macOS Big Sur+)
- `TimeCapsule` - Time Capsule
- `iMac`, `Macmini`, etc.

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

1. Run the setup wizard: `./manage.sh setup-avahi`
2. Verify host Avahi is running:
   - Linux: `systemctl status avahi-daemon`
   - macOS: `pgrep mDNSResponder`
3. Check service file exists: `ls /etc/avahi/services/omnifileserver.service`
4. Verify services are being advertised:
   - Linux: `avahi-browse -a`
   - macOS: `dns-sd -B _smb._tcp`
5. Ensure firewall allows mDNS (port 5353/udp)

**If you skipped Avahi setup:** Manually connect using `smb://hostname` or `afp://hostname`

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
2. Copy entire `docker-omnifileserver/` directory to new host:
   ```bash
   rsync -av docker-omnifileserver/ newhost:/path/to/docker-omnifileserver/
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
6. Set up Avahi on new host for service discovery:
   ```bash
   ./manage.sh setup-avahi
   ```
7. Start services: `docker-compose up -d`

## References

- [ServerContainers Samba](https://github.com/ServerContainers/samba) - Docker image for Samba/SMB
- [ServerContainers Netatalk](https://github.com/ServerContainers/netatalk) - Docker image for AFP
- [Avahi](https://www.avahi.org/) - mDNS/DNS-SD service discovery (runs on host)

## License

This configuration is provided as-is for personal and educational use.
