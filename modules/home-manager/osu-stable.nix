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
in
{
  options.programs.osu-stable = {
    enable = mkEnableOption "osu!stable (wine-osu + yawl via nix-osu-stable)";

    package = mkOption {
      type = types.nullOr types.package;
      default = null;
      example = literalExpression "inputs.nix-osu-stable.packages.\${pkgs.system}.osu-wine";
      description = "osu-wine package from nix-osu-stable (required when enable is true).";
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

    environment = mkOption {
      type = types.attrsOf types.str;
      default = {
        WINENTSYNC = "1";
        WINEFSYNC = "1";
        WINEESYNC = "1";
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
  };

  config = mkIf cfg.enable (
    let
      envFile = pkgs.writeText "nix-osu-stable.env" (
        concatStringsSep "\n" (
          mapAttrsToList (k: v: "${k}=${escapeShellArg v}") cfg.environment
          ++ lib.optional (cfg.preLaunchArgs != "") "PRE_LAUNCH_ARGS=${escapeShellArg cfg.preLaunchArgs}"
          ++ lib.optional (cfg.postLaunchArgs != "") "POST_LAUNCH_ARGS=${escapeShellArg cfg.postLaunchArgs}"
          ++ lib.optional (cfg.extraConfig != "") cfg.extraConfig
        )
        + "\n"
      );

      finalPackage = cfg.package.override {
        location = cfg.location;
        useGameMode = cfg.gamemode;
        configFile = envFile;
      };
    in
    {
      assertions = [
        {
          assertion = cfg.package != null;
          message = "programs.osu-stable.package must be set (pass nix-osu-stable.packages.\${system}.osu-wine).";
        }
      ];

      home.packages = [ finalPackage ];

      # Keep yawl wine paths in sync with the packaged wine-osu on every activation.
      home.activation.osuStableYawlConfigs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        $DRY_RUN_CMD mkdir -p ${escapeShellArg "${cfg.location}/yawl/configs"}
        $DRY_RUN_CMD sh -c ${escapeShellArg ''
          printf 'exec=%s\n' '${finalPackage.wine-osu}/bin/wine' > '${cfg.location}/yawl/configs/osu.cfg'
          printf 'exec=%s\n' '${finalPackage.wine-osu}/bin/wineserver' > '${cfg.location}/yawl/configs/osuserver.cfg'
          printf '%s' '${finalPackage.wine-osu}' > '${cfg.location}/yawl/.wine-osu'
        ''}
      '';
    }
  );
}
