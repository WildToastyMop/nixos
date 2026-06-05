{
  description = "Baby's first multihost";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    sops-nix.url = "github:Mic92/sops-nix";
  };

  outputs = { self, nixpkgs, sops-nix,  ... }: let
    inherit (nixpkgs) lib;
    hostNames = [ "power" "proxy" ];
    commonModules = [
      ./common.nix
      ./hardware-configuration.nix
      sops-nix.nixosModules.sops
    ];
  in {
    nixosConfigurations = lib.pipe hostNames [
      (map (hostName: lib.nameValuePair hostName (lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit sops-nix; };
        modules = commonModules ++ [
          { networking.hostName = hostName; }
          (./hosts + "/${hostName}/default.nix")
        ];
      })))
      lib.listToAttrs
    ];
  };
}
