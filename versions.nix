# Pins referenced from osu-winello (NelloKudo/osu-winello).
# Bump these when upstream bumps wine-osu / yawl / prefix / mime bins.
{
  wineOsu = {
    version = "11.12-3";
    url = "https://github.com/NelloKudo/osu-winello/releases/download/winello-bins/wine-osu-winello-fonts-wow64-11.12-3-x86_64.tar.xz";
    hash = "sha256-h+nnMZ1R1A/qK4DPi6exbXyfBwewyHjt6ZAqvSqoiUw=";
  };

  yawl = {
    version = "0.8.2";
    url = "https://github.com/whrvt/yawl/releases/download/v0.8.2/yawl";
    hash = "sha256-u4co0+6GRNKGMkz/Q8+O7kyA/ZXq1DIpKYcGwngPDhI=";
  };

  wineprefix = {
    url = "https://github.com/NelloKudo/osu-winello/releases/download/winello-bins/osu-winello-prefix.tar.xz";
    hash = "sha256-AJz+GMFE4WNIsap+O1YceTI1qFkfsLKv+loqzqdoJ0M=";
  };

  osuMime = {
    url = "https://github.com/NelloKudo/osu-winello/releases/download/winello-bins/osu-mime.tar.gz";
    hash = "sha256-i3tWLOOhluGLDnwHUYIJtB7nTOWvBHPJUod3690FysU=";
  };

  osuIcon = {
    url = "https://raw.githubusercontent.com/NelloKudo/osu-winello/main/stuff/osu-wine.png";
    hash = "sha256-kn3mKfwpeTRScvxbH7jKbo+7zGDIozFkNVW8BmbayvQ=";
  };

  # From winello stuff/: enter running yawl container for file/URL opens.
  osuHandlerWine = {
    url = "https://raw.githubusercontent.com/NelloKudo/osu-winello/main/stuff/osu-handler-wine";
    hash = "sha256-NZH1Hr9FidaLOF7WZAVxVXKqNudjF0FuZtySQpQc69M=";
  };

  osuHandlerReg = {
    url = "https://raw.githubusercontent.com/NelloKudo/osu-winello/main/stuff/osu-handler.reg";
    hash = "sha256-7RIeoy1liSA64RJrI9Kesxyw9uDYGxIgWdEcXuEzjbs=";
  };

  # Fetched at runtime (not a FOD) so users always get the current installer.
  osuInstall = {
    url = "https://m1.ppy.sh/r/osu!install.exe";
  };

  # Discord Rich Presence bridge for Wine (EnderIce2/rpc-bridge; winello DISCRPCBRIDGEVERSION).
  rpcBridge = {
    version = "1.4.1.3";
    url = "https://github.com/EnderIce2/rpc-bridge/releases/download/v1.4.1.3/bridge.zip";
    hash = "sha256-LjSLhRtUqZtuBiKJvbH1vEyG78se8rPnSO4p8P3RQ+c=";
  };
}
