{ config, pkgs, ... }:

{
  networking.hostName = "power"; 
  imports = [
    ./modules/proxy-client.nix
    ../../modules/driver/nvidia.nix
  ];
 
  networking.interfaces.eth0.ipv4.addresses = [{
    address = "192.168.1.24";
    prefixLength = 24;
  }];
  networking.defaultGateway = "192.168.1.1";

  environment.systemPackages = with pkgs; [
    compose2nix
    net-tools
    git
    tmux
    netbird
  ];

  services.netbird.clients.Netbird.ui.enable = false;

}
