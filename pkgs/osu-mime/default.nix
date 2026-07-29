{
  lib,
  stdenvNoCC,
  fetchurl,
  versions,
}:

stdenvNoCC.mkDerivation {
  pname = "osu-mime";
  version = "winello-bins";

  srcs = [
    (fetchurl {
      inherit (versions.osuMime) url hash;
    })
    (fetchurl {
      inherit (versions.osuIcon) url hash;
      name = "osu-wine.png";
    })
  ];

  sourceRoot = ".";

  dontConfigure = true;
  dontBuild = true;

  unpackPhase = ''
    runHook preUnpack
    # srcs[0] = mime tarball, srcs[1] = icon
    read -ra srcArray <<< "$srcs"
    tar -xzf "''${srcArray[0]}"
    cp "''${srcArray[1]}" osu-wine.png
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 osu-mime/osu-file-extensions.xml \
      "$out/share/mime/packages/nix-osu-stable.xml"

    for size in 16 24 32 48 64 128 256; do
      install -Dm644 osu-wine.png \
        "$out/share/icons/hicolor/''${size}x''${size}/apps/nix-osu-stable.png"
    done
    install -Dm644 osu-wine.png "$out/share/icons/nix-osu-stable.png"
    runHook postInstall
  '';

  meta = {
    description = "MIME types and icon for osu!stable";
    homepage = "https://github.com/gaavin/nix-osu-stable";
    license = lib.licenses.gpl3Plus;
    platforms = [ "x86_64-linux" ];
  };
}
