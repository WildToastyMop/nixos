# bigscreen — TV box host

Mac mini (Late 2012), model identifier **Macmini6,1**, running KDE Plasma
Bigscreen as an appliance.

| | |
|---|---|
| CPU | Intel Core i5-3210M — **2 cores / 4 threads**, Ivy Bridge |
| GPU | Intel HD Graphics 4000 — PCI `8086:0166` (Ivy Bridge GT2) |
| Quick Sync | **H.264 decode + encode only.** No HEVC, no VP8, no VP9, no AV1 |
| Output | HDMI 1.4 + Thunderbolt 1 (DisplayPort 1.1a). **Max 2560×1600 @60; 4K only @30, if at all** |
| I/O | Gigabit Ethernet, 4× USB 3.0, SDXC |
| Stock | 4 GB RAM (2×2), 500 GB 5400 rpm HDD |

**The whole host config follows from one fact: H.264 is the only codec this
machine can decode in hardware.** Everything else lands on a 2-core CPU and
will drop frames. Treat this as a 1080p60 H.264 box.

## Build

```bash
# on the machine, generate the real hardware config straight into this host's
# folder:
nixos-generate-config --show-hardware-config > hosts/bigscreen/hardware-configuration.nix
# (the fileSystems UUIDs in there are placeholders until you do), then:
sudo nixos-rebuild switch --flake .#bigscreen
# or from another host / the repo:
nixos-rebuild switch --flake .#bigscreen --target-host root@bigscreen
```

### Boot: EFI + removable GRUB, not CSM

Apple's EFI 1.x ignores NVRAM boot entries, so `boot.loader.grub`
uses `efiInstallAsRemovable = true`, which writes `EFI/BOOT/BOOTX64.EFI`.
At boot, hold **Option** and pick **EFI Boot**.

Do **not** enable the legacy BIOS/CSM path. It requires a hybrid MBR, and the
rEFInd author's own guidance is that it "turns the boot process into a
coin-toss". If you want a nicer boot menu, install rEFInd *later*, from the
running system, so it picks up the ext4 driver and can actually see your
kernel:

```bash
sudo mount /dev/disk/by-uuid/<ESP-UUID> /boot
sudo refind-install
# if rEFInd can't see the kernel, drop ext4_x64.efi into
# /boot/EFI/refind/drivers_x64/
```

### sops: this host needs its own age key

`common.nix` sets `hashedPasswordFile = config.sops.secrets.user-password.path`,
and secrets are encrypted to a fixed recipient list in `secrets/.sops.yaml`
(currently `primary`, `power`, `proxy`). A brand-new host will **fail to
decrypt** and `toasty` will end up with no usable password.

1. On the Mac mini, get its age recipient from the SSH host key:

   ```bash
   nix-shell -p ssh-to-age --run \
     'ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub'
   ```

2. Add it to `secrets/.sops.yaml` and to the `user-password.yaml` rule:

   ```yaml
   keys:
     - &bigscreen age1...
   creation_rules:
     - path_regex: .*user-password\.yaml$
       key_groups:
         - age:
           - *primary
           - *proxy
           - *power
           - *bigscreen
   ```

3. Re-wrap the data key (needs an existing key that can already decrypt):

   ```bash
   sops updatekeys secrets/user-password.yaml
   ```

Only `user-password.yaml` is needed by this host.

## Upgrades that matter more than anything in this config

- **16 GB RAM** (2×8 GB DDR3-1600 SODIMM). The 2012 mini is user-upgradeable;
  Plasma 6 + Chromium/Electron on 4 GB is painful.
- **SATA SSD** in place of the 5400 rpm drive. Biggest single win.

## Apps

| App | Where it comes from |
|---|---|
| **VacuumTube** | `modules/apps/vacuumtube.nix` — **not in nixpkgs**, so this wraps the upstream `VacuumTube-x86_64.AppImage`, pinned to `v1.8.2` with a verified `sha256` for both the AppImage and the icon. Installs `$out/bin/vacuumtube` plus its own desktop entry, so it shows up in the Bigscreen launcher |
| **Fladder** | `modules/apps/fladder.nix` — straight from nixpkgs (`pkgs.fladder`, built from source with `buildFlutterApplication`). nixpkgs already ships its desktop entry (`AudioVideo;Video;Player`) and scalable icon, so nothing extra is needed |
| **Moonlight** | `moonlight-qt` in `default.nix` |
| **Plasma Bigscreen** | `pkgs.kdePackages.plasma-bigscreen`, registered as a wayland session via `services.displayManager.sessionPackages` |

To bump VacuumTube: change `version` in `modules/apps/vacuumtube.nix` and let the
build tell you the new hashes (leave the old ones in place, `nixos-rebuild`
prints the correct `sha256` on mismatch). Grabbing the icon hash uses the same
tag: `assets/icon.png`.

### If VacuumTube won't start

It's an Electron AppImage, so the two usual causes are:

- **Sandbox.** Launch with `--no-sandbox`, or export
  `ELECTRON_DISABLE_SANDBOX=1`. On NixOS the namespace sandbox normally works
  (unprivileged user namespaces are enabled for Chromium/Flatpak), so treat this
  as a fallback — don't set it globally.
- **Missing host library.** Run `vacuumtube` from a terminal to see which `lib*`
  it wants, add that to `extraPkgs` in the module, rebuild.

## Steer every app onto H.264

### VacuumTube (YouTube Leanback)

YouTube serves VP9/AV1 by default. Neither decodes in hardware here, and 2
cores can't software-decode 1080p VP9 reliably. VacuumTube ships an h264ify
module (`src/preload/modules/h264ify.js`) — open its settings with **Ctrl+O**
and set:

| Setting | Value |
|---|---|
| `h264ify` | on |
| `h264ify_disable_vp9` | **on** |
| `h264ify_disable_av1` | on |
| `h264ify_disable_vp8` | on |
| `h264ify_disable_webm` | leave **off** (blocking VP8/VP9 already covers it) |

YouTube then serves `avc1`/H.264 and Quick Sync does the work.

### Moonlight

Set the client codec to **H.264**, 1080p60, ~15–20 Mbps. H.264 hardware decode
is exactly what this GPU is good at. HEVC would be software-decoded and
unusable. Use **wired Ethernet**.

### Fladder / Jellyfin

VA-API through mpv/FFmpeg handles H.264 fine; **1080p HEVC software decode on
2 cores is a coin flip**. If the library is HEVC-heavy, let the *server*
transcode to H.264 for this client instead of trying to decode locally.

## Verify after install

```bash
vainfo                 # want: i965 / Ivybridge entries with H264 decode
glxinfo -B             # want: Mesa ... HD Graphics 4000 (IVB GT2), NOT llvmpipe
kscreen-doctor -o      # confirms the resolution/refresh actually offered
intel_gpu_top          # watch "Video" while playing something
```

If anything reports `llvmpipe`, the GL/GLES env vars in `default.nix`
(`KWIN_COMPOSE=O2ES`, `QSG_RHI_BACKEND=opengl`) aren't reaching the session.

## Remote control

Three options, in increasing order of quality:

1. **Mac mini's built-in IR receiver** — works out of the box via the kernel's
   `hid-appleir`. Caveat: the ring's up/down report as volume, so you'd remap
   for D-pad navigation.
2. **KDE Connect** on your phone (`programs.kdeconnect.enable = true`).
3. **The DIY TTVKTR dongle** — RP2040 + 38 kHz receiver + `firmware_with_fs.uf2`
   from <https://github.com/Brisk4t/TossedTheTVKeptTheRemote>. Most capable:
   remappable keys, media/consumer keys, layers. Plugs into any of the four
   USB 3.0 ports.

Note the built-in `plasma-bigscreen-inputhandler` translates CEC TV remotes and
*controller* events into keyboard input; a keyboard-class device like the
TTVKTR dongle bypasses it entirely and just works.

## Installing this host from scratch (it's a 4 GB machine)

`install.sh` will **refuse** to install the full configuration here, and that is
deliberate: a NixOS ISO's writable `/nix/store` is a tmpfs (RAM), and this host's
closure is **~14 GiB** — more than the machine has memory. The script sizes the
closure up front and stops *before* wiping anything.

Use the two-stage route:

```bash
./install.sh bigscreen --disk /dev/sda --bootstrap-minimal
```

That installs a minimal system (~123 MiB of fetch) with this box's SSH host key
already in place, sshd, NetworkManager and an 8 GB swapfile. Then finish on the
box itself, where `/nix/store` is the 465 GB disk:

```bash
# a fresh minimal install has no git and no nixpkgs channel, so
# 'nix-shell -p git' cannot resolve <nixpkgs> — use the flake registry
nix shell nixpkgs#git -c git clone https://github.com/WildToastyMop/nixos /etc/nixos

# the repo's committed copy is a placeholder — regenerate it from the machine
nixos-generate-config --show-hardware-config \
  > /etc/nixos/hosts/bigscreen/hardware-configuration.nix

nixos-rebuild switch --flake /etc/nixos#bigscreen
```

Expect step 3 to be **long**: Fladder is built from source, which drags in the
whole Flutter/Dart toolchain on two cores. The swapfile declared in
`default.nix` — not in the generated hardware config, so regeneration can't drop
it — is what makes that survivable.
