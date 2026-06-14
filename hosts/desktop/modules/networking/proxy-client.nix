{ config, pkgs, lib, ... }:

let
  # ========== EDIT THESE VARIABLES ==========
  virtualIP = "10.0.0.4";
  serverPublicKey = "MhnQmQjyjz5OVGUl7zlXbeS8OxYq+jXmN07Nh8dexw8=";
  serverEndpoint = "45.41.205.95:55108";
  privateKeyFile = "/var/lib/wireguard/private.key";
  vpnInterface = "wg0";
  routingTable = "1";
  listenPort = 55108;
  persistentKeepalive = 25;
  # ==========================================
in {
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv4.conf.all.forwarding" = 1;
  };

  networking.firewall.trustedInterfaces = [ vpnInterface ];

  networking.wireguard.interfaces.${vpnInterface} = {
    ips = [ "${virtualIP}/32" ];
    privateKeyFile = privateKeyFile;
    generatePrivateKeyFile = true;
    listenPort = listenPort;
    table = routingTable;

    postSetup = ''
      ${pkgs.iproute2}/bin/ip rule add from ${virtualIP} lookup ${toString routingTable} pref 500
    '';
    preShutdown = ''
      ${pkgs.iproute2}/bin/ip rule del from ${virtualIP} lookup ${toString routingTable} pref 500
    '';

    peers = [
      {
        publicKey = serverPublicKey;
        endpoint = serverEndpoint;
        allowedIPs = [ "0.0.0.0/0" ];
        persistentKeepalive = persistentKeepalive;
      }
    ];
  };
}
