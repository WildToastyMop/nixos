{ config, pkgs, ... }:

{
  networking.hostName = "proxy"; 
  imports = [
    ./modules/portProxy.nix
    ../../modules/net/netbird.nix
  ];
  
  networking.firewall.allowedTCPPorts = [ 55108 ];
  networking.firewall.allowedUDPPorts = [ 55108 ];

  networking.firewall.trustedInterfaces = [ "wg0" ];
 
  environment.systemPackages = with pkgs; [
    nftables
    net-tools
    git
    tmux
  ];

}
