{ config, pkgs, ... }:

{
  networking.hostName = "power"; 

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  imports = [
    ./modules/networking/proxy-client.nix
    ../../modules/networking/netbird.nix
    ../../modules/driver/nvidia.nix
  ];
 
  networking.interfaces.eth0.ipv4.addresses = [{
    address = "192.168.1.24";
    prefixLength = 24;
  }];
  networking.defaultGateway = "192.168.1.1";

  environment.systemPackages = with pkgs; [
    sops
    net-tools
    git
    tmux
  ];

}
