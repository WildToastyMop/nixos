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
# WARNING: this erases the whole target disk. On a Mac it will take macOS with
# it — there is no dual-boot mode here. Back up first.
#
set -Eeuo pipefail

REPO_URL="${REPO_URL:-https://github.com/WildToastyMop/nixos.git}"
ESP_SIZE="${ESP_SIZE:-512MiB}"
DRY_RUN=0
ASSUME_YES=0
SKIP_SOPS=0
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
  -h, --help          this text

notes:
  - run this from a NixOS live ISO on the target, booted UEFI
  - the ISO already has every tool needed; ssh-to-age is fetched automatically
  - network IS required: flake inputs come from GitHub, and the system closure
    (a few GB) is downloaded from cache.nixos.org

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

# The ssh-to-age bootstrap further down re-executes this script *by path*, so it
# has to be a real file. Piping it into a shell (bash < install.sh) loses $0/$@
# and the re-exec would then run the wrong thing — fail loudly instead.
[ -f "$0" ] || die "run this as a file, e.g. ./install.sh bigscreen --disk /dev/sda (don't pipe it into a shell)"

# ----------------------------------------------------------------- args
while [ $# -gt 0 ]; do
  case "$1" in
    --disk)            DISK="${2:?--disk needs a device}"; shift 2 ;;
    --disk=*)          DISK="${1#*=}"; shift ;;
    --yes|-y)          ASSUME_YES=1; shift ;;
    --dry-run)         DRY_RUN=1; shift ;;
    --skip-sops-check) SKIP_SOPS=1; shift ;;
    -h|--help)         usage; exit 0 ;;
    -*)                die "unknown option: $1 (try --help)" ;;
    *)                 [ -n "$HOST" ] && die "only one host at a time"; HOST="$1"; shift ;;
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

cat <<EOF

${B}This will erase $DISK ($DISK_SIZE):${N}
  - GPT: one ${ESP_SIZE} EFI system partition + the rest as a single ext4 root
  - root mounted at /mnt, ESP at /mnt/boot
  - hosts/$HOST/hardware-configuration.nix regenerated from this machine
  - nixos-install --flake $REPO#$HOST

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

say "nixos-install (this is the long part)"
run nixos-install --flake "$REPO#$HOST" --no-root-passwd --no-channel-copy

# ----------------------------------------------------------------- done
if [ "$DRY_RUN" = 1 ]; then
  say "dry run complete — nothing was changed"
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
