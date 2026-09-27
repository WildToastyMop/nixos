{ pkgs, ... }:

{
  imports = [
    ./modules/apps/fladder.nix
    ./modules/apps/vacuumtube.nix
    ./modules/graphics/intel-vaapi.nix

  ];

  boot.loader.grub = {
    enable = true;
    device = "nodev";
    efiSupport = true;
    efiInstallAsRemovable = true;
    configurationLimit = 5;
  };
  boot.loader.efi.canTouchEfiVariables = false;

  hardware.enableAllFirmware = true;

  swapDevices = [ { device = "/swapfile"; size = 8192; } ];

  services.xserver.enable = true;
  services.desktopManager.plasma6.enable = true;

  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;

  services.displayManager.sessionPackages = [ pkgs.kdePackages.plasma-bigscreen ];
  services.displayManager.defaultSession = "plasma-bigscreen-wayland";

  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "toasty";

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  programs.kdeconnect.enable = true;

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;


  environment.systemPackages = with pkgs; [
    kdePackages.plasma-bigscreen

    moonlight-qt

    firefox
    vlc
    git
    tmux
    net-tools

    libva-utils
    mesa-demos
    intel-gpu-tools
    pciutils
    usbutils
  ];

}
