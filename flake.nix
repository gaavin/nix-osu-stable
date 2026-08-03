{
  description = "Declarative osu!stable on Nix (wine-osu + yawl stack, inspired by osu-winello)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
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
        default = osu-wine;
      };
    in
    {
      packages.${system} = packages;

      apps.${system}.default = {
        type = "app";
        program = "${packages.osu-wine}/bin/osu-wine";
      };

      homeModules.osu-stable = ./modules/home-manager/osu-stable.nix;
      homeModules.default = self.homeModules.osu-stable;

      overlays.default = final: _prev: {
        inherit (self.packages.${final.stdenv.hostPlatform.system} or packages)
          wine-osu
          yawl
          osu-wineprefix
          osu-mime
          rpc-bridge
          osu-wine
          ;
      };
    };
}
