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

1. Copy yawl into `~/.local/share/nix-osu-stable/runtime` and create a wine-osu wrapper
2. Download/verify the Steam Runtime via yawl (can be large; runs under `steam-run` on NixOS)
3. Seed the wineprefix from the packaged winello prefix
4. Run `osu!install.exe` if the game is not installed yet

`steam-run` is required so yawl’s Steam Runtime binaries can execute on NixOS (normal
dynamic linker paths). It is pulled in as a dependency of `osu-wine`.

Then start the game with `osu-wine` / `nix run .`.

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

## As a flake input

```nix
# flake.nix
{
  inputs.nix-osu-stable.url = "github:gaavin/nix-osu-stable";

  # home.packages / environment.systemPackages:
  # inputs.nix-osu-stable.packages.${pkgs.system}.osu-wine
}
```

### Overrides

```nix
inputs.nix-osu-stable.packages.${pkgs.system}.osu-wine.override {
  location = "$HOME/Games/osu";
  useGameMode = true;
  preCommands = ''echo starting'';
}
```

## State layout

Default `location` is `~/.local/share/nix-osu-stable` (override with the `location`
package argument, or at runtime with the `LOCATION` env var — must be under a path
visible to `steam-run`, typically somewhere under `$HOME`):

```
~/.local/share/nix-osu-stable/
  runtime/          # yawl binary + yawl-winello wrapper + steam-run helper scripts
  wineprefix/       # seeded then mutated by Wine
  osu/              # game install (osu!.exe, Songs, …)
```

yawl itself also keeps Steam Runtime data under `~/.local/share/yawl/` by default.

Nix owns tool versions; there is no `osu-wine --update`. Bump pins in
[`versions.nix`](./versions.nix) instead.

## Launcher commands

```
osu-wine              # launch
osu-wine --help
osu-wine --info
osu-wine --winecfg
osu-wine --winetricks [args]
osu-wine --regedit
osu-wine --wine <args>
osu-wine --kill / --kill9
osu-wine --devserver <host>
```

## Bumping versions

Edit [`versions.nix`](./versions.nix) to match current
[osu-winello.sh](https://github.com/NelloKudo/osu-winello/blob/main/osu-winello.sh)
`MAJOR`/`MINOR`/`PATCH`, `YAWLVERSION`, and bin URLs. Refresh hashes with:

```bash
nix flake prefetch <url>
# or
nix-prefetch-url --type sha256 <url> | xargs nix hash convert --hash-algo sha256 --to sri
```

For `osu!install.exe`, pass `--name osuinstall.exe` (the `!` is illegal in store names).

## Credits

- [NelloKudo/osu-winello](https://github.com/NelloKudo/osu-winello) — reference for versions, yawl setup, prefix, and defaults
- [NelloKudo/WineBuilder](https://github.com/NelloKudo/WineBuilder) — wine-osu builds
- [whrvt/yawl](https://github.com/whrvt/yawl) — Steam Runtime wine launcher
- [fufexan/nix-gaming](https://github.com/fufexan/nix-gaming) `osu-stable` — first-run installer pattern
