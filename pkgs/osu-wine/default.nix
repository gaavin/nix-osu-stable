{
  lib,
  makeDesktopItem,
  symlinkJoin,
  writeShellApplication,
  writeText,
  wine-osu,
  yawl,
  osu-wineprefix,
  osu-mime,
  rpc-bridge,
  arrpc,
  winetricks,
  steam-run,
  coreutils,
  curl,
  wget,
  gnugrep,
  gnused,
  gawk,
  gnutar,
  gzip,
  xz,
  findutils,
  procps,
  gamemode,
  versions,
  pname ? "osu-wine",
  location ? "$HOME/.local/share/nix-osu-stable",
  useGameMode ? false,
  # Start OpenAsar arrpc when no discord-ipc-* socket exists (needed for Vesktop
  # without built-in arRPC, and atypical Discord setups).
  useArrpc ? true,
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

  osuDownloadUrl = versions.osuInstall.url;

  mergedEnvironment =
    {
      WINENTSYNC = "1";
      WINEFSYNC = "1";
      WINEESYNC = "1";
      WINE_AUDIO_DRIVER = "pipewire";
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
      curl
      wget
      gnugrep
      gnused
      gawk
      gnutar
      gzip
      xz
      findutils
      procps
      winetricks
      steam-run
    ]
    ++ optional useGameMode gamemode
    ++ optional useArrpc arrpc;

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
      OSU_DOWNLOAD_URL="''${OSU_DOWNLOAD_URL:-${osuDownloadUrl}}"
      STEAM_RUN="${steam-run}/bin/steam-run"
      MARKER_YAWL="$YAWL_INSTALL_DIR/.runtime-ready"
      MARKER_WINE="$YAWL_INSTALL_DIR/.wine-osu"
      WINE_WRAP="$STATE_DIR/.wine-wrap"
      WINESERVER_WRAP="$STATE_DIR/.wineserver-wrap"
      OSU_HANDLER_BIN="${osu-mime}/bin/osu-handler-wine"
      OSU_HANDLER_REG="${osu-mime}/share/nix-osu-stable/osu-handler.reg"
      MARKER_HANDLER_REG="$WINEPREFIX_DIR/.nix-osu-stable-handler-reg"
      RPC_BRIDGE_EXE="${rpc-bridge}/bridge.exe"
      MARKER_RPC_BRIDGE="$WINEPREFIX_DIR/.nix-osu-stable-rpc-bridge"
      ARRPC_BIN="${optionalString useArrpc "${arrpc}/bin/arrpc"}"
      ARRPC_LOG="$STATE_DIR/logs/arrpc.log"
      ARRPC_PIDFILE="$STATE_DIR/logs/arrpc.pid"

      export YAWL_INSTALL_DIR
      export WINEPREFIX="$WINEPREFIX_DIR"
      export WINE_INSTALL_PATH="$WINE_OSU"
      # rpc-bridge reads XDG_RUNTIME_DIR for discord-ipc-* (falls back to /run/user/1000).
      export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

      if [ -r "$CONFIG_FILE" ]; then
        set -a
        # shellcheck disable=SC1090
        source "$CONFIG_FILE"
        set +a
      fi

      # Use printf (not echo -e): Wine paths like O:\nix-... contain \n escapes.
      info() { printf '\033[1;34mnix-osu-stable:\033[0m %s\n' "$*"; }
      err() { printf '\033[1;31mnix-osu-stable:\033[0m %s\n' "$*" >&2; }

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

      # pressure-vessel filters $XDG_RUNTIME_DIR to Wayland/Pulse/etc. Host
      # discord-ipc-* sockets are invisible unless bind-mounted individually
      # (mounting the whole runtime dir breaks wayland-* symlinks).
      discord_ipc_dirs() {
        local runtime
        runtime="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
        printf '%s\n' \
          "$runtime" \
          "$runtime/app/com.discordapp.Discord" \
          "$runtime/.flatpak/dev.vencord.Vesktop/xdg-run" \
          "$runtime/.flatpak/com.discordapp.Discord/xdg-run" \
          "$runtime/snap.discord" \
          "$runtime/snap.discord-canary"
      }

      has_discord_ipc() {
        local dir sock
        while IFS= read -r dir; do
          for sock in "$dir"/discord-ipc-*; do
            [ -S "$sock" ] && return 0
          done
        done < <(discord_ipc_dirs)
        return 1
      }

      append_discord_ipc_mounts() {
        local dir sock found=0
        while IFS= read -r dir; do
          for sock in "$dir"/discord-ipc-*; do
            if [ -S "$sock" ]; then
              PRESSURE_VESSEL_FILESYSTEMS_RW+=":$sock"
              found=1
            fi
          done
        done < <(discord_ipc_dirs)
        [ "$found" -eq 1 ]
      }

      refresh_discord_ipc_mounts() {
        append_discord_ipc_mounts || true
        export PRESSURE_VESSEL_FILESYSTEMS_RW="''${PRESSURE_VESSEL_FILESYSTEMS_RW//\/:/:}"
      }

      # OpenAsar arrpc provides discord-ipc-* when Discord/Vesktop arRPC is absent.
      ensure_arrpc() {
        if has_discord_ipc; then
          return 0
        fi
        if [ -z "$ARRPC_BIN" ] || [ ! -x "$ARRPC_BIN" ]; then
          info "No Discord IPC socket found (enable Vesktop Rich Presence/arRPC, or install arrpc)"
          return 0
        fi

        mkdir -p "$(dirname "$ARRPC_LOG")"
        if [ -f "$ARRPC_PIDFILE" ]; then
          local old
          old="$(cat "$ARRPC_PIDFILE" 2>/dev/null || true)"
          if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
            :
          else
            rm -f "$ARRPC_PIDFILE"
          fi
        fi

        if ! has_discord_ipc; then
          # Prefer an already-running arrpc (e.g. systemd --user services.arrpc).
          if ! pgrep -x arrpc >/dev/null 2>&1; then
            info "Starting arrpc for Discord Rich Presence"
            "$ARRPC_BIN" >>"$ARRPC_LOG" 2>&1 &
            echo $! >"$ARRPC_PIDFILE"
          fi
          local n=0
          while [ "$n" -lt 50 ]; do
            has_discord_ipc && break
            sleep 0.1
            n=$((n + 1))
          done
        fi

        if ! has_discord_ipc; then
          err "arrpc did not create a discord-ipc socket (see $ARRPC_LOG)"
          return 1
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
        # arrpc/Discord may not be up yet; mounts refreshed again after ensure_arrpc.
        append_discord_ipc_mounts || true
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

      link_osu_drive() {
        mkdir -p "$WINEPREFIX_DIR/dosdevices" "$OSUPATH"
        ln -sfn "$WINEPREFIX_DIR/drive_c/" "$WINEPREFIX_DIR/dosdevices/c:"
        ln -sfn / "$WINEPREFIX_DIR/dosdevices/z:"
        # Drop a previous D:→osu link so it does not collide with Wine disk letters.
        if [ -L "$WINEPREFIX_DIR/dosdevices/d:" ]; then
          local dtarget
          dtarget="$(readlink -f "$WINEPREFIX_DIR/dosdevices/d:" 2>/dev/null || true)"
          if [ -n "$dtarget" ] && [ "$dtarget" = "$(realpath "$OSUPATH")" ]; then
            rm -f "$WINEPREFIX_DIR/dosdevices/d:"
          fi
        fi
        # Prefer O: for the game dir so Wine's auto disk letters (D:) don't collide.
        rm -f "$WINEPREFIX_DIR/dosdevices/o::"
        ln -sfn "$OSUPATH" "$WINEPREFIX_DIR/dosdevices/o:"
      }

      # Match winello longPathsFix: rename bundled prefix user + wire dosdevices.
      ensure_prefix_tuned() {
        local marker="$WINEPREFIX_DIR/.nix-osu-stable-tuned"
        if [ ! -f "$marker" ]; then
          local user
          user="$(whoami)"
          if [ -f "$WINEPREFIX_DIR/user.reg" ]; then
            sed -i -e "s|nellokudo|''${user}|g" \
              "$WINEPREFIX_DIR/userdef.reg" \
              "$WINEPREFIX_DIR/user.reg" \
              "$WINEPREFIX_DIR/system.reg" 2>/dev/null || true
          fi
          if [ -d "$WINEPREFIX_DIR/drive_c/users/nellokudo" ]; then
            if [ ! -e "$WINEPREFIX_DIR/drive_c/users/$user" ]; then
              mv "$WINEPREFIX_DIR/drive_c/users/nellokudo" "$WINEPREFIX_DIR/drive_c/users/$user"
            else
              rm -rf "$WINEPREFIX_DIR/drive_c/users/nellokudo"
            fi
          fi
          # wineboot may recreate dosdevices; re-link after.
          "$WINE" wineboot -u >/dev/null 2>&1 || true
          touch "$marker"
        fi
        link_osu_drive
      }

      # ProgIDs for .osz/.osk/.osr and osu:// (O:\osu!.exe — matches link_osu_drive).
      ensure_handler_reg() {
        if [ -f "$MARKER_HANDLER_REG" ]; then
          return 0
        fi
        info "Importing osu file/URL handler registry"
        "$WINE" regedit /s "$OSU_HANDLER_REG" >/dev/null 2>&1 || {
          err "Failed to import $OSU_HANDLER_REG"
          return 1
        }
        touch "$MARKER_HANDLER_REG"
      }

      # Port of winello discordRpc(): install EnderIce2/rpc-bridge as a Wine service.
      ensure_discord_rpc() {
        local force="''${1:-}"
        if [ "$force" != "force" ] \
          && [ -f "$MARKER_RPC_BRIDGE" ] \
          && [ -f "$WINEPREFIX_DIR/drive_c/windows/bridge.exe" ]; then
          return 0
        fi

        [ -s "$RPC_BRIDGE_EXE" ] || {
          err "Missing packaged rpc-bridge at $RPC_BRIDGE_EXE"
          return 1
        }

        info "Installing Discord RPC bridge (rpc-bridge)"
        # Clear a stale service entry before reinstall (winello does the same).
        "$WINE" reg delete 'HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\rpc-bridge' /f \
          >/dev/null 2>&1 || true

        # Stage under STATE_DIR so pressure-vessel can always see the binary.
        local staged_dir staged bridge_wine
        staged_dir="$STATE_DIR/.rpc-bridge-install"
        staged="$staged_dir/bridge.exe"
        mkdir -p "$staged_dir"
        cp -f "$RPC_BRIDGE_EXE" "$staged"
        chmod u+rx "$staged"
        bridge_wine="$(unix_to_wine_path "$staged")"
        if ! "$WINE" "$bridge_wine" --install; then
          err "rpc-bridge --install failed"
          return 1
        fi
        if [ ! -f "$WINEPREFIX_DIR/drive_c/windows/bridge.exe" ]; then
          err "rpc-bridge install did not create drive_c/windows/bridge.exe"
          return 1
        fi
        touch "$MARKER_RPC_BRIDGE"
        info "Discord RPC bridge ready"
      }

      ensure_prefix() {
        if [ -d "$WINEPREFIX_DIR" ] && [ -r "$WINEPREFIX_DIR/system.reg" ] && [ -w "$WINEPREFIX_DIR" ]; then
          ensure_prefix_tuned
          ensure_handler_reg
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
        ensure_prefix_tuned
        ensure_handler_reg
      }

      ensure_gstreamer_dir() {
        if [ -n "''${WINE_GST_REGISTRY_DIR:-}" ]; then
          mkdir -p "$WINE_GST_REGISTRY_DIR"
        fi
      }

      # Same as winello: fetch latest osu!install.exe into the game dir as osu!.exe.
      download_osu_bootstrap() {
        local dest="$1"
        local tmp
        mkdir -p "$(dirname "$dest")"
        tmp="$(mktemp "''${dest}.XXXXXX.tmp")"
        info "Downloading latest osu! installer"
        info "  from: $OSU_DOWNLOAD_URL"
        info "  to:   $dest"
        if curl -fL --progress-bar -o "$tmp" "$OSU_DOWNLOAD_URL"; then
          :
        elif wget --show-progress -O "$tmp" "$OSU_DOWNLOAD_URL"; then
          :
        else
          rm -f "$tmp"
          err "Failed to download osu! installer (need network + curl/wget)"
          return 1
        fi
        if [ ! -s "$tmp" ]; then
          rm -f "$tmp"
          err "Downloaded installer is empty"
          return 1
        fi
        # PE/MZ header sanity check
        if [ "$(head -c 2 "$tmp")" != "MZ" ]; then
          rm -f "$tmp"
          err "Download does not look like a Windows executable"
          return 1
        fi
        mv -f "$tmp" "$dest"
        chmod u+rw "$dest"
        info "osu! bootstrap ready ($(du -h "$dest" | cut -f1))"
      }

      ensure_osu() {
        local osu_exe="$OSUPATH/osu!.exe"
        local force="''${1:-}"

        if [ "$force" = "force" ]; then
          info "Re-downloading latest osu! installer..."
          rm -f "$osu_exe"
        fi

        if [ -s "$osu_exe" ]; then
          link_osu_drive
          return 0
        fi

        # Adopt a prior GUI install if one landed under the prefix.
        local user found="" c
        user="$(whoami)"
        local candidates=(
          "$WINEPREFIX_DIR/drive_c/users/$user/AppData/Local/osu!"
          "$WINEPREFIX_DIR/drive_c/users/steamuser/AppData/Local/osu!"
          "$WINEPREFIX_DIR/drive_c/osu!"
          "$WINEPREFIX_DIR/drive_c/osu"
        )
        for c in "''${candidates[@]}"; do
          if [ -s "$c/osu!.exe" ]; then
            found="$c"
            break
          fi
        done
        if [ -n "$found" ]; then
          info "Moving existing osu! from $found -> $OSUPATH"
          mkdir -p "$OSUPATH"
          shopt -s dotglob nullglob
          mv "$found"/* "$OSUPATH/" 2>/dev/null || true
          shopt -u dotglob nullglob
          rmdir "$found" 2>/dev/null || true
        fi

        if [ ! -s "$osu_exe" ]; then
          download_osu_bootstrap "$osu_exe"
        fi

        link_osu_drive
        [ -s "$osu_exe" ] || {
          err "osu!.exe still missing under $OSUPATH"
          return 1
        }
      }

      # Unix path -> Wine Z:\… path (works under yawl/steam-run without relying on cwd).
      unix_to_wine_path() {
        local p
        p="$(realpath "$1")"
        printf 'Z:%s' "''${p//\//\\}"
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

        local osu_exe wine_exe
        osu_exe="$OSUPATH/osu!.exe"
        [ -s "$osu_exe" ] || {
          err "Missing $osu_exe"
          return 1
        }

        # Keep osu! path visible inside pressure-vessel.
        mkdir -p "$OSUPATH"
        PRESSURE_VESSEL_FILESYSTEMS_RW="''${PRESSURE_VESSEL_FILESYSTEMS_RW:-}:$(realpath "$OSUPATH")"
        [ -d "$OSUPATH/Songs" ] && PRESSURE_VESSEL_FILESYSTEMS_RW+=":$(realpath "$OSUPATH/Songs")"
        ensure_arrpc
        if ! append_discord_ipc_mounts; then
          info "No Discord IPC socket found (Rich Presence unavailable this launch)"
        fi
        export PRESSURE_VESSEL_FILESYSTEMS_RW="''${PRESSURE_VESSEL_FILESYSTEMS_RW//\/:/:}"

        wine_exe="$(unix_to_wine_path "$osu_exe")"
        info "Launching $osu_exe"
        info "  wine path: $wine_exe"
        # Do not cd into the game dir — Wine/yawl often cannot use a custom drive as cwd.
        cd "$HOME"
        "''${pre_args[@]}" "$WINE" "$wine_exe" "''${post_args[@]}"
      }

      # Copy import onto the O: game drive so osu!'s MoveFile is same-volume.
      # Opening from Z:\…\Downloads often yields "Error moving file" under Wine.
      stage_handler_file() {
        local src="$1" base staged
        [ -f "$src" ] || {
          err "File not found: $src"
          return 1
        }
        base="$(basename "$src")"
        mkdir -p "$OSUPATH/.handler-import"
        staged="$OSUPATH/.handler-import/$base"
        cp -f "$src" "$staged"
        # O: -> OSUPATH (see link_osu_drive)
        printf 'O:\\.handler-import\\%s' "$base"
      }

      # Port of winello osuHandlerHandle: enter running yawl container when possible.
      # Do NOT wrap enter with steam-run — that nests userns and yawl fails with
      # "reassociate to namespace 'ns/user' failed: Invalid argument".
      handle_osu_arg() {
        local ARG="''${*:-}" OSUPID
        local -a HANDLERRUN PRE_ARGS

        if [ -x "$YAWL_BIN" ] && OSUPID="$(pgrep -n 'osu!.exe' 2>/dev/null || true)" && [ -n "$OSUPID" ]; then
          # Match winello: call yawl directly with enter=PID (already inside host ns).
          HANDLERRUN=(
            env "YAWL_INSTALL_DIR=$YAWL_INSTALL_DIR" "YAWL_VERBS=enter=$OSUPID"
            "$YAWL_BIN" "$OSU_HANDLER_BIN"
          )
          info "Opening via running osu! container (PID=$OSUPID)"
        else
          PRE_ARGS=()
          if [ -n "''${PRE_LAUNCH_ARGS:-}" ]; then
            # shellcheck disable=SC2206
            read -r -a PRE_ARGS <<<"''${PRE_LAUNCH_ARGS}"
          fi
          ${optionalString useGameMode ''PRE_ARGS=("${gamemode}/bin/gamemoderun" "''${PRE_ARGS[@]}")''}
          # Fresh instance still uses the normal steam-run wine wrap.
          HANDLERRUN=("''${PRE_ARGS[@]}" "$WINE")
          info "Opening with a new osu! instance"
        fi

        case "$ARG" in
          osu://*)
            info "Loading link ($ARG)"
            cd "$HOME"
            exec "''${HANDLERRUN[@]}" 'C:\windows\system32\start.exe' "$ARG"
            ;;
          *.osr | *.osz | *.osk | *.osz2)
            local EXT="''${ARG##*.}" FULLARGPATH WINEFILE
            FULLARGPATH="$(realpath "$ARG" 2>/dev/null || true)"
            FULLARGPATH="''${FULLARGPATH:-$ARG}"
            WINEFILE="$(stage_handler_file "$FULLARGPATH")" || return 1
            info "Loading file ($FULLARGPATH -> $WINEFILE)"
            cd "$HOME"
            exec "''${HANDLERRUN[@]}" 'C:\windows\system32\start.exe' /ProgIDOpen "osustable.File.$EXT" "$WINEFILE"
            ;;
          *)
            err "Unsupported osu! file or URL ($ARG)"
            return 1
            ;;
        esac
      }

      is_osu_handler_arg() {
        case "$1" in
          osu://* | *.osr | *.osz | *.osk | *.osz2) return 0 ;;
          *) return 1 ;;
        esac
      }

      prepare() {
        ensure_runtime
        # Create discord-ipc before any long-lived wine/yawl so mounts apply.
        ensure_arrpc
        refresh_discord_ipc_mounts
        ensure_prefix
        ensure_gstreamer_dir
        ensure_discord_rpc
      }

      usage() {
        cat <<EOF
      Usage: ${pname} [command]

        (no args)         Launch osu!
        --help            Show this help
        --info            Show paths
        --download-osu    Re-download latest osu! installer bootstrap
        --osuhandler <a>  Open .osz/.osk/.osr or osu:// (reuse running instance)
        --fixrpc          Reinstall Discord Rich Presence bridge (rpc-bridge)
        --winecfg         Run winecfg
        --winetricks      Run winetricks
        --regedit         Run regedit
        --wine <args>     Run wine with args
        --kill / --kill9
        --devserver <h>   Launch with -devserver <h>

      State: $STATE_DIR
      Config: $CONFIG_FILE
      Installer URL: $OSU_DOWNLOAD_URL
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
      installer:  $OSU_DOWNLOAD_URL
      EOF
          exit 0
          ;;
        --download-osu)
          prepare
          ensure_osu force
          info "Done. Run ${pname} to launch."
          exit 0
          ;;
        --fixrpc)
          ensure_runtime
          ensure_arrpc
          refresh_discord_ipc_mounts
          ensure_prefix
          ensure_gstreamer_dir
          rm -f "$MARKER_RPC_BRIDGE"
          ensure_discord_rpc force
          info "Discord RPC bridge reinstalled."
          exit 0
          ;;
        --osuhandler)
          prepare
          ensure_osu
          shift
          [ -n "''${1:-}" ] || { err "Usage: ${pname} --osuhandler <file|osu://url>"; exit 1; }
          handle_osu_arg "$@"
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
          if is_osu_handler_arg "$1"; then
            handle_osu_arg "$@"
          else
            launch_osu "$@"
          fi
          ;;
      esac
    '';
  };

  desktopItem = makeDesktopItem {
    name = pname;
    exec = "${script}/bin/${pname}";
    icon = "nix-osu-stable";
    comment = "osu!stable (yawl + wine-osu)";
    desktopName = "osu!(stable)";
    categories = [ "Game" ];
  };

  # NoDisplay handlers (winello-style): enter running instance instead of a new launch.
  fileHandlerDesktop = makeDesktopItem {
    name = "${pname}-file-handler";
    exec = "${script}/bin/${pname} --osuhandler %f";
    icon = "nix-osu-stable";
    desktopName = "osu!(stable) file handler";
    noDisplay = true;
    startupNotify = true;
    mimeTypes = [
      "application/x-osu-skin-archive"
      "application/x-osu-replay"
      "application/x-osu-beatmap-archive"
      "application/x-osu-beatmap"
    ];
  };

  urlHandlerDesktop = makeDesktopItem {
    name = "${pname}-url-handler";
    exec = "${script}/bin/${pname} --osuhandler %u";
    icon = "nix-osu-stable";
    desktopName = "osu!(stable) URL handler";
    noDisplay = true;
    startupNotify = true;
    mimeTypes = [ "x-scheme-handler/osu" ];
  };
in
symlinkJoin {
  name = pname;
  paths = [
    script
    desktopItem
    fileHandlerDesktop
    urlHandlerDesktop
    osu-mime
  ];
  passthru = {
    inherit
      wine-osu
      yawl
      osu-wineprefix
      rpc-bridge
      ;
    envConfig = resolvedConfig;
    inherit osuDownloadUrl;
  };
  meta = {
    description = "Declarative osu!stable launcher using wine-osu + yawl";
    homepage = "https://github.com/gaavin/nix-osu-stable";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = pname;
  };
}
