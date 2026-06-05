{ config, lib, pkgs, ... }:

let
  secretsPath = builtins.toString ../..;
in
{
  config = {
    sops.defaultSopsFile = "${secretsPath}/secrets/authentik.yaml";
    sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    sops.templates."authentik-env" = {
      content = ''
        AUTHENTIK_SECRET_KEY=${config.sops.placeholder."AUTHENTIK_SECRET_KEY"}
        AUTHENTIK_POSTGRESQL__PASSWORD=${config.sops.placeholder."AUTHENTIK_POSTGRESQL__PASSWORD"}
        AUTHENTIK_EMAIL__PASSWORD=${config.sops.placeholder."AUTHENTIK_EMAIL__PASSWORD"}
      '';
      owner = "authentik";
      group = "authentik";
    };

    sops.templates."authentik-postgres-password" = {
      content = config.sops.placeholder."AUTHENTIK_POSTGRESQL__PASSWORD";
      owner = "postgres";
      group = "postgres";
    };

    services.authentik = {
      enable = true;
      environmentFile = config.sops.templates."authentik-env".path;

      settings = {
        postgresql = {
          host = "/run/postgresql";
          name = "authentik";
          user = "authentik";
        };
        email = {
          host = "smtp.resend.com";
          port = 587;
          username = "resend";
          use_tls = true;
          use_ssl = false;
          timeout = 30;
          from = "auth@toastymop.me";
        };
        error_reporting.enabled = true;
        disable_startup_analytics = true;
      };
    };

    services.postgresql = {
      enable = true;
      ensureDatabases = [ "authentik" ];
      ensureUsers = [
        { name = "authentik";
          ensurePermissions = { "DATABASE authentik" = "ALL PRIVILEGES"; };
          passwordFile = config.sops.templates."authentik-postgres-password".path;
        }
      ];
    };
  };
}
