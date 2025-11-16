# NVIDIA GPU Report

## Server Information
- **Hostname**: ubuntu
- **Kernel Version**: 6.8.0-86-generic
- **Platform**: Linux x86_64
- **Report Date**: 2025-11-16

## GPU Hardware Details

### Basic Information
- **Model**: NVIDIA GeForce GTX 1060 6GB
- **GPU Architecture**: Pascal (GP106)
- **Revision**: a1
- **Manufacturer**: Micro-Star International Co., Ltd. (MSI)

### Device Identification
- **PCI Slot**: 07:00.0
- **Vendor ID**: 10DE (NVIDIA Corporation)
- **Device ID**: 1C03
- **Subsystem Vendor ID**: 1462 (MSI)
- **Subsystem Device ID**: 3281
- **IOMMU Group**: 14

### Memory Configuration
- **Total VRAM**: 6GB GDDR5
- **Memory Interface**: 192-bit
- **Memory Base Addresses**:
  - `0xfb000000` (32-bit, non-prefetchable, 16MB)
  - `0xd0000000` (64-bit, prefetchable, 256MB)
  - `0xe0000000` (64-bit, prefetchable, 32MB)

### PCI Express Configuration
- **PCI Slot Name**: 0000:07:00.0
- **Bus Master**: Enabled
- **Device Select**: Fast
- **Latency**: 0
- **IRQ**: 94
- **I/O Ports**: 0xe000 (size: 128)
- **Expansion ROM**: 0x000c0000 (disabled, 128KB)

### Audio Controller
- **PCI Slot**: 07:00.1
- **Device**: GP106 High Definition Audio Controller
- **Revision**: a1

## Driver Information

### NVIDIA Driver
- **Driver Version**: 535.274.02
- **Driver Release Date**: Thu Sep 4 22:13:52 UTC 2025
- **Architecture**: UNIX x86_64 Kernel Module
- **Kernel Module Location**: `/lib/modules/6.8.0-86-generic/kernel/nvidia-535srv/nvidia.ko`
- **Kernel Driver In Use**: nvidia

### Available Kernel Modules
- `nvidiafb` - NVIDIA framebuffer driver
- `nouveau` - Open-source NVIDIA driver
- `nvidia_drm` - NVIDIA DRM kernel module
- `nvidia` - Proprietary NVIDIA kernel module (active)

## Device Nodes

The following NVIDIA device nodes are present on the system:

```
/dev/nvidia0           - GPU device 0
/dev/nvidiactl         - NVIDIA control device
/dev/nvidia-modeset    - Mode setting device
/dev/nvidia-uvm        - Unified Virtual Memory device
/dev/nvidia-uvm-tools  - UVM tools device
```

## GPU Capabilities

### Pascal Architecture Features
- CUDA Capability: 6.1
- GPU Boost 3.0 technology
- Simultaneous Multi-Projection
- NVIDIA Ansel support
- NVIDIA GameWorks support
- NVIDIA G-SYNC compatible
- VR Ready

### Video Processing
- Hardware-accelerated video encoding (NVENC)
- Hardware-accelerated video decoding (NVDEC)
- H.264, H.265/HEVC support
- VP9 decode support

### Display Outputs
- Multiple display support
- Maximum resolution: 7680x4320 @ 60Hz
- HDR support

## Technical Specifications

### Compute Specifications
- **CUDA Cores**: 1280
- **Base Clock**: 1506 MHz
- **Boost Clock**: 1708 MHz
- **Memory Clock**: 8 Gbps (effective)
- **Memory Bandwidth**: 192 GB/s
- **TDP**: 120W

### Supported APIs
- DirectX 12
- OpenGL 4.6
- Vulkan 1.3
- CUDA Compute Capability 6.1

## System Integration

### Bus Configuration
- **PCI Class**: VGA compatible controller (0300)
- **Prog Interface**: 00 (VGA controller)
- **Bus Flags**: Bus master, fast devsel, latency 0

### Modalias
```
pci:v000010DEd00001C03sv00001462sd00003281bc03sc00i00
```

## Notes

- **nvidia-smi**: Not available in current environment (command not found)
- **Driver Status**: NVIDIA proprietary driver successfully loaded
- **IOMMU**: GPU is in IOMMU group 14 (suitable for GPU passthrough)
- **Device Access**: All required device nodes are present
- **Multi-GPU**: Single GPU configuration

## Usage Recommendations

This NVIDIA GeForce GTX 1060 6GB is well-suited for:
- Hardware-accelerated video transcoding (NVENC/NVDEC)
- CUDA-based computational tasks
- Machine learning inference (limited by 6GB VRAM)
- RTMP streaming with hardware encoding
- Container-based GPU workloads (with nvidia-docker)

## Additional Information

For detailed runtime statistics and monitoring, install and use `nvidia-smi` tool:
```bash
nvidia-smi
nvidia-smi -q  # Detailed query
nvidia-smi dmon  # Device monitoring
```

---
*Report generated automatically on 2025-11-16*
