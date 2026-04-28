# FreeBSD Atomic Upgrades with Boot Environments
## Using `bectl` + Jails — What Works, What Doesn't, and Why

---

## The Core Idea

Instead of modifying your running system directly, you:

1. **Clone** your current boot environment (a ZFS snapshot of your root filesystem)
2. **Work on the clone** — either by jailing into it or mounting it
3. **Activate it temporarily** with `bectl activate -t` — one safe test boot
4. **Confirm or discard** — make it permanent, or destroy it and start over

Your live system is never touched until the moment you choose to reboot into the new environment.

---

## What This Method Is Good For: Minor Upgrades

Minor upgrades cover two things:

- **Security patches and errata** — e.g., 14.3 → 14.3-p1, or 14.3 → 14.4
- **Third-party package upgrades** — `pkg upgrade` for ports/packages

This is where the `bectl jail` workflow genuinely shines. You are updating userland binaries and packages inside a clone, so if `pkg upgrade` replaces a critical shared library like `openssl` mid-way through and something goes wrong, your live system is completely unaffected.

---

## Step-by-Step: Minor Upgrade Example (14.3 → 14.4)

### 1. Check your current state

```sh
freebsd-version
bectl list
zpool status
```

Make sure your pool is healthy and you know which BE is active before you start.

### 2. Create a dated clone

```sh
sudo bectl create upgrade-$(date +%Y%m%d)
```

This creates a new BE named something like `upgrade-20260428`. It is an instant ZFS clone — no data is copied, it costs almost no disk space initially.

### 3. Mount the clone and run `freebsd-update` against it

**Do not use `bectl jail` for `freebsd-update`.** See the warning section below for why. Instead, mount the BE and point `freebsd-update` at it using `-b`:

```sh
sudo bectl mount upgrade-20260428 /mnt
sudo freebsd-update -b /mnt fetch
sudo freebsd-update -b /mnt install
sudo bectl umount upgrade-20260428
```

`freebsd-update` will download patches and write the new binaries and kernel into the clone at `/mnt`, not into your live root.

### 4. Jail into the clone to upgrade packages

Once the base system files are updated in the clone, you can safely use `bectl jail` to upgrade your third-party packages. The jail is appropriate here because `pkg` does not need to interact with the running kernel:

```sh
sudo bectl jail upgrade-20260428
```

Inside the jail:

```sh
pkg update
pkg upgrade
exit
```

Exiting the shell shuts down the transient jail. Your live system has still not been touched.

### 5. Activate for a single test boot

```sh
sudo bectl activate -t upgrade-20260428
sudo shutdown -r now
```

The `-t` flag means: boot into this environment once only. If the system reboots a second time for any reason — including a crash or power failure — the bootloader automatically returns to your original 14.3 environment.

### 6. Verify

After rebooting, confirm you are in the right environment:

```sh
freebsd-version
bectl list
```

In `bectl list` output:
- `N` — currently booted (now)
- `R` — will boot on next reboot (your default)

If `-t` worked correctly, you will see `N` next to `upgrade-20260428` but `R` still pointing at your old environment.

Check your services are running as expected.

### 7. Make it permanent (or discard)

**If everything looks good:**

```sh
sudo bectl activate upgrade-20260428
```

This sets the new environment as the permanent default. Your old 14.3 BE is still intact and listed — you can keep it for a while as a fallback, then remove it when you are confident:

```sh
sudo bectl destroy 14.3-be-name
```

**If something is wrong:**

Simply reboot. The bootloader falls back to your original environment automatically. Then destroy the failed clone:

```sh
sudo bectl destroy upgrade-20260428
```

---

## What Is Not Recommended: Major Version Upgrades via `bectl jail`


### Why `freebsd-update` does not belong inside a jail

A `bectl jail` shares the **host's running kernel**. `freebsd-update` was designed to run on the base system, not inside a jail. When you run it inside a jail, it may:

- Detect that it is running in a jailed environment and refuse certain operations
- Compare the running kernel version (the host's) against what it is trying to install, producing errors or refusing to proceed
- Silently skip steps that it considers unsafe in a jailed context

The result is an unreliable upgrade process where you cannot be certain what was actually applied and what was skipped.

### The correct approach for major upgrades

For a major version jump (e.g., 14.3 → 15.0), you **mount** the new BE and point `freebsd-update` at the mountpoint using `-b`. This way `freebsd-update` writes into the clone's filesystem without being constrained by the jail environment:

```sh
sudo bectl create 15.0-upgrade
sudo bectl mount 15.0-upgrade /mnt
sudo freebsd-update -b /mnt -r 15.0-RELEASE upgrade
sudo freebsd-update -b /mnt install
sudo bectl umount 15.0-upgrade
```

Then jail in for packages:

```sh
sudo bectl jail 15.0-upgrade
pkg update && pkg upgrade
exit
```

Then activate and test:

```sh
sudo bectl activate -t 15.0-upgrade
sudo shutdown -r now
```

After a successful boot into 15.0, run a final install pass to clean up old libraries and kernel modules left over from 14.x:

```sh
sudo freebsd-update install
sudo bectl activate 15.0-upgrade
```

### An additional caution about 15.0 specifically

As of April 2026, FreeBSD 15.0-RELEASE is supported only until **September 30, 2026** — roughly five months away. If you are on 14.3, you may want to consider:

- Upgrading to **14.4** (released March 2026) first — a straightforward minor upgrade within the same branch
- Waiting for **15.1** (due June 2026) before jumping to the 15.x series

The 14.x branch is supported until November 2028, giving you considerably more runway without pressure.

---

## Quick Reference

| Task | Command |
|---|---|
| List boot environments | `bectl list` |
| Create a clone | `sudo bectl create <name>` |
| Mount a BE | `sudo bectl mount <name> /mnt` |
| Unmount a BE | `sudo bectl umount <name>` |
| Jail into a BE | `sudo bectl jail <name>` |
| Apply freebsd-update to a mounted BE | `sudo freebsd-update -b /mnt fetch` / `install` |
| Activate permanently | `sudo bectl activate <name>` |
| Activate for one boot only | `sudo bectl activate -t <name>` |
| Destroy a BE | `sudo bectl destroy <name>` |

---

## Summary

| Use case | Use `bectl jail`? | Use `-b /mnt`? |
|---|---|---|
| `pkg upgrade` (packages) | Yes | Not needed |
| Minor base patches (`freebsd-update`) | No | Yes |
| Major version upgrade (`freebsd-update -r`) | No | Yes |

The boot environment wrapper protects you in all cases — the difference is only in *how* you write into the clone.
