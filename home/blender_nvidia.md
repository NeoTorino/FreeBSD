# FreeBSD — bhyve VM + NVIDIA + Blender Setup Guide

**Hardware:** Laptop with Intel HD 630 + NVIDIA GeForce GTX 1050 Ti Mobile (Optimus)
**Host OS:** FreeBSD
**Goal:** Run bhyve VM + Blender with NVIDIA GPU acceleration

---

## Table of Contents

1. [bhyve VM Setup](#1-bhyve-vm-setup)
2. [VM Configuration](#2-vm-configuration)
3. [Networking](#3-networking)
4. [NVIDIA GPU Passthrough — What We Tried and Why It Failed](#4-nvidia-gpu-passthrough)
5. [Blender on FreeBSD Host with NVIDIA](#5-blender-on-freebsd-host)
6. [rc.conf Final State](#6-rccconf-final-state)
7. [loader.conf Final State](#7-loaderconf-final-state)
8. [pf.conf Final State](#8-pfconf-final-state)
9. [Quick Reference — Daily Startup](#9-quick-reference--daily-startup)
10. [Lessons Learned](#10-lessons-learned)

---

## 1. bhyve VM Setup

### Pool is on an external disk — must be imported manually
The ZFS pool `pool1` lives on an external disk. It is NOT auto-imported at boot. This means:
- `vm_enable="YES"` must be in rc.conf but `vm_dir` can optionally be omitted if you pass `-d` to `vm init`
- In practice, keep `vm_dir` in rc.conf to avoid errors in subsequent vm commands
- Do NOT set `vm_list` — no VMs should auto-start since the pool isn't mounted yet

### Startup script
Created at `/usr/local/bin/start-vm.sh`:

```sh
#!/bin/sh
zpool import pool1
vm init
vm switch create -t standard public
vm start Ubuntu
```

Make executable:
```sh
chmod +x /usr/local/bin/start-vm.sh
```

Run after every FreeBSD boot:
```sh
sudo start-vm.sh
```

### vm-bhyve templates
Templates live in `/pool1/vms/bhyve/.templates/`. The `linux` template does not exist by default. Create it:

```sh
vim /pool1/vms/bhyve/.templates/linux.conf
```

```sh
loader="uefi"
cpu=2
memory=1G
network0_type="virtio-net"
network0_switch="public"
disk0_type="virtio-blk"
disk0_name="disk0.img"
graphics="yes"
graphics_port="5900"
graphics_res="1280x720"
xhci_mouse="yes"
```

### Creating and destroying VMs

**Create:**
```sh
sudo vm create -t linux -s 60G -m 12G -c 6 Ubuntu
```

**Install from ISO:**
```sh
sudo vm install Ubuntu ubuntu-24.04.4-desktop-amd64.iso
```
⚠️ WARNING: `vm install` WIPES the disk. Only use for first-time install.
To just start an already-installed VM use: `sudo vm start Ubuntu`

**Destroy completely:**
```sh
sudo vm poweroff Ubuntu
sudo bhyvectl --destroy --vm=Ubuntu
sudo vm destroy Ubuntu
```

### Stale VM / bhyve won't start
If you see `guest appears to be running already` but `vm info` shows stopped:
```sh
sudo bhyvectl --destroy --vm=Ubuntu
```
This removes the in-kernel bhyve VM object. `errno=37` means `EEXIST` — the kernel VM object already exists.

### VNC to connect to the VM
Install TigerVNC (not Remmina — Remmina has keyboard layout issues):
```sh
sudo pkg install tigervnc-viewer
vncviewer 127.0.0.1:5900
```

---

## 2. VM Configuration

Location: `/pool1/vms/bhyve/Ubuntu/Ubuntu.conf`

### Working config (without passthrough):
```sh
loader="uefi"
cpu="6"
memory="12G"
network0_type="virtio-net"
network0_switch="public"
disk0_type="virtio-blk"
disk0_name="disk0.img"
graphics="yes"
graphics_port="5900"
graphics_res="1280x720"
xhci_mouse="yes"
uuid="your-uuid-here"
network0_mac="your-mac-here"
```

### Key notes:
- `graphics_res` sets a fixed VNC resolution — bhyve fbuf does NOT support dynamic resize
- Use TigerVNC's F8 menu zoom/scaling to fit your screen
- `bhyve_options="-S"` (wired memory) is required if using passthrough
- Do NOT duplicate `-S` — vm-bhyve may add it automatically, causing double `-S` in the bhyve command which causes `bhyve exited with status 4`

### VM logs
```sh
cat /pool1/vms/bhyve/Ubuntu/vm-bhyve.log
```

### UK keyboard inside Ubuntu VM
```sh
sudo dpkg-reconfigure keyboard-configuration
gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'gb')]"
```
Then log out and back in.

---

## 3. Networking

### Architecture
- `vm-public` bridge on `192.168.100.1/24`
- VMs get IPs via dnsmasq DHCP
- NAT via pf routes VM traffic through `lagg0` (the host's outbound interface)
- `lagg0` is a failover lagg combining `re0` (ethernet) and `wlan0` (wifi)

### The vm-public switch does not survive reboot
The switch is recreated by the startup script:
```sh
vm switch create -t standard public
```

### IP forwarding — required for NAT
Must be enabled:
```sh
sysctl net.inet.ip.forwarding=1
```
Persisted via `gateway_enable="YES"` in rc.conf.

### dnsmasq DHCP for VMs
Config in `/usr/local/etc/dnsmasq.conf`:
```
interface=vm-public
dhcp-range=192.168.100.10,192.168.100.50,12h
dhcp-option=3,192.168.100.1
dhcp-option=6,8.8.8.8,1.1.1.1
```
Multiple interfaces and ranges are supported — each `dhcp-range` is auto-associated with the correct interface by subnet matching.

Enable and start:
```sh
sysrc dnsmasq_enable="YES"
service dnsmasq start
```

### pf.conf issues found and fixed
1. **Second NAT rule removed** — `nat on $ext_if inet from any to any` was overly broad and conflicted with the bhyve NAT
2. **`set skip on $bhyve_if`** — this skips all pf processing on vm-public, making the explicit `pass in/out on $bhyve_if` rules dead code. They are kept for documentation but NAT still works because it is evaluated on `$ext_if` (lagg0)
3. `$ext_if = "lagg0"` must be defined — it is

---

## 4. NVIDIA GPU Passthrough

### Why it failed — Optimus laptop limitation

The GTX 1050 Ti Mobile (`pci0:1:0:0`) is an **Optimus GPU**. On this laptop architecture:
- The GPU sits behind the Intel PCIe bridge (`pcib1@pci0:0:1:0`)
- It has **no dedicated IRQ line** — interrupts route through the Intel bridge
- bhyve **cannot pass through PCIe bridges**
- The GPU has no display output of its own — it renders and hands off to Intel

This causes the `NVRM: Can't find an IRQ for your NVIDIA card!` error inside the VM, and `no irq handler` messages from bhyve. This is a **fundamental hardware limitation** and cannot be fixed with configuration changes.

### Everything we tried (for reference)

| Attempt | Result |
|---|---|
| `pptdevs="1/0/0"` alone | no irq handler |
| Adding `bhyve_options="-S"` | no irq handler |
| `hw.pci.enable_msi=1` and `hw.pci.enable_msix=1` | no irq handler |
| Passing PCIe bridge `pptdevs="0/1/0 1/0/0"` | FreeBSD won't claim a PCIe bridge as ppt |
| Removing `nvidia-modeset` from host kld_list | no irq handler |

### Conclusion
bhyve GPU passthrough for Optimus mobile GPUs is not supported. For this use case:
- KVM on Linux has better Optimus passthrough support
- Or use the GPU directly on the FreeBSD host (which we did — see section 5)

### If you ever want to re-enable passthrough attempt
In `/boot/loader.conf`:
```sh
pptdevs="1/0/0"
```
In `/etc/rc.conf` remove `nvidia-modeset` from `kld_list` and comment out `nvidia_xorg_enable`.
**Remember:** it won't work on this hardware.

---

## 5. Blender on FreeBSD Host

### Why not the ports version
`graphics/blender` in FreeBSD ports is unmaintained. Only `blender-doc` is available as a binary package.

### Linux compatibility layer
FreeBSD runs Linux binaries natively via the Linux compat layer. Required modules are already loaded:
```
linux.ko
linux64.ko
linux_common.ko
linuxkpi_video.ko   ← bridges Linux GPU calls to FreeBSD DRM
```

### Required packages
```sh
sudo pkg install linux_base-rl9
sudo pkg install linux-rl9-dri linux-rl9-libglvnd
sudo pkg install linux-nvidia-libs
```

### Download and install Blender
```sh
cd ~
fetch https://mirrors.dotsrc.org/blender/release/BlenderX.X/blender-X.X.X-linux-x64.tar.xz
tar -xf blender-X.X.X-linux-x64.tar.xz
sudo mv blender-X.X.X-linux-x64 /usr/local/blender
```

### Launcher script
`/usr/local/bin/blender`:
```sh
#!/bin/sh
export __NV_PRIME_RENDER_OFFLOAD=1
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export LD_LIBRARY_PATH=/usr/local/blender/lib:/compat/linux/lib64
exec /usr/local/blender/blender "$@"
```
```sh
sudo chmod +x /usr/local/bin/blender
```

Run from anywhere:
```sh
blender
blender myproject.blend
```

### GPU state
- `__NV_PRIME_RENDER_OFFLOAD=1` and `__GLX_VENDOR_LIBRARY_NAME=nvidia` activate NVIDIA via Optimus PRIME offload
- `nvidia-smi` confirms Blender uses the GTX 1050 Ti for OpenGL/graphics (`C+G`, ~133MiB VRAM used)
- **CUDA is NOT available** — FreeBSD's NVIDIA driver supports OpenGL but not CUDA compute
- Cycles CUDA tab in Blender will be empty — use Cycles CPU or EEVEE instead
- EEVEE runs fully on the NVIDIA GPU and is fast

### Verify GPU is being used
```sh
sudo nvidia-smi
```
While Blender is running you should see `./blender` listed under Processes with VRAM usage.

### Fonts/icons broken in Blender
If UI elements are missing or garbled:
- Always run Blender via the launcher script (correct LD_LIBRARY_PATH is critical)
- `LIBGL_ALWAYS_SOFTWARE=1` fixes rendering but disables GPU — only use for testing
- Do NOT use `glxinfo` through the compat layer — it segfaults

### KDE desktop icon
`/usr/local/share/applications/blender.desktop`:
```sh
[Desktop Entry]
Name=Blender
Comment=3D modeling, animation and rendering
Exec=/usr/local/bin/blender %f
Icon=/usr/local/blender/blender.svg
Terminal=false
Type=Application
Categories=Graphics;3DGraphics;
MimeType=application/x-blender;
StartupNotify=true
```

```sh
sudo update-desktop-database /usr/local/share/applications
cp /usr/local/share/applications/blender.desktop ~/Desktop/
chmod +x ~/Desktop/blender.desktop
```

---

## 6. rc.conf Final State

Relevant bhyve and GPU sections:

```sh
# Kernel modules — i915kms for Intel GPU, nvidia-modeset for NVIDIA
# NOTE: if you ever want to re-enable bhyve GPU passthrough, remove nvidia-modeset
# and nvidia_xorg_enable, and add pptdevs="1/0/0" to loader.conf
kld_list="i915kms nvidia-modeset fusefs cuse"
nvidia_xorg_enable="YES"

# ####################################################################################
# Bhyve
# NOTE: vm_dir is set here so vm commands work after manual pool import.
# pool1 is on an external disk — pool must be imported manually before starting VMs.
# vm_list is intentionally omitted — no auto-start since pool is not available at boot.
vm_enable="YES"
vm_dir="zfs:pool1/vms/bhyve"
# This ensures the vm-bhyve switch has its IP on boot
ifconfig_vm_public="inet 192.168.100.1 netmask 255.255.255.0"
# Enable IP forwarding so bhyve NAT works
gateway_enable="YES"
```

---

## 7. loader.conf Final State

```sh
# bhyve VMM kernel module
hw.pci.enable_msi=1
hw.pci.enable_msix=1
vmm_load="YES"
# pptdevs="1/0/0"  ← commented out — passthrough does not work on this Optimus laptop
#                    uncomment only if testing passthrough again (also disable nvidia in rc.conf)
```

---

## 8. pf.conf Final State

Key points:
- `ext_if = "lagg0"` — failover lagg (ethernet + wifi)
- `bhyve_if = "vm-public"` — VM bridge
- `bhyve_net = "192.168.100.0/24"` — VM subnet
- Single NAT rule: `nat on $ext_if inet from $bhyve_net to any -> ($ext_if)`
- `set skip on $bhyve_if` — pf skips processing on vm-public entirely (NAT still works via ext_if)
- The broad `nat from any to any` rule was removed — it was conflicting with VM routing

---

## 9. Quick Reference — Daily Startup

After booting FreeBSD and mounting the external disk:

```sh
# Start the VM
sudo start-vm.sh

# Connect to VM via VNC
vncviewer 127.0.0.1:5900

# Launch Blender (on FreeBSD host with NVIDIA GPU)
blender

# Check NVIDIA GPU status
sudo nvidia-smi

# Check VM status
sudo vm list
sudo vm info Ubuntu
```

---

## 10. Lessons Learned

| Issue | Cause | Fix |
|---|---|---|
| `guest appears to be running already` | Stale bhyve kernel object | `sudo bhyvectl --destroy --vm=NAME` |
| `failed to find virtual switch` | Switch not created yet / VM started too early | Run `vm switch create -t standard public` in startup script |
| `bhyve exited with status 4` | passthru device not ready or `-S` flag duplicated | Check conf for duplicate `bhyve_options`, verify ppt devices |
| `errno = 37` on vm start | VM object already exists in kernel (`EEXIST`) | `bhyvectl --destroy` |
| VM disk empty after reinstall | Used `vm install` on existing VM | Always use `vm start` for already-installed VMs |
| No IRQ handler for NVIDIA in VM | Optimus laptop — GPU has no dedicated IRQ | Unsolvable in bhyve on this hardware |
| Blender fonts/icons missing | Wrong working directory or LD_LIBRARY_PATH | Always run via launcher script |
| `GLIBC version not found` | Old linux compat base | `pkg install linux_base-rl9` |
| `libGL.so.1 not found` | Missing Mesa Linux compat libs | `pkg install linux-rl9-dri linux-rl9-libglvnd` |
| Keyboard layout wrong in VM | Remmina remaps keys | Use TigerVNC instead of Remmina |
| VNC display too large to fit screen | Fixed resolution in bhyve fbuf | Use TigerVNC F8 menu scaling, or set smaller `graphics_res` in VM conf |
| CUDA not available in Blender | FreeBSD NVIDIA driver doesn't support CUDA compute | Use EEVEE (GPU) or Cycles CPU instead |
| `vm init` fails after reboot | `vm_enable` missing from rc.conf | Keep `vm_enable="YES"` in rc.conf even without auto-start |
| Boot error about vm_dir | vm-bhyve tries to access pool before it's imported | Accept the harmless boot error — pool is imported manually |
