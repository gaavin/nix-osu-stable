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
    # Overlay PE ntdll (BASS hook) and mmdevapi (2-period WASAPI). Unix ntdll.so
    # is left alone so ntsync in the winello unixlib stays intact.
    cp -f ${./overlay/i386-windows/ntdll.dll} "$out/lib/wine/i386-windows/ntdll.dll"
    cp -f ${./overlay/x86_64-windows/ntdll.dll} "$out/lib/wine/x86_64-windows/ntdll.dll"
    cp -f ${./overlay/i386-windows/mmdevapi.dll} "$out/lib/wine/i386-windows/mmdevapi.dll"
    cp -f ${./overlay/x86_64-windows/mmdevapi.dll} "$out/lib/wine/x86_64-windows/mmdevapi.dll"
    runHook postInstall
  '';

  meta = {
    description = "Patched wine-osu (WineBuilder + nix-osu-stable latency overlay) for osu!stable";
    homepage = "https://github.com/gaavin/nix-osu-stable";
    license = lib.licenses.lgpl21Plus;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
