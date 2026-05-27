{
  description = "Baby's first multihost";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }: let
    inherit (nixpkgs) lib;
    hostNames = [ "power" "proxy" ];
    commonModules = [
      ./common.nix
      ./hardware-configuration.nix
    ];
  in {
    nixosConfigurations = lib.pipe hostNames [
      (map (hostName: lib.nameValuePair hostName (lib.nixosSystem {
        system = "x86_64-linux";
        modules = commonModules ++ [
          { networking.hostName = hostName; }
          (./hosts + "/${hostName}/default.nix")
        ];
      })))
      lib.listToAttrs
    ];
  };
}