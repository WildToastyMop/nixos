# Hardware config is per host, generated on the machine itself:
#   nixos-generate-config --show-hardware-config > hosts/<host>/hardware-configuration.nix
#   git -C /etc/nixos add hosts/<host>/hardware-configuration.nix
# /hardware-configuration.nix is gitignored (root-anchored, so a stray
# generate in the repo root can't be committed); the per-host copies under
# hosts/<host>/ are tracked normally.

sudo nixos-rebuild switch --flake .#power
sudo nixos-rebuild switch --flake .#proxy
sudo nixos-rebuild switch --flake .#desktop
sudo nixos-rebuild switch --flake .#bigscreen

# Provisioning a fresh machine: boot a NixOS live ISO (UEFI) on the target,
# get this repo onto it, then:
#
#   ./install.sh bigscreen --disk /dev/sda            # asks before erasing
#   ./install.sh bigscreen --disk /dev/sda --dry-run  # show what it would do
#
# It partitions + formats the disk, writes that host's
# hosts/<host>/hardware-configuration.nix from the real machine, pre-seeds the
# SSH host key so you can add the sops age recipient *before* first boot, and
# runs nixos-install. It erases the whole disk — see ./install.sh --help.
