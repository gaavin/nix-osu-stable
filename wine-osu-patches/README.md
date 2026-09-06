# Optional wine-osu overlays

Wine-side patches applied **on top of** `whrvt/wine-osu-patches` tag `winello-v11.12-3` by WineBuilder `custompatches/`.

The default `wine-osu` pin in [`versions.nix`](../versions.nix) is the stock WineBuilder **11.12-3** tarball (osu!auth.dll crash fix, x11 unplug crash fix). These files are **not** in that pin; they are for an optional custom rebuild.

Do **not** add game-side hooks (inline-hooking `bass.dll` / `osu!.exe`). peppy has said that is against the rules.

## What they do

| Patch | Layer | Effect |
| --- | --- | --- |
| `0002-winepipewire-Account-for-PipeWire-graph-delay.patch` | `winepipewire.drv` | `IAudioClock::GetPosition` / `GetStreamLatency` include `pw_time.delay` + `queued`, so WASAPI latency compensation matches the DAC instead of “bytes handed to PipeWire”. |
| `0003-mmdevapi-Use-two-shared-render-periods.patch` | mmdevapi | Shared-mode render buffer is 2 periods instead of 3. |
| `0004-winewayland-Present-GL-on-xdg-toplevel-for-scanout.patch` | winewayland EGL | Bind `wglSwapBuffers` to the xdg_toplevel instead of a dummy-SHM + `wl_subsurface`. Skip the dummy parent buffer (it blocks KMS scanout), mark the surface opaque, and put `wp_tearing_control` ASYNC on that same surface. |

## Environment

| Variable | Default | Meaning |
| --- | --- | --- |
| `WINE_AUDIO_DRIVER` | `pipewire` | Already set by the launcher. Required for patch 0002. |
| `WINE_WAYLAND_GL_TOPLEVEL` | on | `0` restores the old GL-on-subsurface path (patch 0004). |
| `WINE_OSU_USE_X11` | unset | `1` keeps X11/XWayland (launcher). |

## Build

GitHub Actions workflow `.github/workflows/wine-osu.yml` clones WineBuilder, drops these files into `custompatches/`, and uploads the tarball.

Locally (needs Docker):

```bash
git clone https://github.com/NelloKudo/WineBuilder.git
cp wine-osu-patches/*.patch WineBuilder/custompatches/
cd WineBuilder && ./build.sh
```

Then pin the resulting `wine-osu-winello-fonts-wow64-*.tar.xz` in `versions.nix`.
