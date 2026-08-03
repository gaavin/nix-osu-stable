# nix-osu-stable

**osu!stable on NixOS**, using the same stack as [osu-winello](https://github.com/NelloKudo/osu-winello):

- [wine-osu](https://github.com/NelloKudo/WineBuilder) — Wine built for osu!
- [yawl](https://github.com/whrvt/yawl) — Steam Runtime / pressure-vessel
- a ready-made wineprefix
- desktop / file associations (`.osz`, `.osk`, `.osr`, `osu://`)

This is a normal Nix flake (Home Manager module included), **not** a wrapper around
`osu-winello.sh`.

> **Needs:** `x86_64-linux`, flakes, and a few hundred MB of disk for the Steam
> Runtime on first launch.

---

## 1. Try it (optional)

No flake changes — just run:

```bash
nix run github:gaavin/nix-osu-stable
```

First launch downloads wine-osu, the Steam Runtime, and the osu! installer into
`~/.local/share/nix-osu-stable/`. For a permanent install with a desktop entry,
use Home Manager below.

---

## 2. Install with Home Manager

These steps match a typical NixOS + Home Manager flake (system flake imports HM,
HM imports this module).

### Add the flake input

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
              extraSpecialArgs = { inherit nix-osu-stable; };
              users.YOUR_USERNAME = import ./home.nix;
            };
          }
        ];
      };
    };
}
```

### Enable the module in `home.nix`

```nix
{ nix-osu-stable, ... }:

{
  imports = [ nix-osu-stable.homeModules.osu-stable ];

  programs.osu-stable = {
    enable = true;

    # Optional tablet fix (OpenTabletDriver Absolute + Wayland):
    # environment.WINE_ENABLE_ABS_TABLET_HACK = "2";

    # Optional:
    # location = "${config.xdg.dataHome}/nix-osu-stable";
    # gamemode = false;   # default; keep off unless you know you need it
    # arrpc = true;       # default; helps Discord Rich Presence
    # preLaunchArgs = "mangohud";
    # postLaunchArgs = "-devserver akatsuki.gg";
  };
}
```

The flake’s Home Manager module defaults `package` to this flake’s `osu-wine`.
You do **not** need to set `package` yourself.

### Rebuild and launch

```bash
nix flake update nix-osu-stable
sudo nixos-rebuild switch --flake .#YOUR_HOSTNAME

osu-wine
# or open “osu!(stable)” from your app menu
```

First run:

1. Verifies / downloads the Steam Runtime via yawl (can be large)
2. Seeds the wineprefix
3. Downloads the latest osu! installer from ppy
4. Lets the client self-update

Later launches are much faster. You get `osu-wine` on PATH, a desktop entry, and
handlers for beatmaps / skins / replays / `osu://` links.

---

## 3. Set your audio offset (do this)

Wine adds a bit of audio delay. **Set a global offset in osu!** or hits will feel
late even when your system latency is fine.

Same guidance as [osu-winello](https://github.com/NelloKudo/osu-winello):

| Mode | Suggested global offset |
| --- | --- |
| Normal | **−40 ms** to **−35 ms** |
| Audio compatibility mode | **−25 ms** |

In-game: **Options → Audio → Offset**. Watch the hit error meter and fine-tune —
every setup differs slightly.

---

## 4. Optional: lower system audio latency

PipeWire on NixOS defaults are fine for desktop use but soft for rhythm games.
A locked low quantum cuts buffer delay (example below ≈ **2.7 ms** at 128/48000).

Add something like this to your **NixOS** `configuration.nix` (not Home Manager),
then rebuild:

```nix
{
  services.pipewire = {
    enable = true;
    pulse.enable = true;
    extraConfig.pipewire."92-low-latency" = {
      "context.properties" = {
        "default.clock.rate" = 48000;
        "default.clock.quantum" = 128;
        "default.clock.min-quantum" = 128;
        "default.clock.max-quantum" = 128;
      };
    };
    extraConfig.pipewire-pulse."92-low-latency" = {
      "pulse.properties" = {
        "pulse.min.req" = "128/48000";
        "pulse.default.req" = "128/48000";
        "pulse.max.req" = "128/48000";
        "pulse.min.quantum" = "128/48000";
        "pulse.max.quantum" = "128/48000";
      };
      "stream.properties" = {
        "node.latency" = "128/48000";
        "resample.quality" = 1;
      };
    };
  };

  # Lets PipeWire take realtime priority
  security.rtkit.enable = true;

  # Optional: extra headroom if your user is in the `audio` group
  security.pam.loginLimits = [
    {
      domain = "@audio";
      type = "-";
      item = "rtprio";
      value = "95";
    }
    {
      domain = "@audio";
      type = "-";
      item = "memlock";
      value = "unlimited";
    }
  ];
  # users.users.YOUR_USERNAME.extraGroups = [ "wheel" "audio" ];
}
```

After `nixos-rebuild switch`, restart PipeWire (or log out/in), launch osu!, and
**re-check your offset** — lower latency can change how the old offset feels.

Notes:

- If you hear crackling, try a larger quantum (e.g. `256` instead of `128`) in
  every place above.
- A low-latency / preemptible kernel (e.g. CachyOS via Chaotic Nyx) and
  `boot.kernelParams = [ "preempt=full" ];` can help further, but PipeWire +
  offset matter more for most people.
- More general tuning: [osu-winello wiki — Optimizing performance](https://github.com/NelloKudo/osu-winello/wiki/Optimizing:-osu!-performance).

---

## 5. Optional: Discord Rich Presence

osu! under Wine can’t reach Discord alone. This package installs
[rpc-bridge](https://github.com/EnderIce2/rpc-bridge) and mounts Discord IPC into
the Steam Runtime.

**With Vesktop** — enable built-in arRPC:

```nix
programs.vesktop = {
  enable = true;
  settings.arRPC = true;
};
```

**Or** keep `programs.osu-stable.arrpc = true` (default). The launcher starts
[OpenAsar arrpc](https://github.com/OpenAsar/arrpc) if no `discord-ipc-*` socket
exists. With Vesktop + standalone arrpc, also enable the Vencord plugin
**WebRichPresence (arRPC)**.

- Start Discord/Vesktop, then osu! (or restart osu! after Discord is up).
- Broken after an update? `osu-wine --fixrpc`
- Flatpak Discord needs extra IPC permissions ([rpc-bridge docs](https://github.com/EnderIce2/rpc-bridge)).

---

## 6. Day-to-day use

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

Opening a `.osz` / `.osk` / `.osr` or an `osu://` link reuses the **already
running** game when possible (enters the yawl container instead of a second
window).

### Where files live

```
~/.local/share/nix-osu-stable/
  yawl/          # Steam Runtime + yawl configs
  wineprefix/    # Wine prefix
  osu/           # osu!.exe, Songs, Skins, …
  logs/          # e.g. arrpc.log
```

Nix owns wine-osu / yawl versions (bump [`versions.nix`](./versions.nix) or wait
for this flake). The osu! **client** is not pinned — first run always fetches
the current installer from ppy.

---

## 7. Troubleshooting

| Problem | Try this |
| --- | --- |
| Hits feel late | Set global offset (−40/−35 ms, or −25 ms in audio compatibility mode). |
| Audio crackling after low-latency PipeWire | Raise quantum to `256` (or higher) and rebuild. |
| First launch hangs / huge download | Normal — Steam Runtime fetch. Needs network. |
| Won’t start after a flake update | `osu-wine --kill`, then launch again. |
| No Discord presence | Vesktop `settings.arRPC = true` (or arrpc + WebRichPresence), Discord first, then `osu-wine --fixrpc`. |
| “Runtime Platform missing” | `osu-wine --kill`; remove `~/.local/share/nix-osu-stable/yawl/.runtime-ready`; launch again. |
| Maps open a second osu! | Update nix-osu-stable; handlers should enter the running instance. |
| Clean slate | Quit osu!, move/remove `~/.local/share/nix-osu-stable/` (re-downloads the game). |

---

## Advanced

### Package-only (no Home Manager module)

```nix
home.packages = [
  inputs.nix-osu-stable.packages.${pkgs.stdenv.hostPlatform.system}.osu-wine
];
```

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
| `wine-osu` | WineBuilder binaries |
| `yawl` | Steam Runtime wine launcher |
| `osu-wineprefix` | Prebuilt prefix seed |
| `osu-mime` | MIME types, icon, handler |
| `rpc-bridge` | Discord RPC bridge binary |

```bash
nix build github:gaavin/nix-osu-stable#osu-wine
```

### Bumping versions (maintainers)

Edit [`versions.nix`](./versions.nix) to match
[osu-winello.sh](https://github.com/NelloKudo/osu-winello/blob/main/osu-winello.sh),
then:

```bash
nix flake prefetch <url>
# or
nix-prefetch-url --type sha256 <url> | xargs nix hash convert --hash-algo sha256 --to sri
```

---

## Credits

- [NelloKudo/osu-winello](https://github.com/NelloKudo/osu-winello) — versions, yawl setup, prefix, defaults, offset guidance
- [openglfreak/osu-handler-wine](https://github.com/openglfreak/osu-handler-wine) — file/URL handoff into a running Wine osu!
- [EnderIce2/rpc-bridge](https://github.com/EnderIce2/rpc-bridge) — Discord Rich Presence under Wine
- [OpenAsar/arrpc](https://github.com/OpenAsar/arrpc) — Discord IPC for atypical clients
- [NelloKudo/WineBuilder](https://github.com/NelloKudo/WineBuilder) — wine-osu builds
- [whrvt/yawl](https://github.com/whrvt/yawl) — Steam Runtime wine launcher
- [fufexan/nix-gaming](https://github.com/fufexan/nix-gaming) `osu-stable` — first-run installer pattern
