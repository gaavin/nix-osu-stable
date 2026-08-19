{
  description = "Declarative osu!stable on Nix (wine-osu + yawl stack, inspired by osu-winello)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    offset-calc-osu-stable = {
      url = "github:gaavin/offset-calc-osu-stable";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      offset-calc-osu-stable,
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      versions = import ./versions.nix;

      packages = rec {
        wine-osu = pkgs.callPackage ./pkgs/wine-osu { inherit versions; };
        yawl = pkgs.callPackage ./pkgs/yawl { inherit versions; };
        osu-wineprefix = pkgs.callPackage ./pkgs/osu-wineprefix { inherit versions; };
        osu-mime = pkgs.callPackage ./pkgs/osu-mime { inherit versions; };
        rpc-bridge = pkgs.callPackage ./pkgs/rpc-bridge { inherit versions; };
        osu-wine = pkgs.callPackage ./pkgs/osu-wine {
          inherit
            versions
            wine-osu
            yawl
            osu-wineprefix
            osu-mime
            rpc-bridge
            ;
        };
        osu-offset = offset-calc-osu-stable.packages.${system}.default;
        default = osu-wine;
      };
    in
    {
      packages.${system} = packages;

      apps.${system} = {
        default = {
          type = "app";
          program = "${packages.osu-wine}/bin/osu-wine";
        };
        osu-offset = {
          type = "app";
          program = "${packages.osu-offset}/bin/osu-offset";
        };
      };

      homeModules.osu-stable =
        { lib, pkgs, ... }:
        {
          imports = [ ./modules/home-manager/osu-stable.nix ];
          # Default to this flake's osu-wine; users can still override.
          programs.osu-stable.package = lib.mkDefault (
            self.packages.${pkgs.stdenv.hostPlatform.system}.osu-wine
          );
          programs.osu-stable.offsetCalculator.package = lib.mkDefault (
            self.packages.${pkgs.stdenv.hostPlatform.system}.osu-offset
          );
        };
      homeModules.default = self.homeModules.osu-stable;

      overlays.default = final: _prev: {
        inherit (self.packages.${final.stdenv.hostPlatform.system} or packages)
          wine-osu
          yawl
          osu-wineprefix
          osu-mime
          rpc-bridge
          osu-wine
          osu-offset
          ;
      };
    };
}
