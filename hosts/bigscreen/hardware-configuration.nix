# Hardware config for the TV box: Mac mini (Late 2012) = Macmini6,1.
#
# This is a TEMPLATE. The fileSystems UUIDs below are placeholders — generate
# the real ones on the machine itself and paste them in:
#
#   nixos-generate-config --show-hardware-config > hosts/bigscreen/hardware-configuration.nix
#   # keep the fileSystems.* / swapDevices / kernel-module blocks from that
#   # output — they are the only machine-specific parts
#
# This host is bare metal (Macmini6,1); power/proxy/desktop are QEMU guests.
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  # USB 3.0 (xhci) + USB 2.0 (ehci) + the SATA controller. usbhid is here so
  # the HID keyboard dongle (TTVKTR / Flirc) works even in early boot.
  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ehci_pci"
    "ahci"
    "usb_storage"
    "usbhid"
    "sd_mod"
    "sdhci_pci"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  # !! REPLACE the device UUIDs. Get them with:
  #   ls -l /dev/disk/by-uuid/
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/00000000-0000-0000-0000-000000000000";
    fsType = "ext4";
  };

  # The EFI system partition, mounted at /boot for boot.loader.grub.
  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/0000-0000";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
