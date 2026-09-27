{ config, ... }:

let
  # mediaflow-proxy listens on 8888 inside the container; publish on loopback
  # only. The edge Caddy (modules/caddy.nix) terminates TLS for
  # https://mediaflow.<domain> and proxies to this port, so the raw port is
  # never exposed to the internet.
  port = 8888;
in
{
  # ---- API password (managed by sops, never in this file) -------------
  sops.secrets."MEDIAFLOW_API_PASSWORD" = {
    sopsFile = ../../../secrets/mediaflow.yaml;
  };

  sops.templates."mediaflow-env" = {
    content = "API_PASSWORD=${config.sops.placeholder."MEDIAFLOW_API_PASSWORD"}";
  };

  virtualisation.oci-containers.containers.mediaflow = {
    image = "docker.io/mhdzumair/mediaflow-proxy:v2.4.9";
    autoStart = true;

    # 127.0.0.1 only — the public entry point is the edge Caddy, not this port.
    ports = [ "127.0.0.1:${toString port}:8888" ];

    environment = {
      # This host is on the public internet, so drop the unauthenticated
      # landing/docs pages and keep the API password-only.
      DISABLE_HOME_PAGE = "true";
      DISABLE_DOCS = "true";
    };

    environmentFiles = [ config.sops.templates."mediaflow-env".path ];
  };
}
