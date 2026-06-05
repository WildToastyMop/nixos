{ config, lib, pkgs, ... }:

{

  services.immich = {
    enable = true;
    mediaLocation = "/srv/Immich";
    host = "127.0.0.1";
    port = 2283;

    environmentVariables = {
      TZ = "America/Chicago";
    };

    transcoding = {
      accel = "nvenc";
      accelDecode = true;
    };

    accelerationDevices = [
      "/dev/nvidia0"
      "/dev/nvidiactl"
      "/dev/nvidia-uvm"
    ];
  };

  users.users.immich.extraGroups = [ "video" "render" ];

}
