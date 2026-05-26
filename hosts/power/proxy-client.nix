# proxy-client.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.services.proxy-client;
  inherit (lib) mkEnableOption mkOption types;
in {
  options.services.proxy-client = {
    enable = mkEnableOption "WireGuard split‑tunnel client";
    virtualIP = mkOption { type = types.str; };
    serverPublicKey = mkOption { type = types.str; };
    serverEndpoint = mkOption { type = types.str; };
    privateKeyFile = mkOption {
      type = types.str;
      default = "/etc/wireguard/private.key";
    };
    vpnInterface = mkOption {
      type = types.str;
      default = "wg0";
    };
    routingTable = mkOption {
      type = types.int;
      default = 1;
    };
  };

  config = lib.mkIf cfg.enable {
    networking.wireguard.interfaces.${cfg.vpnInterface} = {
      ips = [ "${cfg.virtualIP}/32" ];
      privateKeyFile = cfg.privateKeyFile;
      generatePrivateKeyFile = true;
      table = cfg.routingTable;
      postUp = ''
        ${pkgs.iproute2}/bin/ip rule add from ${cfg.virtualIP} lookup ${toString cfg.routingTable} pref 500
      '';
      preDown = ''
        ${pkgs.iproute2}/bin/ip rule del from ${cfg.virtualIP} lookup ${toString cfg.routingTable} pref 500
      '';
      peers = [
        {
          publicKey = cfg.serverPublicKey;
          endpoint = cfg.serverEndpoint;
          allowedIPs = [ "0.0.0.0/0" ];
          persistentKeepalive = 25;
        }
      ];
    };
  };
}
