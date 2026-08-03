{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
  versions,
}:

stdenvNoCC.mkDerivation {
  pname = "rpc-bridge";
  inherit (versions.rpcBridge) version;

  src = fetchurl {
    inherit (versions.rpcBridge) url hash;
  };

  nativeBuildInputs = [ unzip ];

  dontConfigure = true;
  dontBuild = true;

  unpackPhase = ''
    runHook preUnpack
    unzip -q "$src"
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 bridge.exe "$out/bridge.exe"
    runHook postInstall
  '';

  meta = {
    description = "Discord Rich Presence bridge for Wine applications";
    homepage = "https://github.com/EnderIce2/rpc-bridge";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
