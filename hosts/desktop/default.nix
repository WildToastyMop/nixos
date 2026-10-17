{ config, pkgs, millennium, ... }:

{
  networking.hostName = "desktop"; 

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  imports = [
    #./modules/networking/proxy-client.nix
    ../../modules/networking/netbird.nix
    ../../modules/driver/nvidia.nix
  ];
  
  nixpkgs.overlays = [ millennium.overlays.default ];

  programs.steam = {
    enable = true;
    package = pkgs.millennium-steam;
  };


  environment.systemPackages = with pkgs; [
    net-tools
    git
    tmux
    firefox
    millennium-steam

    rubik
    nerd-fonts.ubuntu
    nerd-fonts.jetbrains-mono
  ];

  programs.hyprland.enable = true;
  services.geoclue2.enable = true;
  #services.networkmanager.enable = true;

}
