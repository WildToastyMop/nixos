{ config, pkgs, ... }:

{

  networking.networkmanager.enable = true;

  i18n.defaultLocale = "en_US.UTF-8";

  nix.settings = {
    substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  users.users.root = {
    openssh.authorizedKeys.keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILgtWm9T8vrKrhIVqQniTixy7e/SxSvBbkRsM9/Ohpb+"];
  };

  users.users.toasty = {
    isNormalUser = true;
    hashedPasswordFile = config.sops.secrets.user-password.path;
    extraGroups = [ "wheel" "networkmanager" "video" "render" ];
  };

  sops.secrets.user-password = {
    sopsFile = ./secrets/user-password.yaml;
  };
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  environment.shellAliases = {
    rebuild = "sudo nixos-rebuild switch --flake /etc/nixos#${config.networking.hostName}";
    upgrade = "sudo nix flake update --flake /etc/nixos && rebuild";
  };
  environment.sessionVariables = {
    SOPS_AGE_KEY_FILE = "/etc/ssh/ssh_host_ed25519_key";
  };

  services.openssh.enable = true;

  nixpkgs.config.allowUnfree = true;

  nix.gc.automatic = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  system.stateVersion = "25.11"; 
}
