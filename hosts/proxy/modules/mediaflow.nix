{ config, ... }:

let
  port = 8888;
in
{
  sops.secrets."MEDIAFLOW_API_PASSWORD" = {
    sopsFile = ../../../secrets/mediaflow.yaml;
  };

  sops.templates."mediaflow-env" = {
    content = "API_PASSWORD=${config.sops.placeholder."MEDIAFLOW_API_PASSWORD"}";
  };

  virtualisation.oci-containers.containers.mediaflow = {
    image = "docker.io/mhdzumair/mediaflow-proxy:v2.4.9";
    autoStart = true;

    ports = [ "127.0.0.1:${toString port}:8888" ];

    environment = {
      DISABLE_HOME_PAGE = "true";
      DISABLE_DOCS = "true";
    };

    environmentFiles = [ config.sops.templates."mediaflow-env".path ];
  };
}
