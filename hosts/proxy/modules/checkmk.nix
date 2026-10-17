{ ... }:

{
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
    ];
  };
}
