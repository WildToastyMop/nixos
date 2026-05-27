{ config, lib, ... }:

{
  nixpkgs.config.allowUnfree = true;

  boot.kernelModules = [ "nvidia" "nvidia_uvm" ];
  boot.extraModulePackages = [ config.boot.kernelPackages.nvidia_x11 ];

  hardware.nvidia.nvidiaPersistenced = true;
  hardware.nvidia.modesetting.enable = true;
}
