{ config, pkgs, lib, ... }:

let
  serverPublicIP = "45.41.205.95";
  externalInterface = "ens3";
  vpnInterface = "wg0";
  vpnNetwork = "10.0.0.1/24";
  listenPort = 55108;
  mtu = 1380;
  privateKeyFile = "/var/lib/wireguard/private.key";
  portsFile = "/var/lib/wireguard/ports.txt";

  peers = [
    {
      publicKey = "bEMWjZEBHuKIqmPJtukOGAFGIUaCxD4SoM2AcRSc+xA=";
      allowedIPs = [ "10.0.0.2/32" ];
      endpoint = null;
      persistentKeepalive = 25;
    }
  ];
  nft = "${pkgs.nftables}/bin/nft";
  bash = "${pkgs.bash}/bin/bash";
in {
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv4.conf.all.forwarding" = 1;
  };

  networking.wireguard.interfaces.${vpnInterface} = {
    ips = [ vpnNetwork ];
    privateKeyFile = privateKeyFile;
    generatePrivateKeyFile = true;
    listenPort = listenPort;
    peers = peers;
    mtu = mtu;
  };

  systemd.tmpfiles.rules = [
    "d ${builtins.dirOf portsFile} 0755 root root -"
  ];

  environment.etc."wireguard-update-ports.sh" = {
    mode = "0755";
    text = ''
      #!${bash}
      set -euo

      PORTS_FILE="${portsFile}"
      PUBLIC_IP="${serverPublicIP}"
      EXT_IF="${externalInterface}"
      NFT="${nft}"

      $NFT list table ip wg_forward >/dev/null 2>&1 && $NFT flush table ip wg_forward
      $NFT list table ip wg_forward || $NFT add table ip wg_forward

      $NFT add chain ip wg_forward FORWARD { type filter hook forward priority 0\; policy accept\; }
      $NFT add chain ip wg_forward PREROUTING { type nat hook prerouting priority -100\; }
      $NFT add chain ip wg_forward POSTROUTING { type nat hook postrouting priority 100\; }

      $NFT add rule ip wg_forward POSTROUTING oifname "$EXT_IF" ip saddr 10.0.0.0/8 counter snat to $PUBLIC_IP

      if [[ ! -f "$PORTS_FILE" ]]; then
        echo "Warning: $PORTS_FILE not found" >&2
        exit 0
      fi

      while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        read -ra tokens <<< "$line"
        [[ ''${#tokens[@]} -lt 2 ]] && continue
        peer_ip="''${tokens[0]}"
        for spec in "''${tokens[@]:1}"; do
          if [[ "$spec" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            start=''${BASH_REMATCH[1]}
            end=''${BASH_REMATCH[2]}
            for ((port=start; port<=end; port++)); do
              $NFT add rule ip wg_forward PREROUTING ip daddr $PUBLIC_IP tcp dport $port counter dnat to $peer_ip:$port
              $NFT add rule ip wg_forward PREROUTING ip daddr $PUBLIC_IP udp dport $port counter dnat to $peer_ip:$port
              $NFT add rule ip wg_forward FORWARD ip daddr $peer_ip tcp dport $port ct state new,established,related accept
              $NFT add rule ip wg_forward FORWARD ip saddr $peer_ip tcp sport $port ct state established,related accept
              $NFT add rule ip wg_forward FORWARD ip daddr $peer_ip udp dport $port ct state new,established,related accept
              $NFT add rule ip wg_forward FORWARD ip saddr $peer_ip udp sport $port ct state established,related accept
            done
          else
            port=$spec
            $NFT add rule ip wg_forward PREROUTING ip daddr $PUBLIC_IP tcp dport $port counter dnat to $peer_ip:$port
            $NFT add rule ip wg_forward PREROUTING ip daddr $PUBLIC_IP udp dport $port counter dnat to $peer_ip:$port
            $NFT add rule ip wg_forward FORWARD ip daddr $peer_ip tcp dport $port ct state new,established,related accept
            $NFT add rule ip wg_forward FORWARD ip saddr $peer_ip tcp sport $port ct state established,related accept
            $NFT add rule ip wg_forward FORWARD ip daddr $peer_ip udp dport $port ct state new,established,related accept
            $NFT add rule ip wg_forward FORWARD ip saddr $peer_ip udp sport $port ct state established,related accept
          fi
        done
      done < "$PORTS_FILE"
    '';
  };

  systemd.services.wireguard-port-forward = {
    description = "Apply dynamic port forwarding rules";
    after = [ "network.target" "wg-quick-${vpnInterface}.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${bash} /etc/wireguard-update-ports.sh";
    };
  };

  systemd.paths.wireguard-port-forward = {
    description = "Watch ports.txt for changes";
    wantedBy = [ "multi-user.target" ];
    pathConfig = {
      PathChanged = portsFile;
      Unit = "wireguard-port-forward.service";
    };
  };
}
