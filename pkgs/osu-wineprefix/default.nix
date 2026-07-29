{
  lib,
  stdenvNoCC,
  fetchurl,
  versions,
}:

stdenvNoCC.mkDerivation {
  pname = "osu-wineprefix";
  version = "winello-bins";

  src = fetchurl {
    inherit (versions.wineprefix) url hash;
  };

  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    # After unpack, sourceRoot is osu-prefix/; expose as $out for seeding.
    mkdir -p "$out"
    cp -a . "$out/"
    runHook postInstall
  '';

  meta = {
    description = "Prebuilt osu! wineprefix seed from osu-winello";
    homepage = "https://github.com/NelloKudo/osu-winello";
    license = lib.licenses.unfreeRedistributable;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
