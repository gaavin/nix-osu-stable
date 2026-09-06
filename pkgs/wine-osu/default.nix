{
  lib,
  stdenvNoCC,
  fetchurl,
  versions,
}:

stdenvNoCC.mkDerivation {
  pname = "wine-osu";
  inherit (versions.wineOsu) version;

  src = fetchurl {
    inherit (versions.wineOsu) url hash;
  };

  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    # After unpack, sourceRoot is wine-osu/; copy into $out so $out/bin/wine exists.
    cp -a . "$out/"
    runHook postInstall
  '';

  meta = {
    description = "Patched wine-osu (WineBuilder winello-v11.12-3) for osu!stable";
    homepage = "https://github.com/gaavin/nix-osu-stable";
    license = lib.licenses.lgpl21Plus;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
