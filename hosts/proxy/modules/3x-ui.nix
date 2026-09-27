{ config, pkgs, ... }:

{
  virtualisation.oci-containers.backend = "podman";
  virtualisation.oci-containers.containers."3x-ui" = {
    image = "ghcr.io/mhsanaei/3x-ui:latest";
    autoStart = true;
    ports = [
      "9443:9443"   # Xray Reality port
      "2053:2053"  # Web panel admin port
    ];
    # NOTE: panel credentials are intentionally NOT hardcoded here.
    # Set them on first login in the web panel, or inject via a
    # sops-managed env file (--env-file).
    environment = {
      XUI_PORT = "2053";
    };
    volumes = [
      "/var/lib/3x-ui/db:/etc/x-ui"
      #"/var/lib/3x-ui/cert:/root/cert"
    ];
    extraOptions = [ "--cap-add=NET_ADMIN" ];
  };
}
