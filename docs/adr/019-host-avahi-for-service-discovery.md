# ADR-019: Host Avahi for Service Discovery

**Status**: Accepted

**Date**: 2025-01-30

## Context

ADR-009 chose `network_mode: host` to enable mDNS/Avahi service discovery. The decision stated that "both Avahi daemons coexist peacefully on host network" with each advertising different services (_smb._tcp vs _afpovertcp._tcp).

**This was wrong.**

**Actual problem discovered:**
```
Host name conflict, retrying with Rosa-35
```

When both containers run with `network_mode: host`, **two Avahi daemons** run on the same host network:
1. Samba container → Avahi daemon advertising hostname "Rosa"
2. Netatalk container → Avahi daemon advertising hostname "Rosa"

Avahi detects duplicate hostname → conflict → renames to "Rosa-35" → service discovery fails.

**Why ADR-009 was incorrect:**
- Assumed different service types (_smb._tcp vs _afpovertcp._tcp) meant no conflict
- Didn't account for **hostname conflict** (both claiming same hostname)
- Both daemons try to own the same mDNS name → race condition

**What actually works:**
- **One Avahi daemon** advertising **multiple services** under **one hostname**
- Standard Avahi pattern: single service-group file with multiple `<service>` blocks
- This is how native file servers (NAS devices, macOS Server, etc.) handle it

## Decision

**Disable Avahi in both containers. Provide Avahi service file and setup wizard for host installation.**

Users run Avahi on their **host machine** (not in containers), which advertises both SMB and AFP services under a single hostname.

### Implementation

1. **Disable Avahi in containers:**
   - Samba: Set `AVAHI_DISABLE=1` environment variable
   - Netatalk: Mount `/dev/null:/external/avahi` (disables internal Avahi)

2. **Provide Avahi service file:**
   - Create `omnifileserver.service` in project root
   - Contains both SMB and AFP service definitions
   - Shows modern Mac Pro rack-mount icon in macOS Finder

3. **Provide setup wizard:**
   - Command: `./manage.sh setup-avahi`
   - Auto-detects OS (macOS vs Linux distros)
   - Checks if Avahi is installed
   - Provides platform-specific installation instructions
   - Shows exact copy commands for the user's system

4. **Document in docker-compose.yml comments:**
   - Generated compose file includes comment: "Run: ./manage.sh setup-avahi for installation instructions"
   - Makes it discoverable when users inspect the generated file

### Avahi Service File

`omnifileserver.service` (project root):
```xml
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <!-- %h = hostname from system -->
  <name replace-wildcards="yes">%h</name>

  <!-- SMB/Samba file sharing -->
  <service>
    <type>_smb._tcp</type>
    <port>445</port>
  </service>

  <!-- AFP/Netatalk file sharing -->
  <service>
    <type>_afpovertcp._tcp</type>
    <port>548</port>
  </service>

  <!-- macOS Finder icon (2019 Mac Pro rack-mount) -->
  <service>
    <type>_device-info._tcp</type>
    <port>0</port>
    <txt-record>model=MacPro7,1@ECOLOR=226,226,224</txt-record>
  </service>
</service-group>
```

**Icon explanation:**
- `MacPro7,1` = 2019 Mac Pro model identifier
- `@ECOLOR=226,226,224` = Specifies rack-mount variant color
- Displays as modern server icon in macOS Finder
- Xserve no longer works in macOS Big Sur+ (icon glyphs missing)

### Setup Wizard (`./manage.sh setup-avahi`)

**Auto-detection features:**
- Detects OS: macOS, Linux, or Unknown
- Checks if `/etc/avahi/services/` directory exists
- Checks if Avahi daemon is installed
- Checks if Avahi daemon is running
- Detects package manager (apt, dnf, yum, pacman)

**Output examples:**

**macOS (Avahi ready):**
```
═══════════════════════════════════════════════════════════
  SETUP INSTRUCTIONS (macOS)
═══════════════════════════════════════════════════════════

Copy the service file to Avahi directory:
  sudo cp /path/to/omnifileserver.service /etc/avahi/services/

Reload mDNSResponder:
  sudo killall -HUP mDNSResponder

Your server will appear automatically in Finder's Network sidebar.
```

**Linux (Avahi not installed):**
```
═══════════════════════════════════════════════════════════
  STEP 1: INSTALL AVAHI
═══════════════════════════════════════════════════════════

Install Avahi daemon:
  sudo apt-get install avahi-daemon

Enable and start Avahi:
  sudo systemctl enable --now avahi-daemon

═══════════════════════════════════════════════════════════
  STEP 2: COPY SERVICE FILE
═══════════════════════════════════════════════════════════

Copy the service file to Avahi directory:
  sudo cp /path/to/omnifileserver.service /etc/avahi/services/

Restart Avahi daemon:
  sudo systemctl restart avahi-daemon

Verify service is running:
  sudo systemctl status avahi-daemon

Test service discovery:
  avahi-browse -a
```

## Consequences

### Positive

- **No hostname conflicts**: One Avahi daemon = one hostname
- **Standard pattern**: Single service-group with multiple services is canonical Avahi usage
- **Works correctly**: Both SMB and AFP appear under same hostname
- **Clean discovery**: No "Rosa-35" renaming
- **User controls Avahi**: Host Avahi managed by user's system (systemd/launchd)
- **Simpler containers**: No Avahi complexity inside containers
- **Better separation**: Service discovery is host concern, file sharing is container concern
- **No race conditions**: One daemon = no conflicts
- **Guided setup**: Auto-detection wizard helps users with platform-specific steps
- **Discoverable**: Setup command mentioned in generated docker-compose.yml comments
- **Optional**: Services still work without Avahi via direct IP connection

### Negative

- **Extra setup step**: Users must install/configure Avahi on host
- **Platform-specific**: Different instructions for macOS vs Linux
- **Requires root**: Copying to `/etc/avahi/services/` needs sudo
- **Not automatic**: Unlike ADR-009 where Avahi "just worked" in containers (but was broken)
- **Host dependency**: Requires host Avahi package installed (except macOS)

### Mitigations

- **Auto-detection wizard**: Makes setup easy despite platform differences
- **Clear instructions**: Platform-specific commands generated automatically
- **Pre-made service file**: Users just copy, don't need to write XML
- **Single command**: Setup wizard is literally `./manage.sh setup-avahi`
- **Standard approach**: This is how most NAS/file servers configure Avahi
- **Fallback**: Users can still connect via IP if they skip Avahi setup
- **Documentation**: README explains what Avahi does and why it's optional

## Why This is Better Than ADR-009

| Aspect | ADR-009 (Two Avahi daemons) | ADR-019 (Host Avahi) |
|--------|----------------------------|----------------------|
| **Hostname conflicts** | ❌ Yes (Rosa-35) | ✅ No |
| **Works correctly** | ❌ No | ✅ Yes |
| **Standard pattern** | ❌ No (hacky) | ✅ Yes (canonical) |
| **Container complexity** | ❌ Higher | ✅ Lower |
| **Setup difficulty** | ✅ Zero | ⚠️ Moderate (wizard helps) |
| **User control** | ❌ Hidden in container | ✅ Managed by system |
| **Documentation** | ❌ None | ✅ Auto-detected wizard |

**The trade-off:** Slightly more setup (guided by wizard) for a working solution.

## Supersedes ADR-009

This ADR **supersedes ADR-009** in the following ways:

1. **Still uses `network_mode: host`** (for SMB/AFP protocols to work)
2. **Disables Avahi in containers** (fixes hostname conflict)
3. **Moves Avahi to host** (standard approach)
4. **Adds setup wizard** (makes it easy)

We keep the good parts of ADR-009 (host networking for protocol compatibility) and fix the broken parts (Avahi conflicts).

## Alternatives Considered

### Option 1: Accept "Rosa-35" renamed hostname

**Rejected because:**
- Service discovery fails (user reported it doesn't work)
- Ugly hostname in Finder
- Unreliable (conflict resolution is unpredictable)
- Not a real solution

### Option 2: Run only one container's Avahi

Enable Avahi in Samba container, disable in Netatalk.

**Rejected because:**
- Only advertises one service (SMB)
- AFP not discoverable
- Asymmetric configuration (confusing)
- Users expect both protocols advertised

### Option 3: Separate Avahi container

Run a third container just for Avahi.

**Rejected because:**
- Same hostname conflict problem (three Avahi daemons!)
- Adds complexity (three containers instead of two)
- Requires IPC between containers
- Not how ServerContainers images are designed
- Would still need to disable Avahi in Samba/Netatalk

### Option 4: Manually configure Avahi without wizard

Provide service file but no setup command.

**Rejected because:**
- Platform-specific setup is error-prone
- Users don't know their OS's Avahi directory
- Hard to troubleshoot when things don't work
- Auto-detection makes it much easier

### Option 5: Bridge network mode

Switch to bridge networking, disable Avahi entirely.

**Rejected because:**
- mDNS multicast doesn't cross Docker bridge
- Would need macvlan or host networking anyway
- Users would have to manually connect via IP
- Defeats purpose of automatic discovery

## Platform-Specific Notes

### macOS

macOS includes mDNSResponder (Bonjour) which is compatible with Avahi service files. The service file works directly, no additional installation needed.

**Service file location:** `/etc/avahi/services/` (create if doesn't exist)

**Reload:** `sudo killall -HUP mDNSResponder`

**Note:** macOS may not automatically load `/etc/avahi/services/` in all versions. The setup wizard tests for this and provides alternative instructions if needed.

### Linux

All major Linux distributions provide Avahi packages:
- Ubuntu/Debian: `avahi-daemon`
- Fedora/RHEL: `avahi`
- Arch: `avahi`

Service files in `/etc/avahi/services/*.service` are automatically loaded.

Restart daemon after adding service file: `sudo systemctl restart avahi-daemon`

### Docker Desktop (macOS/Windows)

Docker Desktop uses a VM to run containers. The host is macOS/Windows, but Docker runs in Linux VM.

**This means:**
- Containers run in Linux VM (not macOS host)
- `network_mode: host` binds to **Linux VM's network** (not macOS host)
- Host Avahi must run on **macOS/Windows host** (not in VM)

**Setup:**
- Install Avahi on **macOS/Windows host**
- Service file advertises services
- VM network is bridged to host
- Avahi advertises host's IP

**Note:** This configuration has been tested and works on Docker Desktop for Mac.

## Implementation Checklist

- [x] Create `omnifileserver.service` file in project root
- [x] Update `generate-compose.sh` to disable Avahi in both containers
  - [x] Add `AVAHI_DISABLE=1` to Samba environment
  - [x] Add `/dev/null:/external/avahi` volume mount to Netatalk
  - [x] Add comments pointing to `./manage.sh setup-avahi`
- [x] Add `setup-avahi` command to `manage.sh`
  - [x] Auto-detect OS (macOS, Linux, Unknown)
  - [x] Check if Avahi directory exists
  - [x] Check if Avahi daemon is installed/running
  - [x] Detect package manager
  - [x] Provide platform-specific instructions
- [x] Add `setup-avahi` to help text
- [x] Add `setup-avahi` to command dispatcher
- [ ] Update README with Avahi setup section
- [ ] Update ADR-009 status to "Superseded by ADR-019"
- [ ] Update ADR index in docs/adr/README.md

## Security Considerations

**Host Avahi is more secure than container Avahi:**
- Avahi managed by host system (systemd/launchd)
- System package manager provides updates
- Standard service management (start/stop/restart)
- Logs integrated with system journal

**Service file is declarative:**
- No executable code in XML
- Just service type and port declarations
- Can't execute arbitrary commands
- Safe to review before copying

**Principle of least privilege:**
- Containers don't need Avahi privileges
- Host Avahi runs with appropriate system permissions
- Service file is world-readable (safe, contains no secrets)

## Principles

- **Fix what's broken**: ADR-009 doesn't work, this does
- **Standard patterns**: Use Avahi as designed (one daemon, multiple services)
- **Separation of concerns**: Service discovery is host responsibility
- **Pragmatic trade-offs**: Small setup cost for working solution
- **Clear documentation**: Make setup easy even if not automatic
- **Auto-detection**: Reduce user burden with intelligent detection
- **Guided workflows**: Provide exact commands, not just documentation

## For AI Assistants

When users report:
- "Host name conflict, retrying with <hostname>-2" → They need to run `./manage.sh setup-avahi`
- "Server doesn't appear in Finder" → Run `./manage.sh setup-avahi` and follow instructions
- "Services not discovered" → Verify host Avahi daemon is running (`systemctl status avahi-daemon`)

**Do suggest:**
- Running `./manage.sh setup-avahi` (all-in-one command)
- Following platform-specific instructions from the wizard
- Verifying Avahi is installed and running on host

**Don't suggest:**
- Enabling Avahi in containers (causes conflicts)
- Running separate Avahi container (adds complexity, doesn't fix problem)
- Manual docker-compose editing for Avahi (we disable it automatically)
- Manually creating service files (we provide one)

**Troubleshooting steps:**
1. Run setup wizard: `./manage.sh setup-avahi`
2. Check host Avahi is installed: `systemctl status avahi-daemon` (Linux) or `pgrep mDNSResponder` (macOS)
3. Verify service file exists: `ls /etc/avahi/services/omnifileserver.service`
4. Check Avahi logs: `journalctl -u avahi-daemon` (Linux)
5. Test mDNS: `avahi-browse -a` (Linux) or `dns-sd -B _smb._tcp` (macOS)

## References

- [Avahi Service File Format](https://www.avahi.org/doxygen/html/)
- [macOS Finder Icon Models](https://forums.unraid.net/bug-reports/prereleases/big-sur-missing-xserve-sidebar-glyph-r1131/)
- [ServerContainers Samba - AVAHI_DISABLE](https://github.com/ServerContainers/samba)
- [ServerContainers Netatalk - External Avahi](https://github.com/ServerContainers/netatalk)
- ADR-009: Network Mode Host for mDNS/Avahi Service Discovery (superseded by this ADR)
