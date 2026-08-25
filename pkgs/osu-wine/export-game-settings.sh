# Print osu!.*.cfg keys that differ from factory defaults as a per-user nix attr.
# Usage: osu-export-game-settings <user.cfg> [factory.cfg] [username]
# Skips secrets, file-integrity hashes, and ephemeral session/version keys.
# Output shape:
#   <username> = {
#     Key = value;
#   };

set -euo pipefail

user_cfg="${1:?user cfg path}"
factory_cfg="${2:-}"
username="${3:-}"

if [ ! -f "$user_cfg" ]; then
  printf 'nix-osu-stable: no user config at %s (change settings in-game and exit once)\n' "$user_cfg" >&2
  exit 1
fi

if [ -z "$username" ]; then
  base="$(basename "$user_cfg")"
  case "$base" in
    osu!.*)
      username="${base#osu!.}"
      username="${username%.cfg}"
      ;;
    *)
      username="${base%.cfg}"
      ;;
  esac
fi

export EXPORT_OSU_USER="$user_cfg"
export EXPORT_OSU_FACTORY="$factory_cfg"
export EXPORT_OSU_USERNAME="$username"

awk '
function trim(s) {
  gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", s)
  return s
}
function norm(v) {
  v = trim(v)
  if (v ~ /^-?[0-9]+\.[0-9]+$/) {
    sub(/0+$/, "", v)
    sub(/\.$/, "", v)
  }
  return v
}
function skip_key(k) {
  lk = tolower(k)
  if (lk == "password" || lk == "savepassword" || lk == "username" || lk == "saveusername")
    return 1
  if (k ~ /^h_/) return 1
  if (k == "BossKeyFirstActivation" || k == "EditorTip" || k == "GuideTips" \
      || k == "LastVersion" || k == "LastVersionPermissionsFailed" || k == "MenuTip" \
      || k == "ScreenshotId" || k == "UpdatePending" || k == "CredentialEndpoint" \
      || k == "ChatLastChannel" || k == "LastPlayMode" || k == "CanForceOptimusCompatibility")
    return 1
  return 0
}
function nix_escape(s,    out, i, c) {
  out = ""
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c == "\\" || c == "\"") out = out "\\" c
    else out = out c
  }
  return out
}
function print_nix(k, v) {
  if (v ~ /^-?[0-9]+([.][0-9]+)?$/)
    printf "    %s = %s;\n", k, v
  else
    printf "    %s = \"%s\";\n", k, nix_escape(v)
}
BEGIN {
  user = ENVIRON["EXPORT_OSU_USER"]
  factory = ENVIRON["EXPORT_OSU_FACTORY"]
  username = ENVIRON["EXPORT_OSU_USERNAME"]

  if (factory != "" && factory != "/dev/null") {
    while ((getline line < factory) > 0) {
      sub(/^\xef\xbb\xbf/, "", line)
      gsub(/\r/, "", line)
      if (line ~ /^[ \t]*$/ || line ~ /^[ \t]*#/) continue
      eq = index(line, "=")
      if (eq < 1) continue
      key = trim(substr(line, 1, eq - 1))
      val = norm(substr(line, eq + 1))
      if (key == "" || skip_key(key)) continue
      factory_vals[key] = val
      has_factory = 1
    }
    close(factory)
  }

  printf "  %s = {\n", username
  while ((getline line < user) > 0) {
    sub(/^\xef\xbb\xbf/, "", line)
    gsub(/\r/, "", line)
    if (line ~ /^[ \t]*$/ || line ~ /^[ \t]*#/) continue
    eq = index(line, "=")
    if (eq < 1) continue
    key = trim(substr(line, 1, eq - 1))
    val = norm(substr(line, eq + 1))
    if (key == "" || skip_key(key)) continue
    if (has_factory && (key in factory_vals) && factory_vals[key] == val) continue
    print_nix(key, val)
  }
  close(user)
  printf "  };\n"
}
'
