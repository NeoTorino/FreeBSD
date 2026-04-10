# TigerVNC on EndeavourOS (bhyve guest) — Setup Guide

## Overview

This guide covers running EndeavourOS as a bhyve VM on FreeBSD with TigerVNC for remote desktop access.

> **Note on Ubuntu:** Ubuntu was attempted first but failed due to NVIDIA drivers being automatically installed inside the guest. These drivers crash TigerVNC at startup because there is no real GPU inside a bhyve VM. EndeavourOS (Arch-based) does not install NVIDIA drivers by default and works cleanly.

---

## 1. FreeBSD Host — bhyve Prerequisites

Make sure vm-bhyve is installed and initialised:

```sh
sudo pkg install vm-bhyve bhyve-firmware
sudo sysrc vm_enable="YES"
sudo sysrc vm_dir="zfs:pool1/vms/bhyve"
sudo vm init
```

Create the virtual switch and attach it to your physical interface (replace `lagg0` with your interface):

```sh
sudo vm switch create public
sudo vm switch add public lagg0
```

---

## 2. bhyve VM Configuration

Create the VM:

```sh
sudo vm create -t linux -s 60G EndeavourOS
```

The VM config is located at `/pool1/vms/bhyve/EndeavourOS/EndeavourOS.conf`. During installation, enable graphics so you can use VNC to go through the installer:

```
loader="uefi"
cpu="4"
memory="8G"
network0_type="virtio-net"
network0_switch="public"
disk0_type="virtio-blk"
disk0_name="disk0.img"
graphics="yes"
graphics_port="5900"
graphics_res="1280x720"
xhci_mouse="yes"
```

Copy the ISO to the vm-bhyve store and install:

```sh
sudo vm iso /path/to/endeavouros.iso
sudo vm install EndeavourOS endeavouros-filename.iso
```

Connect to the installer via VNC on port `5900` of your FreeBSD host IP.

Once installation is complete, **disable bhyve's built-in VNC** since TigerVNC inside the guest will handle it:

```
loader="uefi"
cpu="4"
memory="8G"
network0_type="virtio-net"
network0_switch="public"
disk0_type="virtio-blk"
disk0_name="disk0.img"
#graphics="yes"
#graphics_port="5900"
#graphics_res="1280x720"
xhci_mouse="yes"
```

Start the VM:

```sh
sudo vm start EndeavourOS
```

---

## 3. Inside the EndeavourOS Guest — TigerVNC Setup

SSH into the guest first (find its IP via `arp -a` on the FreeBSD host or your router's DHCP leases):

```sh
ssh juan@<guest-ip>
```

### Install TigerVNC

```sh
sudo pacman -S tigervnc
```

### Set VNC Password

```sh
vncpasswd
```

### Configure TigerVNC

Create the VNC config file:

```sh
mkdir -p ~/.vnc
vim ~/.vnc/config
```

Add:

```
session=plasma
securitytypes=vncauth,tlsvnc
geometry=1920x1080
```

Change `session=plasma` to match your desktop environment:

| Desktop | Value |
|---------|-------|
| KDE Plasma | `plasma` |
| XFCE | `xfce` |
| GNOME | `gnome` |

### Map Display to User

```sh
sudo vim /etc/tigervnc/vncserver.users
```

Add:

```
:1=juan
```

---

## 4. Systemd Service

Use the built-in TigerVNC service file (do not create a custom one):

```sh
sudo systemctl enable vncserver@:1
sudo systemctl start vncserver@:1
sudo systemctl status vncserver@:1
```

Verify it is listening on port 5901:

```sh
netstat -an | grep 5901
```

---

## 5. Connect via VNC

Point your VNC client at:

```
<guest-ip>:5901
```

TigerVNC supports dynamic resize — the screen will resize automatically when you resize the VNC window.

---

## 6. Optional — Static IP Inside the Guest

```sh
nmcli con show
sudo nmcli con mod "your-connection-name" ipv4.addresses 192.168.1.105/24
sudo nmcli con mod "your-connection-name" ipv4.gateway 192.168.1.1
sudo nmcli con mod "your-connection-name" ipv4.dns 8.8.8.8
sudo nmcli con mod "your-connection-name" ipv4.method manual
sudo nmcli con up "your-connection-name"
```

---

## 7. Optional — Disable sudo Password Prompt

```sh
sudo visudo
```

Comment out:

```
#%wheel ALL=(ALL:ALL) ALL
```

Add:

```
%wheel ALL=(ALL:ALL) NOPASSWD: ALL
```

---

## Notes

- bhyve presents no real GPU to guests. Do not install GPU drivers inside the VM.
- TigerVNC uses software rendering (llvmpipe) inside the VM which is correct and expected.
- The VNC port for display `:1` is always `5901`.
- To manage the VM from the FreeBSD host: `vm start|stop|list|info EndeavourOS`.
