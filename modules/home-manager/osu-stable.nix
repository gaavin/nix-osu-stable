{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    concatStringsSep
    escapeShellArg
    literalExpression
    mapAttrsToList
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  cfg = config.programs.osu-stable;

  settingsValueType = types.oneOf [
    types.str
    types.int
    types.bool
    types.float
  ];

  formatSettingsValue = v: if builtins.isBool v then (if v then "1" else "0") else toString v;

  formatSettingsFile =
    name: attrs:
    pkgs.writeText name (
      concatStringsSep "\n" (mapAttrsToList (k: v: "${k} = ${formatSettingsValue v}") attrs) + "\n"
    );

  secretSettingKeys = lib.filter (k: lib.toLower k == "password") (
    (lib.attrNames cfg.settings) ++ (lib.attrNames cfg.globalSettings)
  );
in
{
  options.programs.osu-stable = {
    enable = mkEnableOption "osu!stable (wine-osu + yawl via nix-osu-stable)";

    package = mkOption {
      type = types.nullOr types.package;
      default = null;
      defaultText = literalExpression "nix-osu-stable.packages.\${pkgs.stdenv.hostPlatform.system}.osu-wine";
      example = literalExpression "nix-osu-stable.packages.\${pkgs.stdenv.hostPlatform.system}.osu-wine";
      description = ''
        osu-wine package to install. When you import
        `nix-osu-stable.homeModules.osu-stable` from the flake, this defaults
        to that flake's `osu-wine` — you usually do not need to set it.
      '';
    };

    location = mkOption {
      type = types.str;
      default = "${config.xdg.dataHome}/nix-osu-stable";
      defaultText = literalExpression "\${config.xdg.dataHome}/nix-osu-stable";
      description = "Mutable state directory (wineprefix, osu install, yawl runtime).";
    };

    gamemode = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Wrap launches with gamemoderun. Requires a working GameMode daemon
        (e.g. programs.gamemode.enable on NixOS). Off by default — gamemode
        preload often breaks inside yawl/steam-run.
      '';
    };

    arrpc = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Enable OpenAsar arrpc so a discord-ipc-* socket exists for rpc-bridge.
        Starts a user systemd service when available, and the launcher also
        starts arrpc on demand if no socket is present. Disable if you already
        run Discord/Vesktop built-in arRPC or a separate arrpc instance.
      '';
    };

    environment = mkOption {
      type = types.attrsOf types.str;
      default = {
        WINENTSYNC = "1";
        WINEFSYNC = "1";
        WINEESYNC = "1";
        WINE_AUDIO_DRIVER = "pipewire";
        WINE_DISABLE_FULLSCREEN_HACK = "1";
        vblank_mode = "0";
        __GL_SYNC_TO_VBLANK = "0";
        LC_ALL = "en_US.UTF-8";
        LANG = "en_US.UTF-8";
      };
      example = {
        WINEFSYNC = "1";
        mesa_glthread = "true";
      };
      description = "Environment variables written to the generated config and sourced at launch.";
    };

    preLaunchArgs = mkOption {
      type = types.str;
      default = "";
      example = "mangohud";
      description = "Programs prepended before wine (e.g. mangohud). gamemode is separate.";
    };

    postLaunchArgs = mkOption {
      type = types.str;
      default = "";
      example = "-devserver akatsuki.gg";
      description = "Default arguments appended to osu!.exe when none are passed on the CLI.";
    };

    extraConfig = mkOption {
      type = types.lines;
      default = "";
      description = "Raw lines appended to the generated env config file.";
    };

    settings = mkOption {
      type = types.attrsOf settingsValueType;
      default = { };
      example = {
        Offset = -35;
        RawInput = true;
        MouseSpeed = 1.0;
        FrameSync = "Unlimited";
        DiscordRichPresence = true;
        VolumeUniversal = 50;
      };
      description = ''
        Declarative osu! in-game settings merged into the per-user config
        (`osu!.<wine-user>.cfg` by default) on Home Manager activation and
        every launch. Only list overrides vs factory defaults — use
        `osu-wine --export-settings` to print them. Unmanaged keys (including
        a locally saved Password hash) are preserved. Never set `Password` here.
      '';
    };

    globalSettings = mkOption {
      type = types.attrsOf settingsValueType;
      default = { };
      example = {
        "_ReleaseStream" = "Stable40";
      };
      description = ''
        Keys merged into the global `osu!.cfg` (release stream, etc.).
        File-integrity `h_*` hashes are left alone unless you set them.
        Never set `Password` here.
      '';
    };

    userConfigFileName = mkOption {
      type = types.str;
      default = "osu!.${config.home.username}.cfg";
      defaultText = literalExpression "\"osu!.\${config.home.username}.cfg\"";
      example = "osu!.alice.cfg";
      description = ''
        Filename under the osu! install directory for per-user settings.
        Matches Wine's Windows username by default (see `home.username`).
      '';
    };

    beatmaps = mkOption {
      type = types.listOf (types.either types.int types.str);
      default = [ ];
      example = [
        75
        1011011
      ];
      description = ''
        Beatmap set IDs to keep installed under `Songs/`. Missing sets are
        downloaded from catboy.best on Home Manager activation and every launch.
        Already-present folders (name starting with the set id) are skipped.
        Failed downloads are warned and skipped so activation still succeeds.
        Use `osu-wine --export-beatmaps` to print installed set IDs as a nix list.
      '';
    };

    skins = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "https://example.com/MySkin.osk" ];
      description = ''
        Direct HTTPS URLs to `.osk` skin archives. Missing skins are downloaded
        and extracted into `Skins/` on Home Manager activation and every launch.
        Each URL is recorded after a successful install so it is not re-fetched.
      '';
    };

    offsetCalculator = {
      enable = mkEnableOption "osu-offset (watch running osu!.exe and recommend Offset from live hit error)";

      package = mkOption {
        type = types.nullOr types.package;
        default = null;
        defaultText = literalExpression "nix-osu-stable.packages.\${pkgs.stdenv.hostPlatform.system}.osu-offset";
        description = ''
          osu-offset package. When you import `nix-osu-stable.homeModules.osu-stable`
          from the flake, this is provided automatically — you do not need to add
          offset-calc-osu-stable to your system flake.
        '';
      };
    };
  };

  config = mkIf cfg.enable (
    let
      formatManifestFile =
        name: entries:
        pkgs.writeText name (
          concatStringsSep "\n" (map toString entries) + lib.optionalString (entries != [ ]) "\n"
        );

      gameSettingsFile =
        if cfg.settings == { } then
          null
        else
          formatSettingsFile "osu-stable-user-settings.cfg" cfg.settings;
      globalSettingsFile =
        if cfg.globalSettings == { } then
          null
        else
          formatSettingsFile "osu-stable-global-settings.cfg" cfg.globalSettings;
      beatmapsFile =
        if cfg.beatmaps == [ ] then null else formatManifestFile "osu-stable-beatmaps.txt" cfg.beatmaps;
      skinsFile = if cfg.skins == [ ] then null else formatManifestFile "osu-stable-skins.txt" cfg.skins;

      envFile = pkgs.writeText "nix-osu-stable.env" (
        concatStringsSep "\n" (
          mapAttrsToList (k: v: "${k}=${escapeShellArg v}") cfg.environment
          ++ lib.optional (cfg.preLaunchArgs != "") "PRE_LAUNCH_ARGS=${escapeShellArg cfg.preLaunchArgs}"
          ++ lib.optional (cfg.postLaunchArgs != "") "POST_LAUNCH_ARGS=${escapeShellArg cfg.postLaunchArgs}"
          ++ lib.optional (cfg.extraConfig != "") cfg.extraConfig
        )
        + "\n"
      );

      finalPackage = cfg.package.override (
        {
          location = cfg.location;
          useGameMode = cfg.gamemode;
          useArrpc = cfg.arrpc;
          configFile = envFile;
          userConfigFileName = cfg.userConfigFileName;
        }
        // lib.optionalAttrs (gameSettingsFile != null) { inherit gameSettingsFile; }
        // lib.optionalAttrs (globalSettingsFile != null) { inherit globalSettingsFile; }
        // lib.optionalAttrs (beatmapsFile != null) { inherit beatmapsFile; }
        // lib.optionalAttrs (skinsFile != null) { inherit skinsFile; }
      );

      applySettings = "${finalPackage.applyGameSettings}/bin/osu-apply-game-settings";
      syncContent = "${finalPackage.syncContent}/bin/osu-sync-content";
      osuDir = "${cfg.location}/osu";
      userCfgPath = "${osuDir}/${cfg.userConfigFileName}";
      globalCfgPath = "${osuDir}/osu!.cfg";
    in
    {
      home.packages = [
        finalPackage
      ]
      ++ lib.optional cfg.arrpc pkgs.arrpc
      ++ lib.optional (
        cfg.offsetCalculator.enable && cfg.offsetCalculator.package != null
      ) cfg.offsetCalculator.package;

      assertions = [
        {
          assertion = cfg.package != null;
          message = ''
            programs.osu-stable.package is unset. Import nix-osu-stable.homeModules.osu-stable
            from the flake (which sets a default), or set package explicitly to
            nix-osu-stable.packages.''${pkgs.stdenv.hostPlatform.system}.osu-wine.
          '';
        }
        {
          assertion = !cfg.offsetCalculator.enable || cfg.offsetCalculator.package != null;
          message = ''
            programs.osu-stable.offsetCalculator.enable is true but package is unset.
            Import nix-osu-stable.homeModules.osu-stable from the flake, or set
            programs.osu-stable.offsetCalculator.package to
            nix-osu-stable.packages.''${pkgs.stdenv.hostPlatform.system}.osu-offset.
          '';
        }
        {
          assertion = secretSettingKeys == [ ];
          message = ''
            programs.osu-stable.settings/globalSettings must not include Password.
            Keep hashed credentials local in the mutable osu!.*.cfg; do not put them in Nix.
          '';
        }
        {
          assertion = lib.all (
            id:
            let
              s = toString id;
            in
            builtins.match "[0-9]+" s != null
          ) cfg.beatmaps;
          message = "programs.osu-stable.beatmaps entries must be numeric beatmap set IDs.";
        }
        {
          assertion = lib.all (url: lib.hasPrefix "http://" url || lib.hasPrefix "https://" url) cfg.skins;
          message = "programs.osu-stable.skins entries must be http(s) URLs to .osk files.";
        }
      ];

      # Keep yawl wine paths in sync with the packaged wine-osu on every activation.
      home.activation.osuStableYawlConfigs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        $DRY_RUN_CMD mkdir -p ${escapeShellArg "${cfg.location}/yawl/configs"}
        $DRY_RUN_CMD sh -c ${escapeShellArg ''
          printf 'exec=%s\n' '${finalPackage.wine-osu}/bin/wine' > '${cfg.location}/yawl/configs/osu.cfg'
          printf 'exec=%s\n' '${finalPackage.wine-osu}/bin/wineserver' > '${cfg.location}/yawl/configs/osuserver.cfg'
          printf '%s' '${finalPackage.wine-osu}' > '${cfg.location}/yawl/.wine-osu'
        ''}
      '';

      # Merge declarative in-game settings when the install dir already exists.
      home.activation.osuStableGameSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] (
        lib.optionalString (gameSettingsFile != null || globalSettingsFile != null) ''
          if [ -d ${escapeShellArg osuDir} ]; then
            ${lib.optionalString (globalSettingsFile != null) ''
              $DRY_RUN_CMD ${escapeShellArg applySettings} ${escapeShellArg globalSettingsFile} ${escapeShellArg globalCfgPath}
            ''}
            ${lib.optionalString (gameSettingsFile != null) ''
              $DRY_RUN_CMD ${escapeShellArg applySettings} ${escapeShellArg gameSettingsFile} ${escapeShellArg userCfgPath}
            ''}
          fi
        ''
      );

      # Download missing beatmaps/skins when the install dir already exists.
      home.activation.osuStableContent = lib.hm.dag.entryAfter [ "writeBoundary" ] (
        lib.optionalString (beatmapsFile != null || skinsFile != null) ''
          if [ -d ${escapeShellArg osuDir} ]; then
            $DRY_RUN_CMD ${escapeShellArg syncContent} \
              ${escapeShellArg (if beatmapsFile != null then beatmapsFile else "/dev/null")} \
              ${escapeShellArg (if skinsFile != null then skinsFile else "/dev/null")} \
              ${escapeShellArg osuDir}
          fi
        ''
      );
    }
  );
}
