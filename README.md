# nix-osu-stable

Declarative [osu!stable](https://osu.ppy.sh) on Nix using the same dependency stack as
[osu-winello](https://github.com/NelloKudo/osu-winello): **WineBuilder wine-osu** +
**[yawl](https://github.com/whrvt/yawl)** (Steam pressure-vessel runtime) + a prebuilt
wineprefix seed.

This is **not** a wrapper around `osu-winello.sh`. Pins, URLs, and env defaults are
taken from upstream winello; packaging and first-run install are Nix-native.

## Quick start

```bash
nix run github:gaavin/nix-osu-stable
# or from a checkout:
nix run .
```

First launch will:

1. Write yawl configs pointing at packaged wine-osu (`YAWL_VERBS=config=osu`)
2. Download/verify the Steam Runtime via yawl (can be large; runs under `steam-run` on NixOS)
3. Seed the wineprefix from the packaged winello prefix
4. Download the **latest** osu! installer from ppy (`m1.ppy.sh`) into `…/osu/osu!.exe`
   with a visible progress bar (same approach as winello; not pinned in the Nix store).
   The first game launch then self-updates the client

`steam-run` is required so yawl’s Steam Runtime binaries can execute on NixOS. It is
pulled in as a dependency of `osu-wine`.

Then start the game with `osu-wine` / `nix run .`.

## Home Manager (recommended)

```nix
# flake.nix — pass the flake into HM
home-manager.extraSpecialArgs = {
  inherit (inputs) nix-osu-stable;
};

# home.nix
{ nix-osu-stable, pkgs, ... }:
{
  imports = [ nix-osu-stable.homeModules.osu-stable ];

  programs.osu-stable = {
    enable = true;
    package = nix-osu-stable.packages.${pkgs.system}.osu-wine;
    # location = "${config.xdg.dataHome}/nix-osu-stable"; # default
    # gamemode = true;
    # environment.WINEFSYNC = "1";
    # preLaunchArgs = "mangohud";
    # postLaunchArgs = "-devserver akatsuki.gg";
  };
}
```

The module generates a store env file sourced at launch and refreshes yawl wine
`exec=` configs on activation when wine-osu changes.

## Packages

| Attribute | Description |
| --- | --- |
| `osu-wine` (default) | Launcher + desktop entry + mime types |
| `wine-osu` | NelloKudo WineBuilder binaries |
| `yawl` | Steam-runtime wine launcher |
| `osu-wineprefix` | Prebuilt prefix seed |
| `osu-mime` | File associations + icon |

```bash
nix build .#wine-osu
nix build .#osu-wine
```

## As a flake input (package only)

```nix
home.packages = [
  inputs.nix-osu-stable.packages.${pkgs.system}.osu-wine
];
```

### Package overrides

```nix
inputs.nix-osu-stable.packages.${pkgs.system}.osu-wine.override {
  location = "$HOME/Games/osu";
  useGameMode = true;
  environment.mesa_glthread = "true";
  preLaunchArgs = "mangohud";
}
```

## State layout

Default `location` is `~/.local/share/nix-osu-stable` (override with the `location`
package/module option, or at runtime with `LOCATION` — must be under `$HOME` for
`steam-run`):

```
~/.local/share/nix-osu-stable/
  yawl/             # Steam Runtime + configs/osu.cfg + configs/osuserver.cfg
  wineprefix/       # seeded then mutated by Wine
  osu/              # game install (osu!.exe, Songs, …)
  .wine-wrap        # steam-run + yawl helpers (recreated as needed)
  .wineserver-wrap
```

yawl may also keep Steam Runtime data under its default cache paths.

Nix owns tool versions; there is no `osu-wine --update`. Bump pins in
[`versions.nix`](./versions.nix) instead.

## Launcher commands

```
osu-wine                 # launch (downloads installer on first run if missing)
osu-wine --help
osu-wine --info
osu-wine --download-osu  # re-fetch latest installer bootstrap
osu-wine --winecfg
osu-wine --winetricks [args]
osu-wine --regedit
osu-wine --wine <args>
osu-wine --kill / --kill9
osu-wine --devserver <host>
```

Override the installer URL at runtime with `OSU_DOWNLOAD_URL=…` if needed.

## Bumping versions

Edit [`versions.nix`](./versions.nix) to match current
[osu-winello.sh](https://github.com/NelloKudo/osu-winello/blob/main/osu-winello.sh)
`MAJOR`/`MINOR`/`PATCH`, `YAWLVERSION`, and bin URLs. Refresh hashes with:

```bash
nix flake prefetch <url>
# or
nix-prefetch-url --type sha256 <url> | xargs nix hash convert --hash-algo sha256 --to sri
```

The osu! installer itself is **not** hashed — it is downloaded at launch time.

## Credits

- [NelloKudo/osu-winello](https://github.com/NelloKudo/osu-winello) — reference for versions, yawl setup, prefix, and defaults
- [NelloKudo/WineBuilder](https://github.com/NelloKudo/WineBuilder) — wine-osu builds
- [whrvt/yawl](https://github.com/whrvt/yawl) — Steam Runtime wine launcher
- [fufexan/nix-gaming](https://github.com/fufexan/nix-gaming) `osu-stable` — first-run installer pattern
