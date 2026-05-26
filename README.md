nixos-generate-config --show-hardware-config > ./hardware-configuration.nix

sudo nixos-rebuild switch --flake .#power
sudo nixos-rebuild switch --flake .#proxy
