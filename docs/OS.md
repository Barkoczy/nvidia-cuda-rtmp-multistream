# Operating System Report

## System Information
- **Hostname**: homelab
- **Machine ID**: b1da143216d24961a3527a685526e084
- **Boot ID**: 92c137527e5c4915bceede1984648e9f
- **Report Date**: 2025-11-16

## Operating System Details

### Distribution
- **OS Name**: Ubuntu
- **Version**: 24.04.3 LTS (Noble Numbat)
- **Codename**: noble
- **Pretty Name**: Ubuntu 24.04.3 LTS
- **Distribution ID**: ubuntu
- **Base System**: Debian-based (ID_LIKE=debian)

### Official Links
- **Home URL**: https://www.ubuntu.com/
- **Support URL**: https://help.ubuntu.com/
- **Bug Reports**: https://bugs.launchpad.net/ubuntu/
- **Privacy Policy**: https://www.ubuntu.com/legal/terms-and-policies/privacy-policy

## Kernel Information

### Kernel Version
- **Full Version**: Linux 6.8.0-86-generic
- **Build Date**: Mon Sep 22 18:03:36 UTC 2025
- **Compiler**: x86_64-linux-gnu-gcc-13 (Ubuntu 13.3.0-6ubuntu2~24.04) 13.3.0
- **Linker**: GNU ld (GNU Binutils for Ubuntu) 2.42
- **Builder**: buildd@lcy02-amd64-031

### Kernel Features
- **Kernel Type**: SMP PREEMPT_DYNAMIC
- **Architecture**: x86_64 x86_64 x86_64 GNU/Linux
- **Boot Parameters**: `BOOT_IMAGE=/vmlinuz-6.8.0-86-generic root=/dev/mapper/ubuntu--vg-ubuntu--lv ro`

## System Architecture

### Platform
- **Architecture**: x86-64 (amd64)
- **CPU Mode**: 64-bit
- **Foreign Architectures**: None
- **Package Architecture**: amd64

### Hardware Information
- **Hardware Vendor**: ASUS
- **Hardware Model**: TUF GAMING B550-PLUS
- **Chassis Type**: Desktop 🖥️
- **Firmware Version**: 2803
- **Firmware Date**: Wed 2022-04-27
- **Firmware Age**: 3 years 6 months 2 weeks 6 days

## System Uptime and Boot

### Current Uptime
- **System Started**: 2025-10-28 15:57:30
- **Current Uptime**: 2 weeks, 4 days, 8 hours, 44 minutes
- **Boot Date**: Tue Oct 28 15:57:36 UTC 2025

### Boot Performance
- **Firmware Time**: 32.210s
- **Bootloader Time**: 11.333s
- **Kernel Time**: 5.687s
- **Userspace Time**: 11.084s
- **Total Boot Time**: 1min 316ms
- **Graphical Target Reached**: 11.067s in userspace

### Boot History
```
Current Boot: 92c137527e5c4915bceede1984648e9f (Tue 2025-10-28 15:57:36 UTC - still running)
Previous Boot: 463f569acc4c47c692845dfa61bd77b7 (Sun 2025-09-28 13:33:05 UTC - Tue 2025-10-28 15:56:37 UTC)
Earlier Boot: 6e5271b720d346a68b0fe7546902f6b0 (Sun 2025-09-28 13:21:49 UTC - Sun 2025-09-28 13:32:21 UTC)
```

### Reboot History
```
Current:  6.8.0-86-generic (Tue Oct 28 15:57) - still running
Previous: 6.8.0-84-generic (Sun Sep 28 13:33) - lasted 30 days 2 hours 23 minutes
Earlier:  6.8.0-84-generic (Sun Sep 28 13:21) - lasted 10 minutes
```

## Time and Localization

### Time Settings
- **Local Time**: Sun 2025-11-16 00:41:48 UTC
- **Universal Time**: Sun 2025-11-16 00:41:48 UTC
- **RTC Time**: Sun 2025-11-16 00:41:48
- **Time Zone**: Etc/UTC (UTC, +0000)
- **System Clock Synchronized**: Yes
- **NTP Service**: Active
- **RTC in Local TZ**: No

### Locale Configuration
- **LANG**: en_US.UTF-8
- **LC_CTYPE**: en_US.UTF-8
- **LC_NUMERIC**: en_US.UTF-8
- **LC_TIME**: en_US.UTF-8
- **LC_COLLATE**: en_US.UTF-8
- **LC_MONETARY**: en_US.UTF-8
- **LC_MESSAGES**: en_US.UTF-8
- **LC_PAPER**: en_US.UTF-8
- **All Other Categories**: en_US.UTF-8

## Storage Configuration

### Filesystem Layout

#### Root Filesystem
```
Device: /dev/mapper/ubuntu--vg-ubuntu--lv
Mount: /
Type: ext4
Size: 914G
Used: 108G (13%)
Available: 768G
Options: rw,relatime
```

#### Boot Partition
```
Device: /dev/nvme0n1p2
Mount: /boot
Type: ext4
Size: 2.0G
Used: 224M (13%)
Available: 1.6G
Options: rw,relatime
```

#### EFI System Partition
```
Device: /dev/nvme0n1p1
Mount: /boot/efi
Type: vfat
Size: N/A
Options: rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=iso8859-1,shortname=mixed,errors=remount-ro
```

### Swap Configuration
```
Name: /swap.img
Type: file
Size: 8G
Used: 0B
Priority: -2
```

### Storage Technology
- **Volume Management**: LVM (Logical Volume Manager)
- **Volume Group**: ubuntu-vg
- **Logical Volume**: ubuntu-lv
- **Primary Storage**: NVMe SSD

## Network Configuration

### Network Interfaces

#### Loopback Interface (lo)
- **Status**: UP
- **MTU**: 65536
- **IPv4**: 127.0.0.1/8

#### Primary Network Interface (enp6s0)
- **Status**: UP
- **MTU**: 1500
- **Queue**: fq_codel
- **IPv4**: 10.0.1.42/24 (DHCP, metric 100)
- **Broadcast**: 10.0.1.255

#### Docker Bridge (docker0)
- **Status**: UP
- **MTU**: 1500
- **IPv4**: 172.17.0.1/16
- **Broadcast**: 172.17.255.255

#### Custom Docker Network (br-95f0a5e3dd65)
- **Status**: UP
- **MTU**: 1500
- **IPv4**: 172.18.0.1/16
- **Broadcast**: 172.18.255.255

#### WireGuard VPN (wg0)
- **Status**: UP
- **MTU**: 1420
- **Type**: POINTOPOINT
- **IPv4**: 10.100.0.10/24

#### Virtual Ethernet Interfaces
- veth6593a4e@if2 (connected to br-95f0a5e3dd65)
- vethb513482@if2 (connected to docker0)
- veth089059f@if2 (connected to docker0)
- vethc2177c3@if2 (connected to docker0)
- veth21fbe8c@if2 (connected to docker0)

### Listening Services (Selected)

| Port | Protocol | Service |
|------|----------|---------|
| 22 | TCP | SSH (OpenBSD Secure Shell) |
| 53 | TCP | DNS (systemd-resolved) |
| 139 | TCP | SMB NetBIOS |
| 445 | TCP | SMB/CIFS (Samba) |
| 3128 | TCP | Proxy/Squid |
| 3702 | TCP | WS-Discovery |
| 5355 | TCP | LLMNR |
| 8096 | TCP | Emby Media Server |

## Package Management

### Installed Packages
- **Total APT Packages**: 912
- **Package Manager**: APT (Advanced Package Tool)
- **Package Format**: DEB

### Snap Packages
```
core22  (revision 2139)  - latest/stable from canonical
snapd   (revision 25577) - latest/stable from canonical
yq      (v4.46.1)        - latest/stable from mikefarah
```

## Running Services

### Systemd Configuration
- **Default Target**: graphical.target
- **Total Enabled Services**: 60
- **Init System**: systemd

### Key Running Services

#### Container & Virtualization
- **containerd.service** - containerd container runtime
- **docker.service** - Docker Application Container Engine

#### System Services
- **systemd-journald.service** - Journal Service
- **systemd-logind.service** - User Login Management
- **systemd-networkd.service** - Network Configuration
- **systemd-resolved.service** - Network Name Resolution
- **systemd-timesyncd.service** - Network Time Synchronization
- **systemd-udevd.service** - Rule-based Manager for Device Events

#### Network Services
- **ssh.service** - OpenBSD Secure Shell server
- **nmbd.service** - Samba NMB Daemon
- **smbd.service** - Samba SMB Daemon
- **wsdd2.service** - WSD/LLMNR Discovery/Name Service Daemon

#### Hardware Services
- **nvidia-persistenced.service** - NVIDIA Persistence Daemon
- **ModemManager.service** - Modem Manager

#### Background Services
- **cron.service** - Regular background program processing daemon
- **rsyslog.service** - System Logging Service
- **snapd.service** - Snap Daemon
- **unattended-upgrades.service** - Unattended Upgrades

#### Device Management
- **dm-event.service** - Device-mapper event daemon
- **multipathd.service** - Device-Mapper Multipath Device Controller
- **udisks2.service** - Disk Manager
- **upower.service** - Daemon for power management

#### System Management
- **dbus.service** - D-Bus System Message Bus
- **polkit.service** - Authorization Manager

#### Terminal Services
- **getty@tty1.service** - Getty on tty1

#### User Services
- **user@1000.service** - User Manager for UID 1000

## Development Tools

### Programming Languages & Runtimes
- **Python**: 3.12.3

### Container Platform
- **Docker**: 29.0.0, build 3d4129b
- **containerd**: Active and running

## User Sessions

### Active Sessions
- **Total Active Sessions**: 4
- **Current Users**: 2 sessions for user 'ubuntu'

### Logged In Users
```
ubuntu   pts/0   2025-11-15 20:06 (from 10.0.1.40)
ubuntu   pts/1   2025-11-15 21:43 (from 10.0.1.40)
```

## Security Features

### System Security
- **IOMMU**: Enabled (GPU in group 14)
- **Secure Boot**: UEFI with firmware support
- **Automatic Updates**: Enabled (unattended-upgrades)

### Network Security
- **Firewall**: Not visible (may be configured)
- **WireGuard VPN**: Active and configured
- **SSH**: Running on port 22

## System Logs

### Journal Configuration
- **Boot History**: 3 recorded boots
- **wtmp begins**: Sun Sep 28 13:21:48 2025
- **Current Boot Session**: 2 weeks, 4 days, 8 hours

## Additional Features

### Virtualization & Containers
- **Docker**: Fully operational with multiple containers
- **Docker Networks**: Custom bridge networks configured
- **Virtual Ethernet**: Multiple veth pairs active

### File Sharing
- **Samba**: Active (SMB/CIFS file sharing)
- **Network Discovery**: WS-Discovery and LLMNR enabled

### Media Services
- **Emby Server**: Running on port 8096

### Monitoring & Logging
- **systemd Journal**: Active
- **rsyslog**: Running
- **systemd-timesyncd**: NTP synchronization active

## Performance Notes

- Fast boot time (~1 minute total)
- Efficient userspace initialization (11 seconds)
- Stable system (19 days uptime)
- Low disk usage (13% on root filesystem)
- No swap currently in use

---
*Report generated automatically on 2025-11-16*
