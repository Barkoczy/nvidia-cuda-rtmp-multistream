# Hardware Report

## System Overview
- **Report Date**: 2025-11-16
- **Hostname**: homelab
- **Chassis Type**: Desktop
- **SMBIOS Version**: 3.3.0

---

## Motherboard

### Board Information
- **Manufacturer**: ASUSTeK COMPUTER INC.
- **Model**: TUF GAMING B550-PLUS
- **Version**: Rev X.0x
- **Serial Number**: 221112290400197
- **Asset Tag**: Default string
- **Type**: Motherboard
- **Form Factor**: ATX

### Features
- Board is a hosting board
- Board is replaceable
- Integrated onboard video device

### Chipset
- **Platform**: AMD B550
- **Socket**: AM4
- **Chipset Family**: AMD 500 Series

---

## Processor (CPU)

### Model Information
- **Processor**: AMD Ryzen 7 5700X 8-Core Processor
- **Vendor**: AuthenticAMD
- **Architecture**: Zen 3 (Vermeer)
- **CPU Family**: 25 (Zen)
- **Model**: 33
- **Stepping**: 2
- **Socket**: AM4
- **Microcode**: 0xa201210

### Performance Specifications
- **Physical Cores**: 8
- **Threads**: 16 (2 threads per core)
- **Base Clock**: 2200 MHz
- **Max Boost Clock**: 3600 MHz (advertised 4650 MHz)
- **Current Speed**: 3600 MHz
- **External Clock**: 100 MHz
- **Voltage**: 1.1V
- **BogoMIPS**: 7199.86

### Cache Hierarchy
- **L1d Cache**: 256 KiB (8 instances, 32 KiB per core)
- **L1i Cache**: 256 KiB (8 instances, 32 KiB per core)
- **L2 Cache**: 4 MiB (8 instances, 512 KiB per core)
- **L3 Cache**: 32 MiB (1 instance, shared)
- **Total Cache**: 36.5 MiB

### CPU Features
- **64-bit**: Yes (x86_64)
- **Operating Modes**: 32-bit, 64-bit
- **Byte Order**: Little Endian
- **Address Sizes**: 48 bits physical, 48 bits virtual
- **Virtualization**: AMD-V (SVM)
- **NUMA**: Single node (node0)

### Instruction Sets
- **FPU**: Floating-point unit on-chip
- **MMX**: MMX technology
- **SSE**: SSE, SSE2, SSSE3, SSE4.1, SSE4.2, SSE4a
- **AVX**: AVX, AVX2, F16C, FMA
- **AES-NI**: Hardware AES encryption
- **SHA-NI**: Hardware SHA acceleration
- **RDRAND**: Hardware random number generator
- **RDSEED**: Hardware random seed generator
- **VAES**: Vector AES
- **VPCLMULQDQ**: Vector carry-less multiplication

### Security Features
- **Execute Protection**: Yes (NX bit)
- **SMEP**: Supervisor Mode Execution Protection
- **SMAP**: Supervisor Mode Access Prevention
- **IBRS/IBPB**: Indirect Branch Restricted Speculation
- **STIBP**: Single Thread Indirect Branch Predictors
- **SSBD**: Speculative Store Bypass Disable

### Vulnerability Mitigations
- **Meltdown**: Not affected
- **Spectre v1**: Mitigated (usercopy/swapgs barriers and __user pointer sanitization)
- **Spectre v2**: Mitigated (Retpolines, IBPB conditional, IBRS_FW, STIBP always-on, RSB filling)
- **Spec Store Bypass**: Mitigated (disabled via prctl)
- **Spec RStack Overflow**: Mitigated (Safe RET)
- **L1TF**: Not affected
- **MDS**: Not affected
- **TAA**: Not affected
- **iTLB Multihit**: Not affected
- **MMIO Stale Data**: Not affected

### Power Management
- **Features**: Temperature sensor, Thermal trip, Hardware thermal management, Effective frequency reporting

---

## Memory (RAM)

### Total System Memory
- **Total RAM**: 32 GB (31.2 GiB)
- **Memory Type**: DDR4 SDRAM
- **Memory Speed**: 3200 MT/s
- **Configuration**: Dual Channel
- **ECC**: None (Unbuffered)

### Memory Modules

#### DIMM_A1 (Bank 0)
- **Status**: Empty (No Module Installed)

#### DIMM_A2 (Bank 1)
- **Size**: 16 GB
- **Type**: DDR4
- **Speed**: 3200 MT/s (Configured: 3200 MT/s)
- **Manufacturer**: Corsair
- **Part Number**: CMK32GX4M2E3200C16
- **Serial Number**: 00000000
- **Module Type**: Synchronous Unbuffered (Unregistered)
- **Volatile Size**: 16 GB
- **Manufacturer ID**: Bank 3, Hex 0x9E

#### DIMM_B1 (Bank 2)
- **Status**: Empty (No Module Installed)

#### DIMM_B2 (Bank 3)
- **Size**: 16 GB
- **Type**: DDR4
- **Speed**: 3200 MT/s (Configured: 3200 MT/s)
- **Manufacturer**: Corsair
- **Part Number**: CMK32GX4M2E3200C16
- **Serial Number**: 00000000
- **Module Type**: Synchronous Unbuffered (Unregistered)
- **Volatile Size**: 16 GB
- **Manufacturer ID**: Bank 3, Hex 0x9E

### Memory Configuration Summary
- **Populated Slots**: 2 of 4 (DIMM_A2, DIMM_B2)
- **Available Slots**: 2 (DIMM_A1, DIMM_B1)
- **Maximum Capacity**: 128 GB (4x 32GB DDR4-3200)
- **Hugepage Size**: 2048 KB

### Current Memory Usage
- **Total**: 32,736,128 KB (31.2 GiB)
- **Available**: 27,056,020 KB (25.8 GiB)
- **Free**: 341,668 KB (333 MiB)
- **Swap Total**: 8,388,604 KB (8 GiB)
- **Swap Used**: 0 KB

---

## Storage Devices

### NVMe SSD - Primary System Drive
- **Model**: WD_BLACK SN770 1TB
- **Serial Number**: 223766800826
- **Capacity**: 931.51 GiB (1 TB)
- **Interface**: NVMe PCIe Gen4
- **Device**: /dev/nvme0n1
- **Type**: SSD (Solid State Drive)

#### Partitions
```
/dev/nvme0n1p1 - 1 GB   - EFI System Partition (vfat)  - /boot/efi
/dev/nvme0n1p2 - 2 GB   - Linux filesystem (ext4)      - /boot
/dev/nvme0n1p3 - 928 GB - Linux LVM (ubuntu-vg)        - Root LV
```

#### LVM Configuration
- **Volume Group**: ubuntu-vg
- **Logical Volume**: ubuntu-lv (928.46 GiB)
- **Filesystem**: ext4
- **Mount Point**: /
- **Usage**: 108 GB used (13%), 768 GB available

### SATA SSD - Storage Drive 1
- **Model**: CT250MX500SSD1 (Crucial MX500)
- **Serial Number**: 1748E1072C19
- **Capacity**: 232.89 GiB (250 GB)
- **Interface**: SATA 6Gb/s
- **Device**: /dev/sda
- **Type**: SSD (Solid State Drive)

#### Partitions
```
/dev/sda1 - 232.8 GB - NTFS - Not mounted
```

### SATA SSD - Storage Drive 2
- **Model**: Crucial_CT275MX300SSD1
- **Serial Number**: 1639140A2C2A
- **Capacity**: 256.17 GiB (275 GB)
- **Interface**: SATA 6Gb/s
- **Device**: /dev/sdb
- **Type**: SSD (Solid State Drive)

#### Partitions
```
/dev/sdb1 - 1007 KB  - BIOS boot partition
/dev/sdb2 - 1 GB     - EFI System Partition
/dev/sdb3 - 255.2 GB - Linux LVM (pve-OLD-9301F08A)
```

#### Legacy LVM Configuration (Proxmox)
- **Volume Group**: pve-OLD-9301F08A
- **Purpose**: Previous Proxmox VE installation
- **Contains**: Multiple VM disks and cloud-init images
  - swap - 8 GB
  - root - 73.79 GB
  - data pool - 154.2 GB (thin-provisioned)
  - VM disks (vm-100, vm-101, vm-102, vm-5000)

### Storage Controllers

#### SATA Controller
- **Model**: AMD 500 Series Chipset SATA Controller
- **PCI Address**: 01:00.1
- **Ports**: 8x SATA III (6 Gb/s)
- **RAID Support**: Yes (0, 1, 10)

#### NVMe Controller
- **Built into CPU**: AMD Matisse (Ryzen 5000 series)
- **PCIe Lanes**: x4 Gen4 per M.2 slot
- **Slots**: 2x M.2 slots (1 populated)

---

## Graphics Card (GPU)

### NVIDIA GeForce GTX 1060 6GB
- **Model**: NVIDIA GP106 (Pascal architecture)
- **Manufacturer**: MSI (Micro-Star International)
- **Revision**: a1
- **VRAM**: 6GB GDDR5
- **PCI Slot**: 07:00.0
- **IOMMU Group**: 14

#### Device IDs
- **Vendor ID**: 10DE (NVIDIA)
- **Device ID**: 1C03
- **Subsystem Vendor**: 1462 (MSI)
- **Subsystem Device**: 3281

#### Memory Configuration
- **Memory Region 0**: 16 MB @ 0xfb000000 (32-bit, non-prefetchable)
- **Memory Region 1**: 256 MB @ 0xd0000000 (64-bit, prefetchable)
- **Memory Region 2**: 32 MB @ 0xe0000000 (64-bit, prefetchable)
- **I/O Ports**: 128 ports @ 0xe000
- **Expansion ROM**: 128 KB @ 0x000c0000 (disabled)

#### Driver
- **Driver in Use**: nvidia (proprietary)
- **Driver Version**: 535.274.02
- **Available Modules**: nvidiafb, nouveau, nvidia_drm, nvidia

#### Features
- **CUDA Cores**: 1280
- **CUDA Capability**: 6.1
- **Hardware Encoding**: NVENC (H.264, H.265)
- **Hardware Decoding**: NVDEC (H.264, H.265, VP9)
- **DirectX**: 12
- **OpenGL**: 4.6
- **Vulkan**: 1.3

### GPU Audio Controller
- **Model**: GP106 High Definition Audio Controller
- **PCI Address**: 07:00.1
- **Purpose**: HDMI/DisplayPort audio output
- **Revision**: a1

**See GPU.md for complete GPU specifications**

---

## Network Controllers

### Ethernet Controller
- **Model**: Realtek RTL8125 2.5GbE Controller
- **Manufacturer**: Realtek Semiconductor Co., Ltd.
- **Revision**: 05
- **PCI Address**: 06:00.0
- **Subsystem**: ASUSTeK Computer Inc.
- **IOMMU Group**: 13

#### Network Interface
- **Interface Name**: enp6s0
- **MAC Address**: c8:7f:54:09:ee:2e
- **Speed**: 1000 Mb/s (1 Gigabit)
- **Duplex**: Full Duplex
- **Port Type**: Twisted Pair (RJ-45)
- **Link Status**: Up
- **Auto-negotiation**: Enabled
- **MTU**: 1500

#### Capabilities
- **Maximum Speed**: 2.5 Gigabit Ethernet
- **Current Speed**: 1 Gigabit (limited by switch/link partner)
- **Wake-on-LAN**: Supported
- **Jumbo Frames**: Supported

#### Driver
- **Kernel Driver**: r8169
- **Kernel Module**: r8169

#### Memory Regions
- **I/O Ports**: 256 ports @ 0xf000
- **Memory Region 0**: 64 KB @ 0xfc500000
- **Memory Region 1**: 16 KB @ 0xfc510000

---

## Audio Devices

### NVIDIA HDMI/DisplayPort Audio
- **Model**: GP106 High Definition Audio Controller
- **Type**: GPU-integrated audio
- **PCI Address**: 07:00.1
- **Purpose**: Digital audio output via HDMI/DisplayPort

### AMD HD Audio Controller
- **Model**: Starship/Matisse HD Audio Controller
- **Manufacturer**: Advanced Micro Devices, Inc.
- **PCI Address**: 09:00.4
- **Subsystem**: ASUSTeK Computer Inc.
- **IOMMU Group**: 19
- **Memory**: 32 KB @ 0xfc400000

#### Driver
- **Kernel Driver**: snd_hda_intel
- **Kernel Module**: snd_hda_intel

#### Features
- **Codec**: Realtek ALC1200 (motherboard audio)
- **Channels**: 7.1 surround sound
- **Audio Jacks**: Front, rear, center/sub, side, microphone, line-in
- **S/PDIF**: Optical and coaxial digital output

---

## USB Controllers

### AMD 500 Series Chipset USB Controller
- **Model**: AMD 500 Series Chipset USB 3.1 XHCI Controller
- **PCI Address**: 01:00.0
- **Type**: USB 3.1 Gen 2 (10 Gbps)
- **Ports**: Multiple USB 3.1 ports

### AMD Matisse USB Controller
- **Model**: AMD Matisse USB 3.0 Host Controller
- **PCI Address**: 09:00.3
- **Type**: USB 3.0 (5 Gbps)
- **Ports**: Additional USB 3.0 ports

### Connected USB Devices
```
Bus 001:
  - Root Hub (USB 2.0)
  - ASUS AURA LED Controller (RGB lighting control)
  - Genesys Logic Hub

Bus 002:
  - Root Hub (USB 3.0)

Bus 003:
  - Root Hub (USB 2.0)

Bus 004:
  - Root Hub (USB 3.0)
```

---

## BIOS/UEFI Firmware

### BIOS Information
- **Vendor**: American Megatrends Inc. (AMI)
- **Version**: 2803
- **Release Date**: 04/27/2022
- **BIOS Revision**: 5.17
- **ROM Size**: 16 MB
- **Address**: 0xF0000
- **Runtime Size**: 64 KB
- **Firmware Age**: 3 years, 6 months, 2 weeks

### BIOS Features
- **UEFI Boot**: Supported
- **Secure Boot**: Available
- **PCI Support**: Yes
- **USB Legacy**: Supported
- **Boot from CD**: Supported
- **Network Boot**: Available
- **ACPI**: Supported
- **SMBIOS**: Version 3.3.0

### Boot Capabilities
- Selectable boot devices
- BIOS is upgradeable
- Boot specification supported
- Targeted content distribution

### BIOS Languages
- **Available Languages**: 9 (English, French, German, Spanish, Russian, Japanese, Korean, Chinese Traditional, Chinese Simplified)
- **Current Language**: English (en|US|iso8859-1)

---

## PCI Express Layout

### Root Complex
- **Type**: AMD Starship/Matisse Root Complex
- **IOMMU**: AMD IOMMU present
- **Manufacturer**: AMD

### PCI Express Bridges
```
00:00.0 - Root Complex
00:01.2 - GPP Bridge → Chipset devices (USB, SATA, Ethernet)
00:03.1 - GPP Bridge → NVIDIA GPU (x16 slot)
00:07.1 - Internal GPP Bridge → Reserved
00:08.1 - Internal GPP Bridge → NVMe, Audio
```

### PCIe Slot Configuration
- **PCIe x16 Slot 1**: NVIDIA GeForce GTX 1060 (07:00.0)
- **PCIe x16 Slot 2**: Empty (mechanical x16, electrical x4)
- **PCIe x1 Slots**: Empty
- **M.2 Slot 1 (PCIe)**: WD Black SN770 1TB NVMe
- **M.2 Slot 2**: Empty

### IOMMU Groups
- **Total Groups**: 19+
- **GPU Isolation**: IOMMU Group 14 (suitable for passthrough)
- **Ethernet**: IOMMU Group 13
- **USB Controllers**: Separate groups

---

## Chipset Details

### AMD B550 Chipset
- **Manufacturer**: AMD
- **Series**: 500 Series
- **Generation**: Zen 3 support
- **PCIe Support**: PCIe 4.0

### Integrated Components
- **SMBus Controller**: AMD FCH SMBus Controller (revision 61)
- **ISA Bridge**: AMD FCH LPC Bridge (revision 51)
- **Data Fabric**: AMD Matisse/Vermeer Data Fabric (Functions 0-5)

### Chipset Features
- PCIe 4.0 support (CPU lanes)
- PCIe 3.0 support (chipset lanes)
- USB 3.2 Gen 2 (10 Gbps)
- SATA III (6 Gbps)
- NVMe support
- AMD StoreMI technology

---

## Power Supply
- **Type**: ATX
- **Number of Power Cords**: 1
- **State**: Safe
- **Thermal State**: Safe

---

## Hardware Summary

### Processing
- **CPU**: AMD Ryzen 7 5700X (8C/16T @ 3.6 GHz)
- **GPU**: NVIDIA GTX 1060 6GB
- **RAM**: 32 GB DDR4-3200 (Dual Channel)

### Storage
- **Primary**: 1TB WD Black SN770 NVMe SSD
- **Secondary**: 250GB Crucial MX500 SATA SSD
- **Tertiary**: 275GB Crucial MX300 SATA SSD (legacy Proxmox)
- **Total Storage**: ~1.5 TB

### Connectivity
- **Ethernet**: 2.5 GbE (Realtek RTL8125)
- **USB**: USB 3.1 Gen 2 + USB 3.0
- **Audio**: 7.1 HD Audio (ALC1200)

### Expansion
- **RAM Slots**: 2 of 4 used (32 GB installed, 128 GB max)
- **PCIe Slots**: 1 of 3 used (GPU)
- **M.2 Slots**: 1 of 2 used (NVMe SSD)
- **SATA Ports**: 2 of 8 used (2x SATA SSDs)

### Virtualization Support
- **AMD-V**: Enabled
- **IOMMU**: Enabled (19+ groups)
- **VT-d Equivalent**: Yes
- **Passthrough Ready**: Yes (GPU in isolated IOMMU group)

---

## Performance Characteristics

### CPU Performance
- **Total Threads**: 16
- **Max Boost**: 4.65 GHz (single core)
- **All-Core Boost**: 3.6 GHz
- **TDP**: 65W
- **Architecture**: Zen 3 (7nm)

### Memory Performance
- **Bandwidth**: ~51.2 GB/s (dual channel DDR4-3200)
- **Latency**: Optimized for Zen 3
- **Capacity**: 32 GB
- **Expandable**: Yes (up to 128 GB)

### Storage Performance
- **NVMe**: PCIe Gen4 x4 (~7000 MB/s read theoretical)
- **SATA SSDs**: Up to 560 MB/s read
- **Total IOPS**: High (NVMe: 1M+ IOPS)

### Network Performance
- **Max Ethernet Speed**: 2.5 Gbps
- **Current Link**: 1 Gbps
- **Latency**: Low (wired connection)

---

## Hardware Monitoring

### Sensors Status
- **lm-sensors**: Not configured
- **CPU Temperature**: Available via k10temp module
- **NVME Temperature**: Available via nvme-cli
- **GPU Temperature**: Available via nvidia-smi

### Thermal Management
- **CPU**: Integrated thermal management
- **Motherboard**: Hardware monitoring supported
- **Fan Control**: PWM fan headers available

---

*Report generated automatically on 2025-11-16*
