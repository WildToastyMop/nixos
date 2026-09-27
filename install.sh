#!/usr/bin/env bash
set -Eeuo pipefail

REPO_URL="${REPO_URL:-https://github.com/WildToastyMop/nixos.git}"
ESP_SIZE="${ESP_SIZE:-512MiB}"
DRY_RUN=0
ASSUME_YES=0
SKIP_SOPS=0
HOST=""
DISK=""
MOUNTED=0

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
  if [ "$MOUNTED" = 1 ] && [ "$rc" != 0 ]; then
    warn "unmounting after failure"
    umount -R /mnt 2>/dev/null || true
  fi
  exit "$rc"
}
trap cleanup EXIT

[ -f "$0" ] || die "run this as a file, e.g. ./install.sh bigscreen --disk /dev/sda (don't pipe it into a shell)"

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

say "preflight"

[ "$(id -u)" = 0 ] || die "must run as root (it's partitioning a disk)"

[ -d /sys/firmware/efi ] || die "not booted in UEFI mode — reboot the ISO and pick 'EFI Boot'"
command -v nixos-install >/dev/null || die "nixos-install not found — run this from a NixOS ISO"
command -v sgdisk >/dev/null || die "sgdisk not found (it's in gptfdisk; you're probably not on a NixOS ISO)"

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

[ -b "$DISK" ] || die "$DISK is not a block device"
[ -e "/sys/class/block/$(basename "$DISK")/partition" ] \
  && die "$DISK is a partition — pass the whole disk (e.g. /dev/sda, not /dev/sda1)"

if [ -n "$(lsblk -no MOUNTPOINT "$DISK" 2>/dev/null | grep -v '^$' || true)" ]; then
  die "$DISK has mounted partitions — unmount them first"
fi

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

say "staging an SSH host key to work out the sops recipient"
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

say "partitioning $DISK"
run sgdisk --zap-all "$DISK"
run sgdisk --set-alignment=2048 \
  --new=1:0:+"$ESP_SIZE" --typecode=1:ef00 --change-name=1:ESP \
  --new=2:0:0         --typecode=2:8300 --change-name=2:nixos \
  "$DISK"
run partprobe "$DISK"
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

say "installing the staged SSH host key"
if [ "$DRY_RUN" != 1 ]; then
  install -d -m 0755 /mnt/etc/ssh
  install -m 0600 "$HOSTKEY" /mnt/etc/ssh/ssh_host_ed25519_key
  install -m 0644 "$HOSTKEY.pub" /mnt/etc/ssh/ssh_host_ed25519_key.pub
  rm -rf "$STAGE"
fi

if [ "$DRY_RUN" != 1 ] && git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$REPO" add -f "hosts/$HOST/hardware-configuration.nix"
fi

say "nixos-install (this is the long part)"
run nixos-install --flake "$REPO#$HOST" --no-root-passwd --no-channel-copy

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
