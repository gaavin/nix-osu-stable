# Print installed beatmap set IDs as a nix `beatmaps` list.
# Usage: osu-export-beatmaps <songs-dir>
#
# Reads osu! Songs/ folder names ("{setId} Artist - Title") and pending
# "{setId}.osz" archives. Output is pasteable into programs.osu-stable.

set -euo pipefail

songs_dir="${1:?songs directory}"

if [ ! -d "$songs_dir" ]; then
  printf 'nix-osu-stable: no Songs directory at %s (install/launch osu! once first)\n' "$songs_dir" >&2
  exit 1
fi

collect_ids() {
  local entry base id
  shopt -s nullglob
  for entry in "$songs_dir"/*; do
    base="${entry##*/}"
    if [ -f "$entry" ]; then
      case "$base" in
        *.[Oo][Ss][Zz]) ;;
        *) continue ;;
      esac
    elif [ ! -d "$entry" ] && [ ! -L "$entry" ]; then
      continue
    fi
    id="${base%% *}"
    id="${id%.*}"
    case "$id" in
      '' | *[!0-9]*) continue ;;
    esac
    printf '%s\n' "$id"
  done
}

mapfile -t ids < <(collect_ids | sort -n -u)

if [ "${#ids[@]}" -eq 0 ]; then
  printf '    beatmaps = [ ];\n'
  exit 0
fi

printf '    beatmaps = [\n'
for id in "${ids[@]}"; do
  printf '      %s\n' "$id"
done
printf '    ];\n'
