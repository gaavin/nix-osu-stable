# Pins referenced from osu-winello (NelloKudo/osu-winello).
# Bump these when upstream bumps wine-osu / yawl / prefix / mime bins.
{
  wineOsu = {
    version = "11.12-1";
    url = "https://github.com/NelloKudo/WineBuilder/releases/download/wine-osu-staging-11.12-1/wine-osu-winello-fonts-wow64-11.12-1-x86_64.tar.xz";
    hash = "sha256-/4SBFDL4Iw+lsaqlLBIyH6BslJ4z5rhi43dD+euntwg=";
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

  # Fetched at runtime (not a FOD) so users always get the current installer.
  osuInstall = {
    url = "https://m1.ppy.sh/r/osu!install.exe";
  };
}
