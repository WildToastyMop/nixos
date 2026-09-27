{ config, lib, pkgs, ... }:

let
  # ---- edge settings -------------------------------------------------
  # Wildcard zone served by this edge. Add more zones as needed.
  domain = "toastymop.me";

  # Where the real sites live, reached over the WireGuard tunnel. The
  # origin (home) Caddy must serve these hosts as PLAIN HTTP on this port
  # (set `http_port 8080` there) — TLS is terminated here on the VPS.
  origin     = "10.0.0.2";
  originPort = 8080;

  # Host that must NOT be reachable through the public edge (Tailscale-only).
  privateHost = "ssh.${domain}";

  # Cloudflare edge ranges (https://www.cloudflare.com/ips-v4 + /ips-v6),
  # so real client IPs are recovered for CF-proxied sites.
  cfProxies = [
    "173.245.48.0/20" "103.21.244.0/22" "103.22.200.0/22" "103.31.4.0/22"
    "141.101.64.0/18" "108.162.192.0/18" "190.93.240.0/20" "188.114.96.0/20"
    "197.234.240.0/22" "198.41.128.0/17" "162.158.0.0/15" "104.16.0.0/13"
    "104.24.0.0/14" "172.64.0.0/13" "131.0.72.0/22"
    "2400:cb00::/32" "2606:4700::/32" "2803:f800::/32" "2405:b500::/32"
    "2405:8100::/32" "2a06:98c0::/29" "2c0f:f248::/32"
  ];

  # Caddy with the Cloudflare DNS-01 provider (needed for wildcard certs)
  # plus the L4 app (raw TCP/UDP proxying, kept available for future use).
  # To change the plugin set: bump the @versions, set hash = lib.fakeHash,
  # build once, and paste the sha256 that Nix prints.
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
      # ---- hide block: keep the Tailscale-only host off the public edge ----
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

    # mediaflow-proxy runs on THIS host, so serve it locally rather than
    # forwarding the name to the origin. An exact host beats the wildcard.
    mediaflow.${domain} {
      reverse_proxy http://127.0.0.1:8888
    }
  '';
in
{
  # ---- Cloudflare API token for DNS-01 (managed by sops) -------------
  sops.secrets."CF_API_TOKEN" = {
    sopsFile = ../../../secrets/caddy.yaml;
  };

  sops.templates."caddy-env" = {
    content = "CF_API_TOKEN=${config.sops.placeholder."CF_API_TOKEN"}";
  };

  # ---- the edge Caddy ------------------------------------------------
  services.caddy = {
    enable = true;
    package = caddyWithPlugins;
    configFile = pkgs.writeText "Caddyfile" caddyfile;
    environmentFile = config.sops.templates."caddy-env".path;
  };

  # The edge owns 80/443 (TCP) and 443/UDP for HTTP/3.
  networking.firewall.allowedTCPPorts = [ 80 443 ];
  networking.firewall.allowedUDPPorts = [ 443 ];
}
