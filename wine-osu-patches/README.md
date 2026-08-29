# wine-osu latency overlay

Patches applied **on top of** `whrvt/wine-osu-patches` tag `winello-v11.12-2` by WineBuilder `custompatches/`.

They exist to drive osu!stable's universal Offset from the community **−40 ms** toward **0** without touching host PipeWire, and to present GL with the lowest compositor delay Wayland allows.

## What they do

| Patch | Layer | Effect |
| --- | --- | --- |
| `0001-ntdll-Hook-BASS-Init-on-osu-load.patch` | osu!'s BASS mixer | After `bass.dll` maps in `osu!.exe`, inline-hook `BASS_Init` / `BASS_SetConfig`. Strip DirectSound, set `BASS_DEVICE_LATENCY`, clamp `BASS_CONFIG_DEV_BUFFER` from the default **30 ms** down to two periods of `WINE_OSU_BASS_PERIOD` frames (default 128 ≈ 2.9 ms @ 44.1 kHz). Does not touch files next to `osu!.exe`. |
| `0002-winepipewire-Account-for-PipeWire-graph-delay.patch` | `winepipewire.drv` | `IAudioClock::GetPosition` / `GetStreamLatency` include `pw_time.delay` + `queued`, so BASS's latency compensation matches the DAC instead of “bytes handed to PipeWire”. |
| `0003-mmdevapi-Use-two-shared-render-periods.patch` | mmdevapi | Shared-mode render buffer is 2 periods instead of 3. |
| `0004-winewayland-Present-GL-on-xdg-toplevel-for-scanout.patch` | winewayland EGL | Bind `wglSwapBuffers` to the xdg_toplevel instead of a dummy-SHM + `wl_subsurface`. Skip the dummy parent buffer (it blocks KMS scanout), mark the surface opaque, and put `wp_tearing_control` ASYNC on that same surface. |

Together: BASS mixes into a ~6 ms WASAPI buffer **and** is told the remaining graph/USB delay, so the mixer timestamps against what you hear. On Wayland the GL backbuffer can be async-flipped / scanned out instead of composited as a child surface.

## Environment

| Variable | Default | Meaning |
| --- | --- | --- |
| `WINE_OSU_BASS_HOOK` | on for `osu!.exe` | `0` disables the hook. `1` forces it on any process. |
| `WINE_OSU_BASS_PERIOD` | `128` | Device period in frames. 64 is the next step if traces are xrun-free. |
| `WINE_AUDIO_DRIVER` | `pipewire` | Already set by the launcher. Required for patch 0002. |
| `WINE_WAYLAND_GL_TOPLEVEL` | on | `0` restores the old GL-on-subsurface path. |
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
