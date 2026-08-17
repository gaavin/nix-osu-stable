<div align="center">

<img src="https://github.com/ppy/osu/blob/master/assets/logo.png?raw=true" width="100" alt="osu! logo">

# nix-osu-stable

**Play osu! on NixOS** — native integration using Wine, Steam Runtime, and a prebuilt prefix.

[![NixOS](https://img.shields.io/badge/NixOS-unstable-informational?logo=NixOS)](https://nixos.org)
[![Flake](https://img.shields.io/badge/Flake-enabled-success)](https://nixos.wiki/wiki/Flakes)

</div>

## ⚡ Quick Start

**Just want to try it?**
```bash
nix run github:gaavin/nix-osu-stable
```

> **Requirements:** `x86_64-linux`, flakes enabled, ~500MB disk space on first launch.

---

## 📦 Install with Home Manager

### 1. Add to flake inputs

```nix
{
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    
    nix-osu-stable.url = "github:gaavin/nix-osu-stable";
    nix-osu-stable.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, home-manager, nix-osu-stable, ... }:
    {
      nixosConfigurations.YOUR_CONFIGURATION = nixpkgs.lib.nixosSystem {
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

### 2. Enable in `home.nix`

```nix
{ nix-osu-stable, ... }:
{
  imports = [ nix-osu-stable.homeModules.osu-stable ];

  programs.osu-stable = {
    enable = true;
    # Uncomment for custom options:
    # environment.WINE_ENABLE_ABS_TABLET_HACK = "2";  # Tablet fix
    # location = "${config.xdg.dataHome}/nix-osu-stable";
    # gamemode = false;
    # preLaunchArgs = "mangohud";
  };
}
```

### 3. Build & launch

```bash
nix flake update nix-osu-stable
sudo nixos-rebuild switch --flake .#YOUR_CONFIGURATION
osu-wine
```

✅ First run downloads the Steam Runtime, seeds the prefix, and installs osu!  
✅ Subsequent launches are instant  
✅ Desktop entry + file associations included

---

## 🎵 Essential: Set Audio Offset

Wine introduces latency. **Configure this in-game** or your hits will feel late:

<div>
<strong>Options → Audio → Offset:</strong>
• <strong>Normal mode:</strong> −40 to −35 ms<br/>
• <strong>Audio compatibility mode:</strong> −25 ms
</div>

Every setup differs — watch the hit error meter and fine-tune.

---

## 🔊 Optional: Low-Latency PipeWire

Default PipeWire works, but a locked quantum reduces buffer delay to ~2.7ms:

```nix
# In configuration.nix (NixOS, not Home Manager):
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

security.rtkit.enable = true;
```

After rebuild, restart PipeWire and **re-check your audio offset** — lower latency changes how it feels.

**Hearing crackling?** Try `quantum = 256` instead.

---

## 💬 Discord Rich Presence

osu! can't reach Discord from Wine directly. Choose one:

**Option A: Vesktop (recommended)**
```nix
programs.vesktop = {
  enable = true;
  settings.arRPC = true;
};
```

**Option B: Keep defaults** (`arrpc = true` by default)  
Start Discord first, then launch osu!. If broken after update: `osu-wine --fixrpc`

---

## 📋 Commands

| Command | Purpose |
|---------|---------|
| <span>osu-wine</span> | Launch |
| <span>osu-wine --help</span> | List all commands |
| <span>osu-wine --info</span> | Show config / paths |
| <span>osu-wine --kill</span> | Force quit |
| <span>osu-wine --fixrpc</span> | Reinstall Discord bridge |
| <span>osu-wine --winecfg</span> | Wine settings |
| <span>osu-wine --winetricks …</span> | winetricks in prefix |

Opening `.osz` / `.osk` / `.osr` files or `osu://` links **reuses the running instance**.

---

## 📁 File Structure

```
~/.local/share/nix-osu-stable/
  yawl/          Steam Runtime
  wineprefix/    Wine prefix
  osu/           Game files, songs, skins
  logs/          Debug logs
```

Nix pins wine-osu & yawl versions (edit [`versions.nix`](./versions.nix)); osu! itself auto-updates.

---

## 🔧 Troubleshooting

| Issue | Solution |
|-------|----------|
| Hits feel late | Set audio offset (−40/−35 ms) |
| Audio crackling | Raise PipeWire quantum to `256` |
| First launch hangs | Normal (downloading Steam Runtime); ensure network access |
| Won't start after update | `osu-wine --kill` then relaunch |
| No Discord presence | Start Discord first, then `osu-wine --fixrpc` |
| "Runtime Platform missing" | `osu-wine --kill && rm ~/.local/share/nix-osu-stable/yawl/.runtime-ready` |
| Multiple windows opening | Update flake; file handlers should enter running instance |
| Start fresh | Remove `~/.local/share/nix-osu-stable/` (everything re-downloads) |

---

## 🎮 Advanced

### Package only (skip Home Manager)
```nix
home.packages = [
  inputs.nix-osu-stable.packages.${pkgs.stdenv.hostPlatform.system}.osu-wine
];
```

### Custom overrides
```nix
inputs.nix-osu-stable.packages.${pkgs.stdenv.hostPlatform.system}.osu-wine.override {
  location = "$HOME/Games/osu";
  useGameMode = false;
  environment.mesa_glthread = "true";
  preLaunchArgs = "mangohud";
}
```

### Available flake packages
- `osu-wine` — Launcher, desktop entry, MIME handlers (default)
- `wine-osu` — Wine binaries
- `yawl` — Steam Runtime launcher
- `osu-wineprefix` — Prefix seed
- `osu-mime` — File associations
- `rpc-bridge` — Discord bridge

```bash
nix build github:gaavin/nix-osu-stable#osu-wine
```

---

## 🙏 Credits

Built on [osu-winello](https://github.com/NelloKudo/osu-winello) stack:

- [NelloKudo/WineBuilder](https://github.com/NelloKudo/WineBuilder) — wine-osu
- [whrvt/yawl](https://github.com/whrvt/yawl) — Steam Runtime launcher
- [EnderIce2/rpc-bridge](https://github.com/EnderIce2/rpc-bridge) — Discord RPC
- [OpenAsar/arrpc](https://github.com/OpenAsar/arrpc) — Discord IPC
- [openglfreak/osu-handler-wine](https://github.com/openglfreak/osu-handler-wine) — File handoff
- [fufexan/nix-gaming](https://github.com/fufexan/nix-gaming) — Pattern inspiration
