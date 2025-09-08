# Signal Desktop on FreeBSD (via Linux Emulator)

This single-file guide shows how to install and run **Signal Desktop** on FreeBSD using the Linux binary compatibility layer with an Ubuntu chroot. Copy and paste the whole file at once.

## 1. Install Linux emulator

Follow the FreeBSD Handbook instructions to enable the Linux binary compatibility layer (lbc):

https://docs.freebsd.org/en/books/handbook/linuxemu/#linuxemu-lbc-install

## 2. Install Ubuntu under the emulator

Bootstrap an Ubuntu environment into `/compat/ubuntu` as described in the Handbook:

https://docs.freebsd.org/en/books/handbook/linuxemu/#linuxemu-debootstrap

## 3. Enter the Ubuntu chroot

```sh
sudo chroot /compat/ubuntu /bin/bash

## 4. Install Signal Desktop (inside the chroot)

# Update package lists
apt update

# Remove any existing Signal installation (if present)
rm -rf /opt/Signal

# Add Signal's official repository
wget -O- https://updates.signal.org/desktop/apt/keys.asc | apt-key add -
echo "deb [arch=amd64] https://updates.signal.org/desktop/apt xenial main" | tee /etc/apt/sources.list.d/signal-desktop.list

# Update package lists again and install Signal Desktop
apt update
apt install -y signal-desktop

exit

## 5. Run Signal Desktop

sudo chroot /compat/ubuntu signal-desktop --no-sandbox --in-process-gpu

## 6. Create a wrapper script for easy launching

sudo tee /usr/local/bin/signal << 'EOF'
#!/bin/sh
sudo chroot /compat/ubuntu signal-desktop --no-sandbox --in-process-gpu
EOF

sudo chmod +x /usr/local/bin/signal
