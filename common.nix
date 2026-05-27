{ config, pkgs, ... }:

{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.networkmanager.enable = true;

  i18n.defaultLocale = "en_US.UTF-8";

  users.users.root = {
    openssh.authorizedKeys.keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILgtWm9T8vrKrhIVqQniTixy7e/SxSvBbkRsM9/Ohpb+"];
  };

  users.users.toasty = {
    isNormalUser = true;
    initialPassword = "changeme"; # change after first login
    extraGroups = [ "wheel" "networkmanager" ];
  };

  environment.shellAliases = {
    rebuild = "sudo nixos-rebuild switch --flake /etc/nixos#${config.networking.hostName}";
    upgrade = "sudo nix flake update --flake /etc/nixos && rebuild";
  };

  services.openssh.enable = true;

  nixpkgs.config.allowUnfree = true;

  nix.gc.automatic = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  system.stateVersion = "25.11"; 
}
