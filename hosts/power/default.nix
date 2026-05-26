{ config, pkgs, ... }:

{
  networking.hostName = "power"; 
  imports = [
    ./proxy-client.nix
    ../../modules/net/netbird.nix
  ];
 
  networking.interfaces.eth0.ipv4.addresses = [{
    address = "192.168.1.23";
    prefixLength = 24;
  }];
  networking.defaultGateway = "192.168.1.1";

  environment.shellAliases = {
    rebuild = "sudo nixos-rebuild switch --flake /etc/nixos#power";
  };

  environment.systemPackages = with pkgs; [
    compose2nix
    net-tools
    git
    git-credential-manager
    tmux
    netbird
  ];

}
