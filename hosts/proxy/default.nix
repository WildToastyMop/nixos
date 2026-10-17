{ config, pkgs, ... }:

{
  networking.hostName = "proxy";
  imports = [
    ./modules/portProxy.nix
    #./modules/3x-ui.nix
    ./modules/d2ray.nix
    ./modules/mediaflow.nix
    ./modules/caddy.nix
    ../../modules/networking/netbird.nix
  ];

  # Key-only SSH — this host is on the public internet (port 22 exposed),
  # so password authentication is a brute-force liability. Log in with a key.
  services.openssh.settings = {
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
    PermitRootLogin = "prohibit-password";
  };

  boot.loader.grub.device = "/dev/vda";

  networking.firewall.allowedTCPPorts = [ 55108 ];
  networking.firewall.allowedUDPPorts = [ 55108 ];

  networking.firewall.trustedInterfaces = [ "wg0" ];

  virtualisation.containers.enable = true;
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };
  virtualisation.containers.registries.search = [ "docker.io" "quay.io" "ghcr.io" ];

  environment.systemPackages = with pkgs; [
    nftables
    net-tools
    git
    tmux
  ];

}
