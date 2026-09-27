{ config, pkgs, ... }:

{
  networking.hostName = "proxy"; 
  imports = [
    ./modules/portProxy.nix
    #./modules/3x-ui.nix
    ./modules/d2ray.nix
    ../../modules/networking/netbird.nix
  ];

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
