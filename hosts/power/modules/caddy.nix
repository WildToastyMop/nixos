{ config, lib, pkgs, ... }:

let
  # The VPS edge's WireGuard IP — trusted so {client_ip} is the real visitor.
  edge = "10.0.0.1";

  # Caddy with the Cloudflare DNS-01 provider (the ssh.<domain> site still
  # issues its own cert). Same plugin set as the edge, so the same hash.
  # (Bump the @versions + re-derive the hash if you change the plugin set.)
  caddyWithPlugins = pkgs.caddy.withPlugins {
    plugins = [
      "github.com/caddy-dns/cloudflare@v0.2.4"
      "github.com/mholt/caddy-l4@v0.1.2"
    ];
    hash = "sha256-6HJkIfqacmsEaubClOVjzPM+7Jy5Z7xHVORzf6+5OxU=";
  };

  caddyfile = ''
    {
      # The VPS edge owns :443 and terminates TLS; serve plain HTTP on 8080
      # for the edge to reverse_proxy to (over the WireGuard tunnel).
      http_port 8080
      auto_https disable_redirects

      # Still required: ssh.<domain> keeps its own certificate (Tailscale-only).
      acme_dns cloudflare {env.CF_API_TOKEN}

      servers {
        trusted_proxies static ${edge}
        timeouts {
          read_body 120s
        }
      }
    }

    # Preserve the real client IP and https scheme (the edge already ended
    # TLS; Caddy would otherwise rewrite X-Forwarded-Proto to http and
    # replace X-Forwarded-For with the edge IP).
    (edge) {
      reverse_proxy {args[0]} {
        header_up X-Forwarded-For {client_ip}
        header_up X-Real-IP {client_ip}
        header_up X-Forwarded-Proto https
      }
    }

    (authentik_forwardauth) {
      reverse_proxy /outpost.goauthentik.io/* https://172.20.0.17:9000
      forward_auth http://172.20.0.17:9000 {
        uri /outpost.goauthentik.io/auth/caddy
        copy_headers X-Authentik-Username X-Authentik-Groups X-Authentik-Email X-Authentik-Name X-Authentik-Uid X-Authentik-Jwt X-Authentik-Meta-Jwks X-Authentik-Meta-Outpost X-Authentik-Meta-Provider X-Authentik-Meta-App X-Authentik-Meta-Version
        trusted_proxies private_ranges
      }
    }

    (noindex) {
      header {
        X-Robots-Tag "noindex"
      }
    }

    http://toastymop.me {
      import noindex
      handle /_matrix/* {
        import edge 172.20.0.27:6167
      }
      handle /.well-known/* {
        root * /srv
        try_files {path} {path}.txt
        file_server
      }
    }

    http://auth.toastymop.me {
      import noindex
      import edge 172.20.0.17:9000
    }
    http://mail.toastymop.me {
      import noindex
      import edge 127.0.0.1:8889
    }
    http://git.toastymop.me {
      import noindex
      import edge 172.20.0.68:3000
    }
    http://jelly.toastymop.me {
      import noindex
      import edge 127.0.0.1:8096
    }
    http://photos.toastymop.me {
      import noindex
      import edge 172.20.0.13:2283
    }
    http://search.toastymop.me {
      import noindex
      import edge 127.0.0.1:8089
    }
    http://home.toastymop.me {
      import noindex
      import edge 127.0.0.1:8123
    }
    http://pace.toastymop.me {
      import noindex
      import edge 127.0.0.1:7000
    }
    http://punch.toastymop.me {
      import noindex
      import edge 127.0.0.1:6900
    }
    http://hub.toastymop.me {
      import noindex
      import edge 172.20.0.9:8080
    }
    http://link.toastymop.me {
      import noindex
      import edge 172.20.0.21:3000
    }
    http://paperless.toastymop.me {
      import noindex
      import edge 172.20.0.28:8000
    }
    http://music.toastymop.me {
      import noindex
      import edge 127.0.0.1:4533
    }
    http://foundry.toastymop.me {
      import noindex
      import edge 127.0.0.1:30000
    }
    http://cloud.toastymop.me {
      import noindex
      import edge 172.20.0.87:80
    }
    http://office.toastymop.me {
      import noindex
      import edge 172.20.0.88:9980
    }
    http://aioman.toastymop.me {
      import noindex
      import edge 127.0.0.1:1610
    }
    http://panel.toastymop.me {
      import noindex
      import edge 127.0.0.1:8002
    }

    # Tailscale-only site — bound to the Tailscale IP, still terminates its
    # own TLS. Never reached through the edge.
    ssh.toastymop.me {
      bind 100.81.30.230
      reverse_proxy 127.0.0.1:8789
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

  # Origin only needs :8080 (for the edge, on wg) and :443 (Tailscale) — no
  # public ports. Firewall is left to the host; see hosts/power/default.nix.
}
