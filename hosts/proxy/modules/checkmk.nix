{ ... }:

{
  fileSystems."/var/lib/checkmk/tmp" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [ "uid=1000" "gid=1000" "mode=0755" "size=1G" ];
  };

  systemd.services.podman-checkmk = {
    requires = [ "var-lib-checkmk-tmp.mount" ];
    after = [ "var-lib-checkmk-tmp.mount" ];
  };

  virtualisation.oci-containers.backend = "podman";

  virtualisation.oci-containers.containers.checkmk = {
    image = "docker.io/checkmk/check-mk-community:2.5.0p15";
    autoStart = true;

    ports = [
      "127.0.0.1:8080:5000"
      "8000:8000"
    ];

    volumes = [
      "checkmk:/omd/sites"
      "/var/lib/checkmk/tmp:/opt/omd/sites/cmk/tmp"
    ];
  };
}
