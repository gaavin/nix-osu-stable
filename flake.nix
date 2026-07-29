{
  description = "Declarative osu!stable on Nix using osu-winello's wine-osu + yawl stack";

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
        osu-wine = pkgs.callPackage ./pkgs/osu-wine {
          inherit
            versions
            wine-osu
            yawl
            osu-wineprefix
            osu-mime
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

      overlays.default = final: _prev: {
        inherit (self.packages.${final.stdenv.hostPlatform.system} or packages)
          wine-osu
          yawl
          osu-wineprefix
          osu-mime
          osu-wine
          ;
      };
    };
}
