#!/usr/bin/env bash
#
# Provision a NixOS host from this flake.
#
# Run this from a NixOS live ISO (UEFI boot) on the machine you're setting up:
#
#   # get the repo onto the target — clone, or copy from a USB stick
#   nix-shell -p git --run 'git clone https://github.com/WildToastyMop/nixos /tmp/nixos'
#   cd /tmp/nixos
#   ./install.sh bigscreen --disk /dev/sda
#
# It will: partition + format the disk, generate that host's
# hardware-configuration.nix into ./hosts/<host>/, pre-seed the SSH host key so
# you can add its age recipient to sops *before* first boot, then run
# nixos-install. Nothing else in the repo is touched.
#
# Low-RAM machines: a NixOS ISO's /nix/store is an overlay whose writable layer
# is a tmpfs (RAM), so the whole closure has to fit in memory. A Plasma desktop
# is ~14 GiB and a 4 GB box has ~2 GB, which cannot work. The script measures
# this up front and refuses; add --bootstrap-minimal to install a small system
# instead and build the real one on the box afterwards (see the epilogue).
#
# WARNING: this erases the whole target disk. On a Mac it will take macOS with
# it — there is no dual-boot mode here. Back up first.
#
set -Eeuo pipefail

REPO_URL="${REPO_URL:-https://github.com/WildToastyMop/nixos.git}"
ESP_SIZE="${ESP_SIZE:-512MiB}"
DRY_RUN=0
ASSUME_YES=0
SKIP_SOPS=0
BOOTSTRAP_MINIMAL=0
BOOTSTRAP_SWAP_MIB=8192
HOST=""
DISK=""
MOUNTED=0

# ----------------------------------------------------------------- boilerplate
if [ -t 1 ]; then
  B=$'\033[1m'; R=$'\033[31m'; Y=$'\033[33m'; G=$'\033[32m'; N=$'\033[0m'
else
  B=""; R=""; Y=""; G=""; N=""
fi
say()  { printf '%s\n' "${B}==>${N} $*"; }
warn() { printf '%s\n' "${Y}warning:${N} $*" >&2; }
die()  { printf '%s\n' "${R}error:${N} $*" >&2; exit 1; }
run()  { if [ "$DRY_RUN" = 1 ]; then printf '  %s[skip]%s %s\n' "$Y" "$N" "$*"; else "$@"; fi; }

usage() {
  cat <<EOF
${B}usage:${N} ./install.sh <host> --disk <device> [options]

  <host>              flake host to install, e.g. bigscreen
  --disk <device>     whole disk to erase and install onto, e.g. /dev/sda
                      (required — there is no default, on purpose)

options:
  --yes               non-interactive: skip the confirmation prompts
  --dry-run           print what would happen, touch nothing
  --skip-sops-check   don't insist that the host's age recipient is already
                      in secrets/.sops.yaml (only do this if you know why)
  --bootstrap-minimal install a minimal system that fits in the installer's
                      RAM-backed store, then build the real one on the box.
                      Use this when the closure is bigger than memory
                      (e.g. a Plasma desktop on a 4 GB machine).
  --bootstrap-swap-mib <n>
                      swapfile size for the bootstrap system (default $BOOTSTRAP_SWAP_MIB,
                      0 to skip). The real system is built ON the box, so it
                      needs swap if RAM is small.
  -h, --help          this text

notes:
  - run this from a NixOS live ISO on the target, booted UEFI
  - the ISO already has every tool needed; ssh-to-age is fetched automatically
  - network IS required: flake inputs come from GitHub, and the system closure
    (a few GB) is downloaded from cache.nixos.org
  - the ISO's writable /nix/store is a tmpfs, i.e. RAM — the closure must fit

environment:
  REPO_URL            git remote to clone if not already in a checkout
                      (default: $REPO_URL)
  ESP_SIZE            EFI system partition size (default: $ESP_SIZE)
EOF
}

cleanup() {
  local rc=$?
  # NB: deliberately does NOT remove $STAGE. The staged host key has to survive a
  # failed run so the recipient is identical when you re-run after updatekeys.
  # The success path deletes it once it's installed into the target.
  if [ "$MOUNTED" = 1 ] && [ "$rc" != 0 ]; then
    warn "unmounting after failure"
    umount -R /mnt 2>/dev/null || true
  fi
  exit "$rc"
}
trap cleanup EXIT

# This has to be a real file: it takes its own path for the epilogue and would
# otherwise be re-run from a pipe with no $0/$@.
[ -f "$0" ] || die "run this as a file, e.g. ./install.sh bigscreen --disk /dev/sda (don't pipe it into a shell)"

# ----------------------------------------------------------------- args
while [ $# -gt 0 ]; do
  case "$1" in
    --disk)              DISK="${2:?--disk needs a device}"; shift 2 ;;
    --disk=*)            DISK="${1#*=}"; shift ;;
    --yes|-y)            ASSUME_YES=1; shift ;;
    --dry-run)           DRY_RUN=1; shift ;;
    --skip-sops-check)   SKIP_SOPS=1; shift ;;
    --bootstrap-minimal) BOOTSTRAP_MINIMAL=1; shift ;;
    --bootstrap-swap-mib)      BOOTSTRAP_SWAP_MIB="${2:?--bootstrap-swap-mib needs MiB}"; shift 2 ;;
    --bootstrap-swap-mib=*)    BOOTSTRAP_SWAP_MIB="${1#*=}"; shift ;;
    -h|--help)           usage; exit 0 ;;
    -*)                  die "unknown option: $1 (try --help)" ;;
    *)                   [ -n "$HOST" ] && die "only one host at a time"; HOST="$1"; shift ;;
  esac
done

[ -n "$HOST" ] || { usage; exit 1; }
[ -n "$DISK" ] || die "--disk <device> is required (try --help)"

# ---------------------------------------------------------------- helpers --
# ssh-to-age is the one tool a NixOS ISO does not ship. Rather than re-executing
# this whole script under nix-shell (which needs $0/$@ to survive the trip), run
# only that single command through nix-shell when it's missing. Everything else
# the script needs — sgdisk/gptfdisk, mkfs.fat via vfat support, mkfs.ext4,
# ssh-keygen, git, jq — is already on the ISO.
ssh_to_age() {
  if command -v ssh-to-age >/dev/null 2>&1; then
    ssh-to-age
  elif command -v nix-shell >/dev/null 2>&1; then
    say "ssh-to-age isn't in the ISO — fetching it via nix-shell (needs network)" >&2
    nix-shell -p ssh-to-age --run "ssh-to-age"
  else
    return 127
  fi
}

nix_flake() { nix --extra-experimental-features "nix-command flakes" "$@"; }

# ----------------------------------------------------------------- preflight
say "preflight"

[ "$(id -u)" = 0 ] || die "must run as root (it's partitioning a disk)"

[ -d /sys/firmware/efi ] || die "not booted in UEFI mode — reboot the ISO and pick 'EFI Boot'"
command -v nixos-install >/dev/null || die "nixos-install not found — run this from a NixOS ISO"
command -v sgdisk >/dev/null || die "sgdisk not found (it's in gptfdisk; you're probably not on a NixOS ISO)"

# find the repo: use $PWD if it looks like this flake, otherwise clone it
if [ -f flake.nix ] && grep -q 'nixosConfigurations' flake.nix; then
  REPO="$PWD"
else
  REPO="/tmp/nixos-$$"
  warn "no flake.nix here — cloning $REPO_URL to $REPO"
  command -v git >/dev/null || die "git not found (nix-shell -p git)"
  run git clone --depth 1 "$REPO_URL" "$REPO"
fi
say "repo: $REPO"

grep -qE "^ *$HOST = lib\.nixosSystem" "$REPO/flake.nix" \
  || die "no host '$HOST' in $REPO/flake.nix"
[ -f "$REPO/hosts/$HOST/default.nix" ] \
  || die "missing $REPO/hosts/$HOST/default.nix"

# the disk must be a whole, unmounted, non-live block device
[ -b "$DISK" ] || die "$DISK is not a block device"
[ -e "/sys/class/block/$(basename "$DISK")/partition" ] \
  && die "$DISK is a partition — pass the whole disk (e.g. /dev/sda, not /dev/sda1)"

if [ -n "$(lsblk -no MOUNTPOINT "$DISK" 2>/dev/null | grep -v '^$' || true)" ]; then
  die "$DISK has mounted partitions — unmount them first"
fi

# refuse the disk that any currently-mounted filesystem lives on — that's how
# you'd otherwise wipe the live ISO's own USB stick
while read -r src; do
  [ -b "$src" ] || continue
  parent="$(lsblk -no PKNAME "$src" 2>/dev/null | head -n1 || true)"
  if [ -n "$parent" ] && [ "/dev/$parent" = "$DISK" ]; then
    die "$DISK carries a live/mounted filesystem ($src) — that's your installer, pick another disk"
  fi
done < <(findmnt -rno SOURCE | sort -u)

DISK_SIZE="$(lsblk -bdno SIZE "$DISK" | numfmt --to=iec)"
say "target: $DISK ($DISK_SIZE)"

# -------------------------------------------------------------------- fit --
# How big is the system, and does the installer's store have room for it? On a
# NixOS ISO /nix/store is an overlay over the squashfs whose writable layer is a
# tmpfs (RAM), so the *entire* closure has to fit in memory. Learning that here,
# before the disk is wiped, beats discovering it 20 minutes into nixos-install.
say "sizing the closure against the installer's store"
need_mib=0
plan="$(nix_flake build --dry-run \
          "$REPO#nixosConfigurations.$HOST.config.system.build.toplevel" 2>&1 || true)"
need_human="$(printf '%s\n' "$plan" | grep -oE '[0-9.]+ (KiB|MiB|GiB) unpacked' | tail -n1 || true)"
need_human="${need_human% unpacked}"     # "13.9 GiB unpacked" -> "13.9 GiB"
if [ -n "$need_human" ]; then
  num="${need_human%% *}"; unit="${need_human##* }"
  whole="${num%%.*}"; frac="${num#*.}"
  [ "$frac" = "$num" ] && frac=0
  case "$unit" in
    KiB) need_mib=$(( whole / 1024 )) ;;
    MiB) need_mib=$(( whole )) ;;
    GiB) need_mib=$(( whole * 1024 + frac * 1024 / 10 )) ;;
    *)   warn "unrecognised size '$need_human' — treating the estimate as unknown"
         need_mib=0 ;;
  esac
fi
avail_mib="$(df -Pm /nix/store 2>/dev/null | tail -n1 | tr -s ' ' | cut -d' ' -f4 || true)"
case "$avail_mib" in ''|*[!0-9]*) avail_mib=0 ;; esac

if [ "$need_mib" -gt 0 ] && [ "$avail_mib" -gt 0 ] && [ "$need_mib" -gt "$avail_mib" ]; then
  warn "this system needs ~${need_mib} MiB of store, but only ${avail_mib} MiB is writable here"
  warn "that writable layer is a tmpfs — i.e. RAM — so the closure has to fit in memory"
  if [ "$BOOTSTRAP_MINIMAL" != 1 ]; then
    cat <<EOF

  ${Y}This install cannot finish on this machine.${N} Either:

  1) two-stage (the low-RAM route) — install a small system now, finish on the box:
       ./install.sh $HOST --disk $DISK --bootstrap-minimal
     then boot it and, on that machine:
       nixos-rebuild switch --flake /etc/nixos#$HOST

  2) give the installer 8 GB+ of RAM, or run from a machine whose
     /nix/store is on disk.

EOF
    die "refusing to wipe $DISK for an install that cannot complete"
  fi
  say "--bootstrap-minimal: installing a minimal system; the real one gets built on the box"
elif [ "$need_mib" -gt 0 ]; then
  say "closure ~${need_mib} MiB, ${avail_mib} MiB writable — fits"
else
  warn "could not work out the closure size — carrying on"
fi

cat <<EOF

${B}This will erase $DISK ($DISK_SIZE):${N}
  - GPT: one ${ESP_SIZE} EFI system partition + the rest as a single ext4 root
  - root mounted at /mnt, ESP at /mnt/boot
  - hosts/$HOST/hardware-configuration.nix regenerated from this machine
$(if [ "$BOOTSTRAP_MINIMAL" = 1 ]; then
  echo "  - nixos-install of a MINIMAL bootstrap system (--bootstrap-minimal)"
  echo "    the real configuration is built on the box after first boot"
else
  echo "  - nixos-install --flake $REPO#$HOST"
fi)

EOF

if [ "$DRY_RUN" != 1 ]; then
  if [ "$ASSUME_YES" = 1 ]; then
    :
  elif [ ! -t 0 ]; then
    die "no TTY to confirm on — re-run with --yes for a non-interactive install"
  else
    printf 'Type the device name to confirm (%s): ' "$DISK"
    read -r confirm
    [ "$confirm" = "$DISK" ] || die "aborted"
  fi
fi

# -------------------------------------------------------------------- sops --
# Deliberately BEFORE any destructive step. sops-nix decrypts with the machine's
# SSH host key, and if the recipient isn't in .sops.yaml the installed system
# can't set the user password — so find that out while the disk is still intact.
#
# Note which key matters: the ONE BELOW becomes /etc/ssh/ssh_host_ed25519_key on
# the installed system, and that is the identity sops uses. It is deliberately
# not the installer's own sshd key, which is regenerated on every ISO boot — so
# the recipient you authorise is the one printed here, not the key you happen to
# be connected to right now.
say "staging an SSH host key to work out the sops recipient"
# Stable path on purpose. Adding the recipient to .sops.yaml and re-running is a
# two-phase dance, so the *same* key — and therefore the same recipient — has to
# survive between runs. This is the machine's own host key, it only ever lives
# on the installer's RAM disk, and it's deleted once installed into the target.
STAGE="${STAGE_DIR:-/root/.install-ssh-$HOST}"
HOSTKEY="$STAGE/ssh_host_ed25519_key"
if [ "$DRY_RUN" != 1 ]; then
  if [ -f "$HOSTKEY" ]; then
    say "reusing the staged host key at $HOSTKEY"
  else
    install -d -m 0700 "$STAGE"
    ssh-keygen -q -t ed25519 -N '' -C "$HOST host key" -f "$HOSTKEY"
    chmod 600 "$HOSTKEY"
  fi

  RECIPIENT="$(ssh_to_age < "$HOSTKEY.pub" || true)"
  if [ -z "$RECIPIENT" ]; then
    warn "ssh-to-age unavailable — cannot compute the recipient or verify sops."
    warn "staged key: $HOSTKEY — recipient: ssh-to-age < $HOSTKEY.pub"
  else
    printf '\n  %sadd this to secrets/.sops.yaml as:  - &%s %s%s\n\n' "$B" "$HOST" "$RECIPIENT" "$N"
    printf '  then, from a machine that can already decrypt:\n'
    printf '    sops updatekeys secrets/user-password.yaml --yes\n'
    printf '  ...get that change into %s, then re-run this script.\n\n' "$REPO"

    if [ "$SKIP_SOPS" = 1 ]; then
      warn "--skip-sops-check: not verifying that this host can decrypt its secrets"
    elif grep -q "$RECIPIENT" "$REPO/secrets/.sops.yaml"; then
      say "recipient already present in secrets/.sops.yaml"
    elif [ "$ASSUME_YES" = 1 ] || [ ! -t 0 ]; then
      warn "recipient missing from .sops.yaml — nothing has been written to disk."
      warn "add it to $REPO/secrets/.sops.yaml, run sops updatekeys, then re-run."
      warn "the key is staged at $HOSTKEY, so the recipient will be identical next run."
      exit 2
    else
      printf 'Add it to secrets/.sops.yaml and run sops updatekeys, then press Enter\n'
      printf '(Ctrl-C to abort. --skip-sops-check skips this check.)\n'
      read -r _
      grep -q "$RECIPIENT" "$REPO/secrets/.sops.yaml" \
        || die "recipient still not in secrets/.sops.yaml"
      say "recipient present"
    fi
  fi
fi

# ----------------------------------------------------------------- partition
say "partitioning $DISK"
run sgdisk --zap-all "$DISK"
run sgdisk --set-alignment=2048 \
  --new=1:0:+"$ESP_SIZE" --typecode=1:ef00 --change-name=1:ESP \
  --new=2:0:0         --typecode=2:8300 --change-name=2:nixos \
  "$DISK"
run partprobe "$DISK"
# nvme/mmc name partitions differently than sd*/vd*
case "$DISK" in
  *[0-9]) PART_PREFIX="${DISK}p" ;;
  *)      PART_PREFIX="$DISK" ;;
esac
ESP="${PART_PREFIX}1"
ROOT="${PART_PREFIX}2"

[ "$DRY_RUN" = 1 ] || udevadm settle --timeout=30 || true

say "formatting"
run mkfs.fat -F 32 -n ESP "$ESP"
run mkfs.ext4 -L nixos "$ROOT"

say "mounting"
run mount "$ROOT" /mnt
MOUNTED=1
run mkdir -p /mnt/boot
run mount "$ESP" /mnt/boot

# ----------------------------------------------------------------- hardware
HW="$REPO/hosts/$HOST/hardware-configuration.nix"
say "generating $HW"
if [ "$DRY_RUN" != 1 ]; then
  [ -f "$HW" ] && cp -v "$HW" "$HW.bak"
  if ! nixos-generate-config --root /mnt --show-hardware-config > "$HW.tmp" 2>/dev/null; then
    nixos-generate-config --root /mnt
    cp /mnt/etc/nixos/hardware-configuration.nix "$HW.tmp"
  fi
  mv "$HW.tmp" "$HW"
  say "wrote $(wc -l < "$HW") lines; filesystems:"
  grep -E 'fileSystems|device =' "$HW" | sed 's/^/  /'
fi

# ------------------------------------------------------------------- key --
# Install the host key staged before partitioning. sops-nix reads it from
# /etc/ssh/ssh_host_ed25519_key at activation time.
say "installing the staged SSH host key"
if [ "$DRY_RUN" != 1 ]; then
  install -d -m 0755 /mnt/etc/ssh
  install -m 0600 "$HOSTKEY" /mnt/etc/ssh/ssh_host_ed25519_key
  install -m 0644 "$HOSTKEY.pub" /mnt/etc/ssh/ssh_host_ed25519_key.pub
  rm -rf "$STAGE"
fi

# ----------------------------------------------------------------- install
# A flake in a git checkout only sees tracked/staged files, and the hardware
# config we just generated is brand new — stage it or the build can't find it.
if [ "$DRY_RUN" != 1 ] && git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$REPO" add -f "hosts/$HOST/hardware-configuration.nix"
fi

if [ "$BOOTSTRAP_MINIMAL" = 1 ]; then
  # ------------------------------------------------------- bootstrap install --
  # A minimal system that fits in the installer's RAM store. It deliberately has
  # no sops (so activation can't fail on a secret it can't read yet) and no
  # desktop — the point is to get *a* bootable NixOS on the disk.
  say "writing a minimal bootstrap system into /mnt/etc/nixos"
  if [ "$DRY_RUN" != 1 ]; then
    install -d -m 0755 /mnt/etc/nixos
    cp "$HW" /mnt/etc/nixos/hardware-configuration.nix

    bs_json="$(nix_flake eval --json "$REPO#nixosConfigurations.$HOST.config" --apply \
      'c: { host = c.networking.hostName; state = c.system.stateVersion; tz = c.time.timeZone; keys = c.users.users.root.openssh.authorizedKeys.keys; }' 2>/dev/null || true)"
    bs_get() { printf '%s' "${bs_json:-{\}}" | jq -r "$1" 2>/dev/null || true; }
    bs_host="$(bs_get '.host // empty')";   [ -n "$bs_host" ]  || bs_host="$HOST"
    bs_state="$(bs_get '.state // empty')"; [ -n "$bs_state" ] || bs_state="25.11"
    bs_tz="$(bs_get '.tz // empty')";       [ -n "$bs_tz" ]    || bs_tz="UTC"
    bs_keys="$(bs_get '.keys[]? | "    \(@json)"')"
    [ -n "$bs_keys" ] || warn "no root SSH keys found in the flake — you may need console access"

    {
      cat <<NIX
{ config, lib, pkgs, ... }:
# Minimal bootstrap system generated by install.sh --bootstrap-minimal.
# It exists only to host the build of the real configuration: /nix/store here is
# the disk, so the full closure has room. See the epilogue for the next step.
{
  imports = [ ./hardware-configuration.nix ];

  boot.loader.grub = {
    enable = true;
    device = "nodev";
    efiSupport = true;
    efiInstallAsRemovable = true;
    configurationLimit = 5;
  };
  boot.loader.efi.canTouchEfiVariables = false;

  networking.hostName = "$bs_host";
  networking.networkmanager.enable = true;

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };
  users.users.root.openssh.authorizedKeys.keys = [
$bs_keys
  ];
NIX
      if [ "$BOOTSTRAP_SWAP_MIB" -gt 0 ]; then
        cat <<NIX

  # The real system is built ON this machine, so small-RAM boxes need swap.
  swapDevices = [ { device = "/swapfile"; size = $BOOTSTRAP_SWAP_MIB; } ];
NIX
      fi
      cat <<NIX

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true;
  time.timeZone = "$bs_tz";
  system.stateVersion = "$bs_state";
}
NIX
    } > /mnt/etc/nixos/configuration.nix

    say "wrote /mnt/etc/nixos/configuration.nix (hostname=$bs_host, swap=${BOOTSTRAP_SWAP_MIB} MiB)"
  fi

  say "nixos-install (minimal system — much smaller than the real one)"
  run nixos-install --no-root-passwd --no-channel-copy
else
  say "nixos-install (this is the long part)"
  run nixos-install --flake "$REPO#$HOST" --no-root-passwd --no-channel-copy
fi

# ----------------------------------------------------------------- done
if [ "$DRY_RUN" = 1 ]; then
  say "dry run complete — nothing was changed"
  exit 0
fi

if [ "$BOOTSTRAP_MINIMAL" = 1 ]; then
  cat <<EOF

${G}bootstrap system installed.${N}

  reboot — unplug the USB first, or the Mac will boot it again — and hold
  ${B}Option${N} at the chime → pick ${B}EFI Boot${N}

then, ON that machine:

  1. get the repo. A fresh minimal install has no git and no nixpkgs channel,
     so 'nix-shell -p git' cannot resolve <nixpkgs> — use the flake registry:
       nix shell nixpkgs#git -c git clone https://github.com/WildToastyMop/nixos /etc/nixos

  2. give it THIS machine's hardware config (the repo's copy is a placeholder):
       nixos-generate-config --show-hardware-config > /etc/nixos/hosts/$HOST/hardware-configuration.nix

  3. build the real system. /nix/store is the disk now, so the closure fits:
       nixos-rebuild switch --flake /etc/nixos#$HOST

  Swap (${BOOTSTRAP_SWAP_MIB} MiB) is declared in the bootstrap system precisely so
  step 3 survives a small amount of RAM. Expect a long build if the host pulls in
  anything compiled from source (a Flutter app, for instance).

  The sops key this machine will use is already in place, and it's the recipient
  you authorised above — don't regenerate /etc/ssh/ssh_host_ed25519_key.
EOF
  exit 0
fi

cat <<EOF

${G}installed.${N}

  reboot, and on a Mac hold ${B}Option${N} at the chime → pick ${B}EFI Boot${N}

bring back to your repo:
  1. $REPO/hosts/$HOST/hardware-configuration.nix   (generated here)
  2. secrets/.sops.yaml + re-wrapped secrets, if you did that elsewhere
  3. the host entry in flake.nix, if it was new

don't regenerate this host's SSH host key later — sops decrypts with it,
and /etc/ssh/ssh_host_ed25519_key was pre-seeded here on purpose.

once it's up:
  vainfo              # i965 / Ivybridge with H264 decode
  glxinfo -B          # HD Graphics 4000, not llvmpipe
  kscreen-doctor -o   # confirm the modes the TV actually offers

then see hosts/$HOST/README.md for the codec settings (h264ify in VacuumTube,
H.264 in Moonlight, transcode-to-H.264 for HEVC libraries).
EOF
