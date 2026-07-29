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
    description = "Patched wine-osu (WineBuilder) for osu!stable, as used by osu-winello";
    homepage = "https://github.com/NelloKudo/WineBuilder";
    license = lib.licenses.lgpl21Plus;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
