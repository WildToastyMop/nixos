{
  description = "Baby's first multihost";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }: {
    nixosConfigurations = {

      power = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./common.nix
	  ./hardware-configuration.nix
          ./hosts/power/default.nix
        ];
      };

      proxy = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./common.nix
          ./hardware-configuration.nix
	  ./hosts/proxy/default.nix
        ];
      };

    };
  };
}
