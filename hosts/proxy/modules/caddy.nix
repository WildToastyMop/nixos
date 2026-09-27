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

  networking.firewall.allowedTCPPorts = [ 80 443 ];
  networking.firewall.allowedUDPPorts = [ 443 ];
}
