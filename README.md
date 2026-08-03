# nix-osu-stable

**osu!stable on NixOS**, using the same dependency stack as [osu-winello](https://github.com/NelloKudo/osu-winello):

- [wine-osu](https://github.com/NelloKudo/WineBuilder) (Wine built for osu!)
- [yawl](https://github.com/whrvt/yawl) (Steam Runtime / pressure-vessel)
- a ready-made wineprefix
- desktop / file associations (`.osz`, `.osk`, `.osr`, `osu://`)

This is **not** a wrapper around `osu-winello.sh`. It’s a normal Nix flake you wire into Home Manager.

> **Requirements:** `x86_64-linux`, Nix flakes, and enough disk for the Steam Runtime on first run (can be a few hundred MB).

---

## Try it once (no install)

```bash
nix run github:gaavin/nix-osu-stable
```

That downloads wine-osu, sets up yawl, seeds a wineprefix under
`~/.local/share/nix-osu-stable/`, and fetches the latest osu! installer.
First launch takes a while. After that, use the same command again, or install
properly with Home Manager (below) so you get a desktop entry and `osu-wine` on
your PATH.

---

## Install with Home Manager (recommended)

These snippets match a real NixOS + Home Manager flake setup (NixOS module
imports HM, then HM imports this flake’s module).

### 1. Add the flake input

In your system `flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-osu-stable = {
      url = "github:gaavin/nix-osu-stable";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # ...your other inputs...
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      nix-osu-stable,
      ...
    }:
    {
      nixosConfigurations.YOUR_HOSTNAME = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              # Pass the flake into home.nix:
              extraSpecialArgs = { inherit nix-osu-stable; };
              users.YOUR_USERNAME = import ./home.nix;
            };
          }
        ];
      };
    };
}
```

### 2. Enable it in `home.nix`

```nix
{ nix-osu-stable, ... }:

{
  imports = [ nix-osu-stable.homeModules.osu-stable ];

  programs.osu-stable = {
    enable = true;

    # Optional — example from a real desktop config (Wacom / tablet fix):
    # environment.WINE_ENABLE_ABS_TABLET_HACK = "2";

    # Optional extras:
    # location = "${config.xdg.dataHome}/nix-osu-stable";
    # gamemode = false;          # default; keep off unless you know you need it
    # arrpc = true;              # default; helps Discord Rich Presence
    # preLaunchArgs = "mangohud";
    # postLaunchArgs = "-devserver akatsuki.gg";
  };
}
```

### 3. Rebuild

```bash
# update the flake input (first time / when you want a new nix-osu-stable)
nix flake update nix-osu-stable

# NixOS + HM in one flake:
sudo nixos-rebuild switch --flake .#YOUR_HOSTNAME
```

You should now have:

- `osu-wine` on your PATH
- an **osu!(stable)** app in your app menu
- handlers for beatmaps / skins / replays / `osu://` links

### 4. Launch

Open **osu!(stable)** from the menu, or:

```bash
osu-wine
```

First run downloads the Steam Runtime (big) and the osu! installer, then the
client updates itself. Later launches are much faster.

---

## Discord Rich Presence (optional)

osu! under Wine can’t talk to Discord by itself. This package installs
[rpc-bridge](https://github.com/EnderIce2/rpc-bridge) automatically and mounts
Discord’s IPC socket into the Steam Runtime.

**Easiest with Vesktop** — turn on built-in arRPC:

```nix
programs.vesktop = {
  enable = true;
  settings.arRPC = true;   # creates $XDG_RUNTIME_DIR/discord-ipc-0
};
```

**Or** leave `programs.osu-stable.arrpc = true` (default). The launcher starts
[OpenAsar arrpc](https://github.com/OpenAsar/arrpc) if no IPC socket exists.
With Vesktop + standalone arrpc, also enable the Vencord plugin
**WebRichPresence (arRPC)** so Vesktop shows the activity.

Tips:

- Start Discord/Vesktop, then osu! (or restart osu! after Discord is up).
- If presence breaks after an update: `osu-wine --fixrpc`
- Flatpak Discord needs extra IPC permissions (see [rpc-bridge](https://github.com/EnderIce2/rpc-bridge)).

---

## Everyday commands

| Command | What it does |
| --- | --- |
| `osu-wine` | Launch osu! |
| `osu-wine --help` | List commands |
| `osu-wine --info` | Show paths / config |
| `osu-wine --download-osu` | Re-download the installer bootstrap |
| `osu-wine --fixrpc` | Reinstall Discord RPC bridge |
| `osu-wine --kill` | Stop Wine / osu! |
| `osu-wine --devserver HOST` | Launch with `-devserver HOST` |
| `osu-wine --winecfg` | Wine settings |
| `osu-wine --winetricks …` | winetricks in this prefix |

Opening a `.osz` / `.osk` / `.osr` or an `osu://` link reuses the running game
when possible (enters the existing yawl container instead of starting a second
window).

---

## Where files live

Default state dir: `~/.local/share/nix-osu-stable/`

```
~/.local/share/nix-osu-stable/
  yawl/          # Steam Runtime + yawl configs
  wineprefix/    # Wine prefix (seeded, then used by the game)
  osu/           # osu!.exe, Songs, Skins, …
  logs/          # e.g. arrpc.log
```

Nix owns tool versions. There is no `osu-wine --update` for wine-osu — bump
pins in [`versions.nix`](./versions.nix) (or wait for this flake to bump them).

The osu! **client** itself is not pinned: the launcher downloads the current
installer from ppy on first run.

---

## Troubleshooting

| Problem | Try this |
| --- | --- |
| First launch hangs / huge download | Normal — yawl is fetching the Steam Runtime. Needs network. |
| Game won’t start after a flake update | `osu-wine --kill`, then launch again. |
| Discord doesn’t show osu! | Enable Vesktop `settings.arRPC = true` (or arrpc + WebRichPresence), start Discord first, then `osu-wine --fixrpc` and relaunch. |
| “Runtime Platform missing” | `osu-wine --kill`; delete `~/.local/share/nix-osu-stable/yawl/.runtime-ready` and launch again to re-verify. |
| Maps / skins open a second osu! | Update to a current nix-osu-stable; file opens should enter the running instance. |
| Want a clean slate | Quit osu!, then move/remove `~/.local/share/nix-osu-stable/` (you will re-download the game). |

---

## Package-only install (no HM module)

```nix
# flake input: github:gaavin/nix-osu-stable  (same as above)

home.packages = [
  inputs.nix-osu-stable.packages.${pkgs.stdenv.hostPlatform.system}.osu-wine
];
```

Override example:

```nix
inputs.nix-osu-stable.packages.${pkgs.stdenv.hostPlatform.system}.osu-wine.override {
  location = "$HOME/Games/osu";
  useGameMode = false;
  environment.mesa_glthread = "true";
  preLaunchArgs = "mangohud";
}
```

### Flake packages

| Attribute | What it is |
| --- | --- |
| `osu-wine` (default) | Launcher + desktop entries + mime handlers |
| `wine-osu` | WineBuilder wine-osu binaries |
| `yawl` | Steam Runtime wine launcher |
| `osu-wineprefix` | Prebuilt prefix seed |
| `osu-mime` | MIME types, icon, osu-handler-wine |
| `rpc-bridge` | Discord RPC bridge binary |

```bash
nix build github:gaavin/nix-osu-stable#osu-wine
```

---

## Bumping versions (maintainers)

Edit [`versions.nix`](./versions.nix) to match current
[osu-winello.sh](https://github.com/NelloKudo/osu-winello/blob/main/osu-winello.sh)
wine / yawl / bin URLs, then refresh hashes:

```bash
nix flake prefetch <url>
# or
nix-prefetch-url --type sha256 <url> | xargs nix hash convert --hash-algo sha256 --to sri
```

---

## Credits

- [NelloKudo/osu-winello](https://github.com/NelloKudo/osu-winello) — versions, yawl setup, prefix, defaults
- [openglfreak/osu-handler-wine](https://github.com/openglfreak/osu-handler-wine) — hand off files/URLs into a running Wine osu!
- [EnderIce2/rpc-bridge](https://github.com/EnderIce2/rpc-bridge) — Discord Rich Presence under Wine
- [OpenAsar/arrpc](https://github.com/OpenAsar/arrpc) — Discord IPC for atypical clients
- [NelloKudo/WineBuilder](https://github.com/NelloKudo/WineBuilder) — wine-osu builds
- [whrvt/yawl](https://github.com/whrvt/yawl) — Steam Runtime wine launcher
- [fufexan/nix-gaming](https://github.com/fufexan/nix-gaming) `osu-stable` — first-run installer pattern
