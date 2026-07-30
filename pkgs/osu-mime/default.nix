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
    (fetchurl {
      inherit (versions.osuHandlerWine) url hash;
      name = "osu-handler-wine";
    })
    (fetchurl {
      inherit (versions.osuHandlerReg) url hash;
      name = "osu-handler.reg";
    })
  ];

  sourceRoot = ".";

  dontConfigure = true;
  dontBuild = true;

  unpackPhase = ''
    runHook preUnpack
    # srcs: mime tarball, icon, handler binary, handler reg
    read -ra srcArray <<< "$srcs"
    tar -xzf "''${srcArray[0]}"
    cp "''${srcArray[1]}" osu-wine.png
    cp "''${srcArray[2]}" osu-handler-wine
    cp "''${srcArray[3]}" osu-handler.reg
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

    # nix-osu-stable maps the game dir to O: (not winello's D:).
    # .reg values use doubled backslashes; sed needs \\\\ to match \\.
    install -Dm755 osu-handler-wine "$out/bin/osu-handler-wine"
    sed 's|D:\\\\osu!.exe|O:\\\\osu!.exe|g' osu-handler.reg \
      >osu-handler-o.reg
    install -Dm644 osu-handler-o.reg \
      "$out/share/nix-osu-stable/osu-handler.reg"
    runHook postInstall
  '';

  meta = {
    description = "MIME types, icon, and file/URL handler for osu!stable";
    homepage = "https://github.com/gaavin/nix-osu-stable";
    license = lib.licenses.gpl3Plus;
    platforms = [ "x86_64-linux" ];
  };
}
