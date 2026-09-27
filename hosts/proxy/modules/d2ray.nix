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

        PORT = "7443";

      };
    };
  };

  networking.firewall.allowedTCPPorts = [ 7443 ];

  systemd.tmpfiles.rules = [
    "d /var/lib/d2ray 0755 root root -"
  ];
}
