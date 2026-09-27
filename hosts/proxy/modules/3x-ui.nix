{ config, pkgs, ... }:

{
  virtualisation.oci-containers.backend = "podman";
  virtualisation.oci-containers.containers."3x-ui" = {
    image = "ghcr.io/mhsanaei/3x-ui:latest";
    autoStart = true;
    ports = [
      "9443:9443"
      "2053:2053"
    ];
    environment = {
      XUI_PORT = "2053";
    };
    volumes = [
      "/var/lib/3x-ui/db:/etc/x-ui"
    ];
    extraOptions = [ "--cap-add=NET_ADMIN" ];
  };
}
