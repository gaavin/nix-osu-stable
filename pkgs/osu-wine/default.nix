{
  lib,
  fetchurl,
  makeDesktopItem,
  symlinkJoin,
  writeShellApplication,
  wine-osu,
  yawl,
  osu-wineprefix,
  osu-mime,
  winetricks,
  steam-run,
  coreutils,
  gnugrep,
  gnused,
  gawk,
  gnutar,
  gzip,
  xz,
  findutils,
  gamemode,
  versions,
  # Override knobs
  pname ? "osu-wine",
  location ? "$HOME/.local/share/osu-winello",
  useGameMode ? true,
  preCommands ? "",
  postCommands ? "",
}:

let
  osuInstall = fetchurl {
    inherit (versions.osuInstall) url name hash;
  };

  gameModeBin = lib.optionalString useGameMode "${gamemode}/bin/gamemoderun";

  script = writeShellApplication {
    name = pname;
    runtimeInputs = [
      coreutils
      gnugrep
      gnused
      gawk
      gnutar
      gzip
      xz
      findutils
      winetricks
      steam-run
    ]
    ++ lib.optional useGameMode gamemode;

    text = ''
      set -euo pipefail

      LOCATION="''${LOCATION:-${location}}"
      LOCATION="''${LOCATION/#\~/$HOME}"
      STATE_DIR="$LOCATION"
      WINEPREFIX_DIR="$STATE_DIR/wineprefix"
      OSUPATH="$STATE_DIR/osu"
      RUNTIME_DIR="$STATE_DIR/runtime"
      YAWL_BIN="$RUNTIME_DIR/yawl"
      WINE_WRAPPER="$RUNTIME_DIR/yawl-winello"
      WINE_RUN="$RUNTIME_DIR/wine-run"
      WINESERVER_RUN="$RUNTIME_DIR/wineserver-run"
      MARKER_YAWL="$RUNTIME_DIR/.yawl-configured"
      WINE_OSU="${wine-osu}"
      YAWL_STORE="${yawl}/bin/yawl"
      PREFIX_SEED="${osu-wineprefix}"
      OSU_INSTALL="${osuInstall}"
      STEAM_RUN="${steam-run}/bin/steam-run"

      export WINEPREFIX="$WINEPREFIX_DIR"
      export WINE_INSTALL_PATH="$WINE_OSU"
      # Point Wine tools at steam-run wrappers so pressure-vessel can exec on NixOS.
      export WINE="$WINE_RUN"
      export WINESERVER="$WINESERVER_RUN"
      export WINEDLLOVERRIDES="winemenubuilder.exe=;"
      export WINEDEBUG="''${WINEDEBUG:--all}"

      # winello-default.cfg inspired defaults
      export WINENTSYNC="''${WINENTSYNC:-1}"
      export WINEFSYNC="''${WINEFSYNC:-1}"
      export WINEESYNC="''${WINEESYNC:-1}"
      export WINE_DISABLE_FULLSCREEN_HACK="''${WINE_DISABLE_FULLSCREEN_HACK:-1}"
      export vblank_mode="''${vblank_mode:-0}"
      export __GL_SYNC_TO_VBLANK="''${__GL_SYNC_TO_VBLANK:-0}"
      export LC_ALL="en_US.UTF-8"
      export LANG="en_US.UTF-8"

      # pressure-vessel: expose home / state / osu paths
      _mount_of() {
        local p
        p="$(df -P "$1" 2>/dev/null | tail -1)" || return 0
        [ -n "$p" ] && echo -n "''${p##* }:"
      }
      PRESSURE_VESSEL_FILESYSTEMS_RW="''${PRESSURE_VESSEL_FILESYSTEMS_RW:-}"
      PRESSURE_VESSEL_FILESYSTEMS_RW+="$(_mount_of "$STATE_DIR")"
      PRESSURE_VESSEL_FILESYSTEMS_RW+="$(_mount_of "$HOME")"
      PRESSURE_VESSEL_FILESYSTEMS_RW+="/mnt:/media:/run/media"
      if [ -d "$OSUPATH" ]; then
        PRESSURE_VESSEL_FILESYSTEMS_RW+=":$(realpath "$OSUPATH")"
        [ -d "$OSUPATH/Songs" ] && PRESSURE_VESSEL_FILESYSTEMS_RW+=":$(realpath "$OSUPATH/Songs")"
      fi
      export PRESSURE_VESSEL_FILESYSTEMS_RW="''${PRESSURE_VESSEL_FILESYSTEMS_RW//\/:/:}"

      # Bundled gstreamer from wine-osu when present (prefix must already be writable)
      if [ -f "''${WINE_OSU}/lib/wine/x86_64-unix/libgstfaad.so" ]; then
        export GST_PLUGIN_SYSTEM_PATH_1_0="''${WINE_OSU}/lib/wine/x86_64-unix"
        export WINE_GST_REGISTRY_DIR="''${WINEPREFIX}/gstreamer-1.0"
      fi

      info() { echo -e '\033[1;34m'"osu-winello:\033[0m $*"; }
      err() { echo -e '\033[1;31m'"osu-winello:\033[0m $*" >&2; }

      ensure_gstreamer_dir() {
        if [ -n "''${WINE_GST_REGISTRY_DIR:-}" ]; then
          mkdir -p "''${WINE_GST_REGISTRY_DIR}"
        fi
      }

      write_wrappers() {
        # steam-run is required on NixOS: yawl's Steam Runtime uses a normal dynamic linker.
        printf '#!/bin/sh\nexec %q %q "$@"\n' "$STEAM_RUN" "$WINE_WRAPPER" >"$WINE_RUN"
        printf '#!/bin/sh\nexec %q %q "$@"\n' "$STEAM_RUN" "''${WINE_WRAPPER}server" >"$WINESERVER_RUN"
        chmod +x "$WINE_RUN" "$WINESERVER_RUN"
      }

      ensure_runtime() {
        mkdir -p "$RUNTIME_DIR" "$STATE_DIR"

        if [ ! -x "$YAWL_BIN" ]; then
          info "Installing yawl into $RUNTIME_DIR"
          cp -f "$YAWL_STORE" "$YAWL_BIN"
          chmod +x "$YAWL_BIN"
        fi

        write_wrappers

        local want
        want="''${WINE_OSU}|$(basename "$WINE_OSU")"
        if [ ! -x "$WINE_WRAPPER" ] || [ ! -f "$MARKER_YAWL" ] || [ "$(cat "$MARKER_YAWL")" != "$want" ]; then
          info "Configuring yawl wrapper for wine-osu"
          # make_wrapper only writes a script next to yawl; no Steam Runtime needed.
          YAWL_VERBS="make_wrapper=winello;exec=''${WINE_OSU}/bin/wine;wineserver=''${WINE_OSU}/bin/wineserver" \
            "$YAWL_BIN"
          # update/verify needs steam-run on NixOS (pressure-vessel is dynamically linked).
          info "Verifying Steam Runtime via yawl (first run may download ~hundreds of MB)..."
          YAWL_VERBS="update;verify;exec=/bin/true" "$STEAM_RUN" "$YAWL_BIN" || {
            err "yawl runtime setup failed; retry or check network"
            return 1
          }
          printf '%s' "$want" >"$MARKER_YAWL"
        fi
      }

      ensure_prefix() {
        if [ -d "$WINEPREFIX_DIR" ] && [ -r "$WINEPREFIX_DIR/system.reg" ] && [ -w "$WINEPREFIX_DIR" ]; then
          return 0
        fi
        info "Seeding wineprefix from packaged osu-winello prefix"
        mkdir -p "$(dirname "$WINEPREFIX_DIR")"
        if [ -e "$WINEPREFIX_DIR" ]; then
          chmod -R u+w "$WINEPREFIX_DIR" 2>/dev/null || true
          rm -rf "$WINEPREFIX_DIR"
        fi
        mkdir -p "$WINEPREFIX_DIR"
        # Avoid inheriting nix store read-only mode bits.
        cp -a --no-preserve=mode "$PREFIX_SEED"/. "$WINEPREFIX_DIR/"
        chmod -R u+rwX "$WINEPREFIX_DIR"
      }

      ensure_osu() {
        local osu_exe="$OSUPATH/osu!.exe"
        if [ -f "$osu_exe" ]; then
          return 0
        fi
        info "osu! not found; running installer (GUI)..."
        mkdir -p "$OSUPATH"
        local user
        user="$(whoami)"
        "$WINE" "$OSU_INSTALL" || true
        local candidates=(
          "$WINEPREFIX_DIR/drive_c/users/$user/AppData/Local/osu!"
          "$WINEPREFIX_DIR/drive_c/users/steamuser/AppData/Local/osu!"
          "$WINEPREFIX_DIR/drive_c/osu!"
        )
        local found=""
        local c
        for c in "''${candidates[@]}"; do
          if [ -f "$c/osu!.exe" ]; then
            found="$c"
            break
          fi
        done
        if [ -z "$found" ]; then
          if [ -f "$osu_exe" ]; then
            return 0
          fi
          err "Could not locate installed osu!.exe after installer finished."
          err "Place osu! under $OSUPATH or re-run."
          return 1
        fi
        info "Moving osu! from $found -> $OSUPATH"
        shopt -s dotglob nullglob
        mv "$found"/* "$OSUPATH/" 2>/dev/null || true
        shopt -u dotglob nullglob
        rmdir "$found" 2>/dev/null || true
        if [ ! -f "$osu_exe" ]; then
          err "osu!.exe still missing under $OSUPATH"
          return 1
        fi
      }

      launch_osu() {
        local -a pre_args=()
        ${
          if useGameMode then
            ''pre_args+=(${gameModeBin})''
          else
            ""
        }
        ${preCommands}

        info "Launching $OSUPATH/osu!.exe $*"
        cd "$OSUPATH"
        "''${pre_args[@]}" "$WINE" "osu!.exe" "$@"
        ${postCommands}
      }

      usage() {
        cat <<EOF
      Usage: ${pname} [command]

        (no args)       Launch osu!
        --help          Show this help
        --info          Show paths
        --winecfg       Run winecfg in the osu! prefix
        --winetricks    Run winetricks in the osu! prefix
        --regedit       Run regedit in the osu! prefix
        --wine <args>   Run wine with args in the osu! prefix
        --kill          wineserver -k
        --kill9         wineserver -k9
        --devserver <h> Launch with -devserver <h>

      State directory: $STATE_DIR
      Versions are managed by Nix (no --update).
      EOF
      }

      case "''${1:-}" in
        --help|-h)
          usage
          exit 0
          ;;
        --info)
          ensure_runtime
          ensure_prefix
          ensure_gstreamer_dir
          cat <<EOF
      State:      $STATE_DIR
      Wineprefix: $WINEPREFIX_DIR
      osu! path:  $OSUPATH
      wine-osu:   $WINE_OSU
      yawl:       $YAWL_BIN
      wrapper:    $WINE_WRAPPER
      steam-run:  $STEAM_RUN
      EOF
          exit 0
          ;;
        --kill)
          ensure_runtime
          ensure_prefix
          ensure_gstreamer_dir
          "$WINESERVER" -k
          exit 0
          ;;
        --kill9)
          ensure_runtime
          ensure_prefix
          ensure_gstreamer_dir
          "$WINESERVER" -k9
          exit 0
          ;;
        --winecfg)
          ensure_runtime
          ensure_prefix
          ensure_gstreamer_dir
          exec "$WINE" winecfg
          ;;
        --regedit)
          ensure_runtime
          ensure_prefix
          ensure_gstreamer_dir
          exec "$WINE" regedit
          ;;
        --winetricks)
          ensure_runtime
          ensure_prefix
          ensure_gstreamer_dir
          shift
          exec env WINE="$WINE" WINESERVER="$WINESERVER" WINEPREFIX="$WINEPREFIX" winetricks "$@"
          ;;
        --wine)
          ensure_runtime
          ensure_prefix
          ensure_gstreamer_dir
          shift
          exec "$WINE" "$@"
          ;;
        --devserver)
          ensure_runtime
          ensure_prefix
          ensure_gstreamer_dir
          ensure_osu
          shift
          if [ -z "''${1:-}" ]; then
            err "Usage: ${pname} --devserver <address>"
            exit 1
          fi
          host="$1"
          shift
          launch_osu -devserver "$host" "$@"
          ;;
        "")
          ensure_runtime
          ensure_prefix
          ensure_gstreamer_dir
          ensure_osu
          launch_osu
          ;;
        *)
          ensure_runtime
          ensure_prefix
          ensure_gstreamer_dir
          ensure_osu
          launch_osu "$@"
          ;;
      esac
    '';
  };

  desktopItem = makeDesktopItem {
    name = pname;
    exec = "${script}/bin/${pname} %U";
    icon = "osu-winello";
    comment = "osu!stable (yawl + wine-osu)";
    desktopName = "osu!(stable)";
    categories = [
      "Game"
    ];
    mimeTypes = [
      "application/x-osu-skin-archive"
      "application/x-osu-replay"
      "application/x-osu-beatmap-archive"
      "application/x-osu-beatmap"
      "x-scheme-handler/osu"
    ];
  };
in
symlinkJoin {
  name = pname;
  paths = [
    script
    desktopItem
    osu-mime
  ];

  meta = {
    description = "Declarative osu!stable launcher using winello's wine-osu + yawl stack";
    homepage = "https://github.com/NelloKudo/osu-winello";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = pname;
  };
}
