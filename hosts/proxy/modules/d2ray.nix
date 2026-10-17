{ pkgs, ... }:

{
  virtualisation = {
    containers.enable = true;
    podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };
    oci-containers.backend = "podman";
    oci-containers.containers.d2ray = {
      image = "quackerd/d2ray:latest";
      autoStart = true;

      ports = [ "7443:8443" ];

      volumes = [ "/var/lib/d2ray:/etc/d2ray" ];

      environment = {
        HOST = "play.toastymop.me";
        TARGET_HOST = "addons.mozilla.org";
        USERS = "toasty,user2";

        # PORT is the EXTERNAL port. It must match the left side of the ports mapping above
        # so the generated client links point to the correct port.
        PORT = "7443";

        # Optional settings:
        # TARGET_PORT = "443";              # Optional, default is 443
        # PRIVATE_KEY = "...";              # Optional: provide a fixed key
        # BLOCK_CN = "true";                # Optional, default true
        # BLOCK_ADS = "true";               # Optional, default true
        # BLOCK_LOCAL = "true";             # Optional, default true
        # LOG_LEVEL = "warning";            # Optional, default warning
      };
    };
  };

  networking.firewall.allowedTCPPorts = [ 7443 ];

  systemd.tmpfiles.rules = [
    "d /var/lib/d2ray 0755 root root -"
  ];
}
