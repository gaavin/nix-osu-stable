{
  lib,
  stdenvNoCC,
  fetchurl,
  versions,
}:

stdenvNoCC.mkDerivation {
  pname = "yawl";
  inherit (versions.yawl) version;

  src = fetchurl {
    inherit (versions.yawl) url hash;
  };

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/yawl"
    runHook postInstall
  '';

  meta = {
    description = "Wine launcher that runs wine inside Steam's pressure-vessel runtime";
    homepage = "https://github.com/whrvt/yawl";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
