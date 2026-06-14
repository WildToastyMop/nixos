{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    sops-nix.url = "github:Mic92/sops-nix";

    # Desktop‑only inputs
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    illogical-flake = {
      url = "github:soymou/illogical-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.dotfiles.follows = "dotfiles";
    };

    dotfiles = {
      url = "git+https://github.com/WildToastyMop/dots-hyprland?submodules=1";
      flake = false;
    };
    
    millennium.url = "github:SteamClientHomebrew/Millennium?dir=packages/nix";
  };

  outputs = { self, nixpkgs, sops-nix, home-manager, illogical-flake, dotfiles, millennium, ... }: let
    inherit (nixpkgs) lib;
    system = "x86_64-linux";
  in {
    nixosConfigurations = {
      # Existing hosts (no home-manager)
      power = lib.nixosSystem {
        inherit system;
        specialArgs = { inherit sops-nix; };
        modules = [
          ./common.nix
          ./hardware-configuration.nix
          sops-nix.nixosModules.sops
          { networking.hostName = "power"; }
          ./hosts/power/default.nix
        ];
      };

      proxy = lib.nixosSystem {
        inherit system;
        specialArgs = { inherit sops-nix; };
        modules = [
          ./common.nix
          ./hardware-configuration.nix
          sops-nix.nixosModules.sops
          { networking.hostName = "proxy"; }
          ./hosts/proxy/default.nix
        ];
      };

      # New desktop host with Hyprland + home-manager + illogical-flake
      desktop = lib.nixosSystem {
        inherit system;
        specialArgs = { inherit sops-nix home-manager illogical-flake dotfiles millennium; };
        modules = [
          ./common.nix
          ./hardware-configuration.nix   # replace with ./hardware-desktop.nix if different
          sops-nix.nixosModules.sops
          { networking.hostName = "desktop"; }
          ./hosts/desktop/default.nix    # system-level Hyprland, services, fonts

          # Home Manager as a NixOS module
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.toasty = { pkgs, ... }: {
              imports = [ illogical-flake.homeManagerModules.default ];
              programs.illogical-impulse = {
                enable = true;
                dotfiles = {
                  fish.enable = true;
                  kitty.enable = true;
                  starship.enable = true;
                };
              };
              home.stateVersion = "26.05";
            };
          }
        ];
      };
    };
  };
}
