# 📱 Mounting Android (MTP) Devices on FreeBSD using `jmtpfs`

This guide explains how to install, configure, and mount Android devices on FreeBSD using `jmtpfs`.  
It also covers permissions, `devd` setup, and how to unmount safely.

---

## 🧩 1. Install Required Packages

```bash
pkg install jmtpfs fusefs-libs fusefs-kmod usbutils
```

Enable and load FUSE:
```bash
sysrc kld_list+="fusefs"
kldload fusefs
```

---

## ⚙️ 2. Enable User Mounts

Allow non-root users to mount with FUSE:
```bash
sysctl vfs.usermount=1
```

To make it permanent, add to `/etc/sysctl.conf`:
```bash
vfs.usermount=1
```

---

## 👥 3. Configure User Groups and Permissions

Add your user to the required groups:
```bash
pw groupmod operator -m <username>
pw groupmod wheel -m <username>
pw groupmod fuse -m <username>
```

Then log out and back in.

Create a mount directory owned by the user:
```bash
mkdir -p ~/android
chown <username>:<username> ~/android
chmod 700 ~/android
```

---

## 🔌 4. Identify Your Device and Vendor ID

Plug in your Android device, enable **File Transfer (MTP)** mode, and run:
```bash
usbconfig
```

Example output:
```
ugen0.2: <Samsung Electronics Co., Ltd. Android Phone> at usbus0
```

Inspect details:
```bash
usbconfig -d ugen0.2 dump_device_desc
```

Look for:
```
idVendor = 0x04e8
idProduct = 0x6860
```

🆔 **Vendor ID:** `0x04e8` (Samsung)

---

## ⚡ 5. Configure `devd` for Automatic Permissions

Create `/usr/local/etc/devd/android.conf`:

```conf
# Android MTP device rule
notify 100 {
    match "system" "USB";
    match "subsystem" "DEVICE";
    match "type" "ATTACH";
    match "vendor" "0x04e8";    # Samsung vendor ID
    action "chmod 0660 /dev/$cdev && chown <username>:operator /dev/$cdev";
}
```

Reload `devd`:
```bash
service devd restart
```

---

## 📂 6. Mounting the Device with `jmtpfs`

Mount:
```bash
jmtpfs ~/android
```

You can now access your phone’s storage under `~/android`.

---

## 🚫 7. Unmounting Safely (without `fusermount`)

On FreeBSD, `fusermount` often fails — use `umount` instead:

```bash
umount ~/android
```

If it complains that the directory is busy, ensure no terminal or file browser is open in that folder.

---

## 🔁 8. Optional: Auto-Load at Boot

Add this to `/etc/rc.conf`:
```bash
devd_enable="YES"
fusefs_enable="YES"
```

---

## 🧼 9. Troubleshooting Tips

- If `jmtpfs` fails: replug the device and ensure it’s in **File Transfer (MTP)** mode.  
- Check device visibility:
  ```bash
  usbconfig
  ```
- If permission denied: verify `/dev/ugen*` ownership after plugging in.

---

✅ **You now have a working MTP setup using `jmtpfs` on FreeBSD!**  
Fast, stable, and no need for `fusermount`.
