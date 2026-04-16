# Comprehensive Guide: Configuring Realtek RTL8822BU (0bda:b812) on OpenWrt

This guide provides a complete, step-by-step walkthrough for taking a physical Realtek RTL8822BU USB WiFi adapter and configuring it as a high-performance 5GHz Access Point within an OpenWrt VirtualBox environment.

---

## 1. Phase 1: VirtualBox & Host Preparation

Before the OpenWrt guest can interact with the hardware, the VirtualBox Hypervisor must be configured to pass the USB signal directly from the host machine to the VM.

### 1.1 VirtualBox Extension Pack
Ensure the **VirtualBox Extension Pack** is installed on your host OS. This is a requirement for USB 3.0 (xHCI) support. Without it, the high-speed Realtek chip will fail to initialise.

### 1.2 USB Controller Settings
1. Shut down the OpenWrt VM.
2. Navigate to **Settings > USB**.
3. Select **USB 3.0 (xHCI) Controller**.
4. Click the **USB Plus (+)** icon and select `Realtek 802.11ac NIC [0bda:b812]`. This creates a hardware filter that automatically captures the device when the VM starts.

### 1.3 Host Side Interference (Optional)
If the device is captured by the VM but the driver fails to load, ensure your host (e.g., Kali Linux) isn't "holding" the device. You can temporarily unload the driver on the host:
```bash
sudo modprobe -r rtw88_8822bu
```

---

## 2. Phase 2: Hardware Verification in OpenWrt

Boot the VM and log in. We must verify that the virtual USB bus has successfully mapped the hardware.

### 2.1 USB Bus Check
```bash
lsusb
```
**Success Indicator:** `Bus 002 Device 002: ID 0bda:b812 Realtek Semiconductor Corp. RTL88x2bu`

### 2.2 Initial Network State
Run `ifconfig`. You will only see `eth0` and `br-lan`. The WiFi interface is currently invisible because the kernel does not yet have the drivers required to communicate with the RTL8822BU chip.

---

## 3. Phase 3: Software & Driver Installation

OpenWrt Snapshot builds are minimal and do not include wireless drivers by default. We must install the driver, the firmware, and the management utilities.

### 3.1 Package Installation
```bash
apk update
apk add kmod-rtw88-8822bu kmod-rtw88-usb rtl8822be-firmware hostapd iw-full wireless-regdb
```

**Package Explanations:**
- `kmod-rtw88-8822bu`: The specific kernel driver for your chipset.
- `rtl8822be-firmware`: The binary "brain" for the chip (the 'BE' firmware is shared by 'BU' USB models).
- `hostapd`: The daemon that manages the Access Point, SSID broadcasting, and security.
- `iw-full`: The complete version of the wireless configuration utility.
- `wireless-regdb`: The regulatory database required for 5GHz compliance.

---

## 4. Phase 4: Driver Activation & Kernel Logs

### 4.1 Manual Module Loading
If the driver does not start automatically after installation, trigger the kernel modules:
```bash
modprobe rtw88_8822bu
```

### 4.2 Verifying the Firmware (dmesg)
Check the kernel logs to ensure the driver has successfully injected the firmware into the USB stick:
```bash
dmesg | grep rtw88
```
**Success Indicators:**
- `rtw88_8822bu 2-1:1.0: Firmware version 30.20.0, H2C version 14`
- `usbcore: registered new interface driver rtw88_8822bu`

### 4.3 Verifying the Physical Radio
Even if you cannot see a `wlan0` interface yet, the "Radio" should be registered in the system:
```bash
iw list
```
If this command returns a large amount of data (frequencies, bitrates, etc.), the hardware is fully operational.

---

## 5. Phase 5: Wireless Configuration (UCI)

OpenWrt uses a configuration system called UCI. We need to define the 5GHz parameters and turn the radio on.

### 5.1 Generate Default Configuration

    wifi config > /etc/config/wireless

### 5.2 Editing for 5GHz and VHT80 (High Speed)
Open the file using `vim /etc/config/wireless` and edit the sections to match the following:

    config wifi-device 'radio0'
        option type 'mac80211'
        option band '5g'
        option channel '36'
        option htmode 'VHT80'    # Enables 80MHz bandwidth for 802.11ac speeds
        option country 'GB'      # Set to your country; vital for 5GHz activation
        option disabled '0'      # MUST be set to 0 to enable the radio

    config wifi-iface 'default_radio0'
        option device 'radio0'
        option network 'lan'
        option mode 'ap'
        option ssid 'OpenWrt-Home'
        option encryption 'psk2'
        option key 'YourSecretPassword'

---

## 6. Phase 6: Bringing the Access Point Online

### 6.1 Start Wireless Services
Apply the new configuration:
```bash
wifi up
```

### 6.2 The Interface Naming Catch
Realtek drivers in OpenWrt often do not use the name `wlan0`. Check for the interface name assigned by the kernel:
```bash
ifconfig -a
```
In many cases, your interface will be named `phy0-ap0`.

### 6.3 Verify Bridge Inclusion
For connected WiFi clients to access the internet, the wireless interface must be part of the network bridge:
```bash
brctl show
```
Confirm that `phy0-ap0` (or `wlan0`) is listed under the interfaces column for `br-lan`.

---

## 7. Phase 7: Verification & Performance Tuning

### 7.1 Verify Broadcast Status
Confirm that the Access Point daemon is running correctly:
```bash
logread | grep hostapd
```
**Success Indicator:** `phy0-ap0: AP-ENABLED`

### 7.2 Confirm 80MHz Bandwidth
To ensure you aren't stuck at low speeds, check the active channel width:
```bash
iw dev phy0-ap0 info
```
Look for `width: 80 MHz`. If it shows `20 MHz`, check your `country` and `htmode` settings in `/etc/config/wireless`.

### 7.3 Monitor Clients
To see real-time signal strength and bitrate for connected devices:
```bash
iw dev phy0-ap0 station dump
```

---

## Troubleshooting Checklist

- **No SSID visible:** Check `logread` for DFS wait times or regulatory errors.
- **lsusb is empty:** Check VirtualBox USB settings; ensure it is set to USB 3.0.
- **wifi up fails:** Ensure `option disabled '0'` is set and the `wireless-regdb` package is installed.
- **Kernel Warning in dmesg:** Minor warnings regarding "CPU" or "EIP" in the rtw88 logs can usually be ignored if `iw list` shows the radio.
