{ config, lib, pkgs, ... }:

let
  domain = "toastymop.me";

  origin     = "10.0.0.2";
  originPort = 8080;

  privateHost = "ssh.${domain}";

  cfProxies = [
    "173.245.48.0/20" "103.21.244.0/22" "103.22.200.0/22" "103.31.4.0/22"
    "141.101.64.0/18" "108.162.192.0/18" "190.93.240.0/20" "188.114.96.0/20"
    "197.234.240.0/22" "198.41.128.0/17" "162.158.0.0/15" "104.16.0.0/13"
    "104.24.0.0/14" "172.64.0.0/13" "131.0.72.0/22"
    "2400:cb00::/32" "2606:4700::/32" "2803:f800::/32" "2405:b500::/32"
    "2405:8100::/32" "2a06:98c0::/29" "2c0f:f248::/32"
  ];

  caddyWithPlugins = pkgs.caddy.withPlugins {
    plugins = [
      "github.com/caddy-dns/cloudflare@v0.2.4"
      "github.com/mholt/caddy-l4@v0.1.2"
    ];
    hash = "sha256-6HJkIfqacmsEaubClOVjzPM+7Jy5Z7xHVORzf6+5OxU=";
  };

  caddyfile = ''
    {
      email admin@${domain}
      acme_dns cloudflare {env.CF_API_TOKEN}

      servers {
        # HTTP/3 (QUIC/UDP) is deliberately OFF: this network drops QUIC mid-handshake,
        # so browsers stalled on the first attempt and only succeeded after falling
        # back to TCP. Serve h1/h2 only.
        protocols h1 h2
        trusted_proxies static ${lib.concatStringsSep " " cfProxies}
        trusted_proxies_strict
        client_ip_headers CF-Connecting-IP X-Forwarded-For
        timeouts {
          read_body 120s
        }
      }
    }

    *.${domain}, ${domain} {
      @private host ${privateHost}
      handle @private {
        abort
      }

      handle {
        reverse_proxy http://${origin}:${toString originPort} {
          header_up X-Forwarded-For {client_ip}
          header_up X-Real-IP {client_ip}
        }
      }
    }

    mediaflow.${domain} {
      reverse_proxy http://127.0.0.1:8888
    }
  '';
in
{
  sops.secrets."CF_API_TOKEN" = {
    sopsFile = ../../../secrets/caddy.yaml;
  };

  sops.templates."caddy-env" = {
    content = "CF_API_TOKEN=${config.sops.placeholder."CF_API_TOKEN"}";
  };

  services.caddy = {
    enable = true;
    package = caddyWithPlugins;
    configFile = pkgs.writeText "Caddyfile" caddyfile;
    environmentFile = config.sops.templates."caddy-env".path;
  };

  # The edge owns 80/443 (TCP). HTTP/3 is disabled, so no UDP/443 listener.
  networking.firewall.allowedTCPPorts = [ 80 443 ];

  # Caddy graceful reload waits for in-flight requests to drain, which can exceed
  # the systemd default 90s reload timeout while media streams are active. systemd
  # then reports a false Failed-to-reload and races whether the new config applied.
  systemd.services.caddy.serviceConfig.TimeoutSec = "5min";
}
