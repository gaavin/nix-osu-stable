{
  lib,
  fetchurl,
  makeDesktopItem,
  symlinkJoin,
  writeShellApplication,
  writeText,
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
  pname ? "osu-wine",
  location ? "$HOME/.local/share/nix-osu-stable",
  useGameMode ? true,
  # Path to a shell-sourceable env file (HM generates one; package ships a default).
  configFile ? null,
  environment ? { },
  preLaunchArgs ? "",
  postLaunchArgs ? "",
}:

let
  inherit (lib)
    concatStringsSep
    escapeShellArg
    mapAttrsToList
    optional
    optionalAttrs
    optionalString
    ;

  osuInstall = fetchurl {
    inherit (versions.osuInstall) url name hash;
  };

  mergedEnvironment =
    {
      WINENTSYNC = "1";
      WINEFSYNC = "1";
      WINEESYNC = "1";
      WINE_DISABLE_FULLSCREEN_HACK = "1";
      vblank_mode = "0";
      __GL_SYNC_TO_VBLANK = "0";
      LC_ALL = "en_US.UTF-8";
      LANG = "en_US.UTF-8";
      WINEDLLOVERRIDES = "winemenubuilder.exe=;";
      WINEDEBUG = "-all";
    }
    // environment
    // optionalAttrs (preLaunchArgs != "") { PRE_LAUNCH_ARGS = preLaunchArgs; }
    // optionalAttrs (postLaunchArgs != "") { POST_LAUNCH_ARGS = postLaunchArgs; };

  packagedConfig = writeText "nix-osu-stable.env" (
    concatStringsSep "\n" (mapAttrsToList (k: v: "${k}=${escapeShellArg v}") mergedEnvironment) + "\n"
  );

  resolvedConfig = if configFile != null then configFile else packagedConfig;

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
    ++ optional useGameMode gamemode;

    text = ''
      set -euo pipefail

      LOCATION="''${LOCATION:-${location}}"
      LOCATION="''${LOCATION/#\~/$HOME}"
      STATE_DIR="$LOCATION"
      WINEPREFIX_DIR="$STATE_DIR/wineprefix"
      OSUPATH="$STATE_DIR/osu"
      YAWL_INSTALL_DIR="$STATE_DIR/yawl"
      CONFIG_FILE="''${OSU_STABLE_CONFIG:-${resolvedConfig}}"
      WINE_OSU="${wine-osu}"
      YAWL_BIN="${yawl}/bin/yawl"
      PREFIX_SEED="${osu-wineprefix}"
      OSU_INSTALL="${osuInstall}"
      STEAM_RUN="${steam-run}/bin/steam-run"
      MARKER_YAWL="$YAWL_INSTALL_DIR/.runtime-ready"
      MARKER_WINE="$YAWL_INSTALL_DIR/.wine-osu"
      WINE_WRAP="$STATE_DIR/.wine-wrap"
      WINESERVER_WRAP="$STATE_DIR/.wineserver-wrap"

      export YAWL_INSTALL_DIR
      export WINEPREFIX="$WINEPREFIX_DIR"
      export WINE_INSTALL_PATH="$WINE_OSU"

      if [ -r "$CONFIG_FILE" ]; then
        set -a
        # shellcheck disable=SC1090
        source "$CONFIG_FILE"
        set +a
      fi

      info() { echo -e '\033[1;34m'"nix-osu-stable:\033[0m $*"; }
      err() { echo -e '\033[1;31m'"nix-osu-stable:\033[0m $*" >&2; }

      write_tool_wrappers() {
        mkdir -p "$STATE_DIR"
        printf '#!/bin/sh\nexec %q env YAWL_INSTALL_DIR=%q YAWL_VERBS=config=osu %q "$@"\n' \
          "$STEAM_RUN" "$YAWL_INSTALL_DIR" "$YAWL_BIN" >"$WINE_WRAP"
        printf '#!/bin/sh\nexec %q env YAWL_INSTALL_DIR=%q YAWL_VERBS=config=osuserver %q "$@"\n' \
          "$STEAM_RUN" "$YAWL_INSTALL_DIR" "$YAWL_BIN" >"$WINESERVER_WRAP"
        chmod +x "$WINE_WRAP" "$WINESERVER_WRAP"
        export WINE="$WINE_WRAP"
        export WINESERVER="$WINESERVER_WRAP"
      }

      ensure_yawl_configs() {
        mkdir -p "$YAWL_INSTALL_DIR/configs"
        local want="$WINE_OSU"
        if [ ! -f "$YAWL_INSTALL_DIR/configs/osu.cfg" ] \
          || [ ! -f "$MARKER_WINE" ] \
          || [ "$(cat "$MARKER_WINE")" != "$want" ]; then
          printf 'exec=%s\n' "$WINE_OSU/bin/wine" >"$YAWL_INSTALL_DIR/configs/osu.cfg"
          printf 'exec=%s\n' "$WINE_OSU/bin/wineserver" >"$YAWL_INSTALL_DIR/configs/osuserver.cfg"
          printf '%s' "$want" >"$MARKER_WINE"
        fi
      }

      ensure_runtime() {
        ensure_yawl_configs
        write_tool_wrappers

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

        if [ -f "$WINE_OSU/lib/wine/x86_64-unix/libgstfaad.so" ]; then
          export GST_PLUGIN_SYSTEM_PATH_1_0="$WINE_OSU/lib/wine/x86_64-unix"
          export WINE_GST_REGISTRY_DIR="$WINEPREFIX/gstreamer-1.0"
        fi

        if [ ! -f "$MARKER_YAWL" ]; then
          info "Verifying Steam Runtime via yawl (first run may download ~hundreds of MB)..."
          YAWL_VERBS="update;verify;exec=/bin/true" "$STEAM_RUN" "$YAWL_BIN" || {
            err "yawl runtime setup failed; retry or check network"
            return 1
          }
          touch "$MARKER_YAWL"
        fi
      }

      ensure_prefix() {
        if [ -d "$WINEPREFIX_DIR" ] && [ -r "$WINEPREFIX_DIR/system.reg" ] && [ -w "$WINEPREFIX_DIR" ]; then
          return 0
        fi
        info "Seeding wineprefix"
        mkdir -p "$(dirname "$WINEPREFIX_DIR")"
        if [ -e "$WINEPREFIX_DIR" ]; then
          chmod -R u+w "$WINEPREFIX_DIR" 2>/dev/null || true
          rm -rf "$WINEPREFIX_DIR"
        fi
        mkdir -p "$WINEPREFIX_DIR"
        cp -a --no-preserve=mode "$PREFIX_SEED"/. "$WINEPREFIX_DIR/"
        chmod -R u+rwX "$WINEPREFIX_DIR"
      }

      ensure_gstreamer_dir() {
        if [ -n "''${WINE_GST_REGISTRY_DIR:-}" ]; then
          mkdir -p "$WINE_GST_REGISTRY_DIR"
        fi
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
        local found="" c
        for c in "''${candidates[@]}"; do
          if [ -f "$c/osu!.exe" ]; then
            found="$c"
            break
          fi
        done
        if [ -z "$found" ]; then
          [ -f "$osu_exe" ] && return 0
          err "Could not locate installed osu!.exe after installer finished."
          err "Place osu! under $OSUPATH or re-run."
          return 1
        fi
        info "Moving osu! from $found -> $OSUPATH"
        shopt -s dotglob nullglob
        mv "$found"/* "$OSUPATH/" 2>/dev/null || true
        shopt -u dotglob nullglob
        rmdir "$found" 2>/dev/null || true
        [ -f "$osu_exe" ] || {
          err "osu!.exe still missing under $OSUPATH"
          return 1
        }
      }

      launch_osu() {
        local -a pre_args=()
        if [ -n "''${PRE_LAUNCH_ARGS:-}" ]; then
          # shellcheck disable=SC2206
          read -r -a pre_args <<<"''${PRE_LAUNCH_ARGS}"
        fi
        ${optionalString useGameMode ''pre_args=("${gamemode}/bin/gamemoderun" "''${pre_args[@]}")''}

        local -a post_args=("$@")
        if [ "''${#post_args[@]}" -eq 0 ] && [ -n "''${POST_LAUNCH_ARGS:-}" ]; then
          # shellcheck disable=SC2206
          read -r -a post_args <<<"''${POST_LAUNCH_ARGS}"
        fi

        info "Launching $OSUPATH/osu!.exe ''${post_args[*]}"
        cd "$OSUPATH"
        "''${pre_args[@]}" "$WINE" "osu!.exe" "''${post_args[@]}"
      }

      prepare() {
        ensure_runtime
        ensure_prefix
        ensure_gstreamer_dir
      }

      usage() {
        cat <<EOF
      Usage: ${pname} [command]

        (no args)       Launch osu!
        --help          Show this help
        --info          Show paths
        --winecfg       Run winecfg
        --winetricks    Run winetricks
        --regedit       Run regedit
        --wine <args>   Run wine with args
        --kill / --kill9
        --devserver <h> Launch with -devserver <h>

      State: $STATE_DIR
      Config: $CONFIG_FILE
      EOF
      }

      case "''${1:-}" in
        --help|-h) usage; exit 0 ;;
        --info)
          prepare
          cat <<EOF
      State:      $STATE_DIR
      Wineprefix: $WINEPREFIX_DIR
      osu! path:  $OSUPATH
      yawl dir:   $YAWL_INSTALL_DIR
      wine-osu:   $WINE_OSU
      config:     $CONFIG_FILE
      EOF
          exit 0
          ;;
        --kill) prepare; "$WINESERVER" -k; exit 0 ;;
        --kill9) prepare; "$WINESERVER" -k9; exit 0 ;;
        --winecfg) prepare; exec "$WINE" winecfg ;;
        --regedit) prepare; exec "$WINE" regedit ;;
        --winetricks)
          prepare
          shift
          exec env WINE="$WINE" WINESERVER="$WINESERVER" WINEPREFIX="$WINEPREFIX" winetricks "$@"
          ;;
        --wine) prepare; shift; exec "$WINE" "$@" ;;
        --devserver)
          prepare
          ensure_osu
          shift
          [ -n "''${1:-}" ] || { err "Usage: ${pname} --devserver <address>"; exit 1; }
          host="$1"; shift
          launch_osu -devserver "$host" "$@"
          ;;
        "")
          prepare
          ensure_osu
          launch_osu
          ;;
        *)
          prepare
          ensure_osu
          launch_osu "$@"
          ;;
      esac
    '';
  };

  desktopItem = makeDesktopItem {
    name = pname;
    exec = "${script}/bin/${pname} %U";
    icon = "nix-osu-stable";
    comment = "osu!stable (yawl + wine-osu)";
    desktopName = "osu!(stable)";
    categories = [ "Game" ];
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
  passthru = {
    inherit wine-osu yawl osu-wineprefix;
    envConfig = resolvedConfig;
  };
  meta = {
    description = "Declarative osu!stable launcher using wine-osu + yawl";
    homepage = "https://github.com/gaavin/nix-osu-stable";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = pname;
  };
}
