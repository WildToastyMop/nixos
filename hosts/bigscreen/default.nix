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

  boot.kernelParams = [ "video=DP-1:1920x1080@60" ];

  hardware.enableAllFirmware = true;

  swapDevices = [ { device = "/swapfile"; size = 8192; } ];

  zramSwap.enable = true;

  environment.etc."xdg/kwinrulesrc".text = ''
    [General]
    count=1
    rules=4f6d1c2e-9a3b-4c7d-8e1f-2b3c4d5e6f70

    [4f6d1c2e-9a3b-4c7d-8e1f-2b3c4d5e6f70]
    Description=Fladder fullscreen
    wmclass=nl.jknaapen.fladder
    wmclassmatch=1
    wmclasscomplete=false
    fullscreen=true
    fullscreenrule=1
  '';

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
