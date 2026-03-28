# VNC Server Setup on Kali Linux

A complete guide to setting up multi-user TigerVNC remote desktop access on Kali Linux.

---

## Overview

This guide sets up a TigerVNC server where each user gets their own isolated desktop session on a unique port. Sessions survive reboots via systemd services.

- Each user runs their own VNC session
- Sessions start automatically at boot
- Ports are auto-assigned to avoid conflicts (`:1` = `5901`, `:2` = `5902`, etc.)
- Two helper scripts handle setup and cleanup for any user

---

## Required Packages

Install these on the Kali machine running the VNC server:

```bash
sudo apt update
sudo apt install tigervnc-standalone-server tigervnc-common xterm xfce4 xfce4-goodies dbus-x11
```

| Package | Purpose |
|---|---|
| `tigervnc-standalone-server` | The VNC server |
| `tigervnc-common` | Shared TigerVNC tools (`vncpasswd` etc.) |
| `xterm` | Minimal terminal, needed as fallback for session startup |
| `xfce4` | Desktop environment |
| `xfce4-goodies` | Extra XFCE plugins and tools |
| `dbus-x11` | D-Bus for X11, required by XFCE to start properly |

---

## How It Works

### Port Mapping

VNC port is always `5900 + display number`:

| Display | Port |
|---|---|
| `:1` | `5901` |
| `:2` | `5902` |
| `:3` | `5903` |

### Network Binding

| Flag | Behaviour |
|---|---|
| `-localhost no` | Listens on `0.0.0.0` — direct VNC access from the network |
| `-localhost yes` | Listens on `127.0.0.1` only — requires SSH tunnel to connect |

> **Security note:** TigerVNC defaults to `localhost` only as a security measure. Using `-localhost no` exposes VNC directly on the network. Make sure your VNC password is strong, and consider using an SSH tunnel instead for sensitive environments.

### SSH Tunnel (optional, more secure)

If you prefer to keep `-localhost yes`, connect via SSH tunnel instead:

```bash
ssh -L 5901:localhost:5901 user@kali-ip
```

Then point your VNC client to `localhost:5901`. Traffic is fully encrypted through SSH.

---

## Configuration Files

TigerVNC on Kali reads config from `~/.config/tigervnc/` (not the older `~/.vnc/`):

| File | Purpose |
|---|---|
| `~/.config/tigervnc/passwd` | Encrypted VNC password |
| `~/.config/tigervnc/xstartup` | Script that launches the desktop session |
| `/etc/systemd/system/vncserver-USER@DISPLAY.service` | Systemd service per user |

### xstartup

The xstartup script must use `exec` (not `&`) to keep the desktop process in the foreground. If it exits immediately VNC thinks the session ended and kills itself.

```bash
#!/bin/bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export $(dbus-launch)
[ -f $HOME/.Xresources ] && xrdb $HOME/.Xresources
exec startxfce4
```

---

## Scripts

Install both scripts so any user on the system can run them:

```bash
sudo cp vnc-setup /usr/local/bin/vnc-setup
sudo cp vnc-clean /usr/local/bin/vnc-clean
sudo chmod +x /usr/local/bin/vnc-setup /usr/local/bin/vnc-clean
```

`/usr/local/bin/` is in every user's `PATH` by default, so no path prefix is needed.

---

### vnc-setup

Each user runs this once to configure their own VNC session. It auto-selects a free display/port, sets a password, creates the xstartup, and registers a systemd service.

```bash
#!/bin/bash

# vnc-setup - Sets up a TigerVNC server for the current user
# Each user gets their own isolated session on a unique display/port
# Run as the user who wants VNC access (not root)
#
# Usage: vnc-setup
#
# Packages required on the server:
#   tigervnc-standalone-server  - the VNC server
#   tigervnc-common             - shared tools (vncpasswd etc.)
#   xterm                       - minimal terminal for session startup
#   xfce4                       - desktop environment
#   xfce4-goodies               - extra XFCE plugins and tools
#   dbus-x11                    - D-Bus for X11, required by XFCE
#
# Port mapping:
#   VNC port = 5900 + display number
#   :1 = 5901, :2 = 5902, :3 = 5903 etc.
#   Display number is auto-selected to avoid conflicts between users
#
# Network binding:
#   -localhost no  : listens on 0.0.0.0 (direct VNC access from network)
#   -localhost yes : listens on 127.0.0.1 only (requires SSH tunnel)
#   Current setting: 0.0.0.0 (direct access)
#   If you prefer SSH tunneling, remove -localhost no from ExecStart
#   and connect with: ssh -L 5901:localhost:5901 user@host
#   then point VNC client to localhost:5901

set -e

USERNAME=$(whoami)
HOME_DIR=$(eval echo ~$USERNAME)

echo "=== VNC Setup for user: $USERNAME ==="

# Install missing packages if needed
echo "[*] Checking dependencies..."
MISSING=""
for pkg in tigervnc-standalone-server tigervnc-common xterm xfce4 xfce4-goodies dbus-x11; do
    if ! dpkg -s "$pkg" &>/dev/null; then
        MISSING="$MISSING $pkg"
    fi
done

if [ -n "$MISSING" ]; then
    echo "[*] Installing missing packages:$MISSING"
    sudo apt update
    sudo apt install -y $MISSING
else
    echo "[*] All dependencies already installed."
fi

# Auto-select the next free display number to avoid port conflicts
# between users. Display :1 = port 5901, :2 = 5902, etc.
echo "[*] Finding available display number..."
DISPLAY_NUM=1
while [ -f "/tmp/.X$DISPLAY_NUM-lock" ] || ss -tlnp | grep -q ":59$(printf '%02d' $DISPLAY_NUM)"; do
    DISPLAY_NUM=$((DISPLAY_NUM + 1))
done
PORT=$((5900 + DISPLAY_NUM))
echo "[*] Using display :$DISPLAY_NUM (port $PORT)"

# Set VNC password - stored in ~/.config/tigervnc/passwd
echo "[*] Setting VNC password..."
mkdir -p "$HOME_DIR/.config/tigervnc"
vncpasswd "$HOME_DIR/.config/tigervnc/passwd"

# Create xstartup - this is what launches the desktop when VNC starts
# Must use exec (not &) to keep the process in the foreground
# so VNC does not think the session ended immediately
echo "[*] Creating xstartup..."
cat > "$HOME_DIR/.config/tigervnc/xstartup" << 'EOF'
#!/bin/bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export $(dbus-launch)
[ -f $HOME/.Xresources ] && xrdb $HOME/.Xresources
exec startxfce4
EOF
chmod +x "$HOME_DIR/.config/tigervnc/xstartup"

# Create a systemd service named after the user and display number
# e.g. vncserver-juan@1.service
# Type=simple with -fg flag keeps vncserver in the foreground
# so systemd can track the process properly
echo "[*] Creating systemd service..."
SERVICE_NAME="vncserver-${USERNAME}@${DISPLAY_NUM}"

sudo bash -c "cat > /etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=TigerVNC server for $USERNAME on display :$DISPLAY_NUM
After=network.target

[Service]
Type=simple
User=$USERNAME
Group=$USERNAME
WorkingDirectory=$HOME_DIR

# Ensure runtime dir exists and clean up any stale session before starting
ExecStartPre=/bin/bash -c 'mkdir -p $HOME_DIR/.local/share/vncserver && vncserver -kill :$DISPLAY_NUM 2>/dev/null; sleep 1; true'

# VNC port = 5900 + display number (:1 = 5901, :2 = 5902 etc.)
# -localhost no  : listen on 0.0.0.0 (direct access from network)
# -localhost yes : listen on 127.0.0.1 only (SSH tunnel required)
# -fg            : run in foreground so systemd tracks the process
ExecStart=/usr/bin/vncserver :$DISPLAY_NUM -geometry 1920x1080 -depth 24 -fg -localhost no
ExecStop=/usr/bin/vncserver -kill :$DISPLAY_NUM

Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable "${SERVICE_NAME}.service"
sudo systemctl start "${SERVICE_NAME}.service"

# Print connection details
IP=$(hostname -I | awk '{print $1}')
echo ""
echo "=== Setup complete! ==="
echo "    User:    $USERNAME"
echo "    Display: :$DISPLAY_NUM"
echo "    Port:    $PORT"
echo "    Connect: $IP:$PORT"
echo ""
echo "Manage your session with:"
echo "  sudo systemctl status ${SERVICE_NAME}.service"
echo "  sudo systemctl stop   ${SERVICE_NAME}.service"
echo "  sudo systemctl start  ${SERVICE_NAME}.service"
```

---

### vnc-clean

Removes all VNC configuration for the user who runs it. Stops and disables the service, kills active sessions, and removes all config and runtime files.

```bash
#!/bin/bash

# vnc-clean - Removes all VNC configuration for the current user
# Stops and disables the systemd service, kills active sessions,
# and removes all config, log, and runtime files
#
# Usage: vnc-clean
# Run as the user whose VNC setup you want to remove (not root)

set -e

USERNAME=$(whoami)
HOME_DIR=$(eval echo ~$USERNAME)

echo "=== VNC Cleanup for user: $USERNAME ==="

# Stop and disable all systemd services belonging to this user
# Service names follow the pattern: vncserver-USERNAME@DISPLAY.service
SERVICES=$(systemctl list-units --full --all | grep "vncserver-${USERNAME}@" | awk '{print $1}' || true)

if [ -z "$SERVICES" ]; then
    echo "[*] No VNC services found for $USERNAME"
else
    for SERVICE in $SERVICES; do
        echo "[*] Stopping and disabling $SERVICE..."
        sudo systemctl stop "$SERVICE" 2>/dev/null || true
        sudo systemctl disable "$SERVICE" 2>/dev/null || true
        SERVICE_FILE="/etc/systemd/system/${SERVICE}"
        if [ -f "$SERVICE_FILE" ]; then
            sudo rm -f "$SERVICE_FILE"
            echo "[*] Removed $SERVICE_FILE"
        fi
    done
    sudo systemctl daemon-reload
    echo "[*] Systemd reloaded"
fi

# Kill active VNC sessions via vncserver -list
# This is more reliable than scanning /tmp/.X*-lock files
echo "[*] Killing any active VNC sessions..."
for DISPLAY_NUM in $(vncserver -list 2>/dev/null | grep "^:" | awk '{print $1}' | tr -d ':'); do
    echo "[*] Killing VNC session on display :$DISPLAY_NUM"
    vncserver -kill ":$DISPLAY_NUM" 2>/dev/null || true
done

# Force kill any Xtigervnc processes still owned by this user
# in case vncserver -kill did not catch them
PIDS=$(pgrep -u "$USERNAME" Xtigervnc 2>/dev/null || true)
if [ -n "$PIDS" ]; then
    echo "[*] Force killing remaining Xtigervnc processes: $PIDS"
    kill -9 $PIDS 2>/dev/null || true
fi

# Remove X lock and socket files so ports are fully released
sudo rm -f /tmp/.X*-lock 2>/dev/null || true
sudo rm -f /tmp/.X11-unix/X* 2>/dev/null || true

# Remove all VNC config and runtime files for this user
echo "[*] Removing VNC config and runtime files..."
rm -f "$HOME_DIR/.config/tigervnc/passwd"
rm -f "$HOME_DIR/.config/tigervnc/xstartup"
rm -f "$HOME_DIR/.config/tigervnc/"*.log 2>/dev/null || true
rm -f "$HOME_DIR/.config/tigervnc/"*.pid 2>/dev/null || true
rm -f "$HOME_DIR/.vnc/"*.log 2>/dev/null || true
rm -rf "$HOME_DIR/.local/share/vncserver" 2>/dev/null || true

# Optionally remove TigerVNC packages
# Only say yes if no other users are using VNC on this machine
echo ""
read -rp "Do you also want to uninstall TigerVNC packages? [y/N] " REMOVE_PKGS
if [[ "$REMOVE_PKGS" =~ ^[Yy]$ ]]; then
    sudo apt remove -y tigervnc-standalone-server tigervnc-common
    sudo apt autoremove -y
    echo "[*] Packages removed"
else
    echo "[*] Packages kept"
fi

echo ""
echo "=== Cleanup complete for $USERNAME ==="
echo "    VNC sessions killed"
echo "    Systemd services removed"
echo "    Config and runtime files removed"
```

---

## Connecting

Use any VNC client on the remote machine:

| Client | Platform |
|---|---|
| TigerVNC Viewer | Linux, Windows, macOS |
| Remmina | Linux |
| RealVNC Viewer | Linux, Windows, macOS |
| Jump Desktop | macOS, iOS |

Connect to:

```
kali-ip:5901
```

Or via SSH tunnel (more secure):

```bash
ssh -L 5901:localhost:5901 user@kali-ip
```

Then connect VNC client to `localhost:5901`.

---

## Managing Sessions

```bash
# Check status
sudo systemctl status vncserver-juan@1.service

# Stop
sudo systemctl stop vncserver-juan@1.service

# Start
sudo systemctl start vncserver-juan@1.service

# Restart
sudo systemctl restart vncserver-juan@1.service

# View logs
journalctl -u vncserver-juan@1.service -f

# Check VNC log
cat ~/.config/tigervnc/*.log

# List active sessions
vncserver -list

# Check listening ports
ss -tlnp | grep 590
```

---

## Troubleshooting

### Session exits immediately

Check the VNC log:

```bash
cat ~/.config/tigervnc/*.log
```

Common causes:

- `xstartup` uses `startxfce4 &` instead of `exec startxfce4` — the `&` makes it background and VNC thinks the session ended
- XFCE or xterm not installed — verify with `which startxfce4` and `which xterm`
- Wrong config location — Kali's TigerVNC reads from `~/.config/tigervnc/` not `~/.vnc/`

### Service shows failed but VNC works

The process forked before systemd could track it. Make sure the service uses `Type=simple` and the `-fg` flag on `ExecStart`. See the service definition in `vnc-setup`.

### Can't reach VNC from another device on the same WiFi

Likely **AP Isolation** on your router — it blocks device-to-device communication over WiFi while still allowing internet. Check your router admin panel and disable AP Isolation / Wireless Isolation / Client Isolation.

If you cannot change the router setting, use ethernet for the Kali connection or set up a VPN like Tailscale.

### Port still in use after vnc-clean

Force kill any remaining processes:

```bash
pgrep -u $(whoami) Xtigervnc
kill -9 <PID>
sudo rm -f /tmp/.X*-lock
sudo rm -f /tmp/.X11-unix/X*
```

---

## Network Considerations

| Scenario | Recommendation |
|---|---|
| Home network, same subnet | Direct VNC connection |
| WiFi with AP Isolation | Use ethernet or SSH tunnel |
| Remote access over internet | SSH tunnel or Tailscale |
| Sensitive / security work | Self-hosted WireGuard VPN |

### Tailscale (easy remote access)

Tailscale creates a private encrypted network between your devices using WireGuard. Works through AP isolation and across networks. Free for personal use.

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

Every device gets a stable private IP that never changes, even after reboots.
