{ pkgs, ... }:

{
  # Enable Podman with Docker compatibility
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

      # External port 443 -> container's fixed internal port 8443
      ports = [ "7443:8443" ];

      # Persistent storage for keys and logs
      volumes = [ "/var/lib/d2ray:/etc/d2ray" ];

      environment = {
        HOST = "play.toastymop.me";          # REQUIRED: Your server's hostname/IP
        TARGET_HOST = "addons.mozilla.org";  # REQUIRED: SNI disguise target
        USERS = "toasty,user2";              # REQUIRED: Comma-separated usernames

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

  # Open firewall port (must match the external PORT you chose)
  networking.firewall.allowedTCPPorts = [ 7443 ];

  # Ensure the volume directory exists
  systemd.tmpfiles.rules = [
    "d /var/lib/d2ray 0755 root root -"
  ];
}
