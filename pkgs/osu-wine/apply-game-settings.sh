# Apply declarative osu! cfg keys into a target osu!.*.cfg file.
# Usage: apply-game-settings.sh <managed.cfg> <target.cfg>
# - Preserves unmanaged keys (including Password)
# - Refuses to write Password
# - Writes CRLF line endings (osu!stable expects them)

set -euo pipefail

managed="${1:?managed cfg fragment}"
target="${2:?target cfg path}"

if [ ! -r "$managed" ]; then
  exit 0
fi

mkdir -p "$(dirname "$target")"

tmp="$(mktemp "${target}.XXXXXX.tmp")"
trap 'rm -f "$tmp" "$tmp.crlf"' EXIT

if grep -Eiq '^[[:space:]]*Password[[:space:]]*=' "$managed"; then
  printf 'nix-osu-stable: refusing to apply settings: Password must not be managed declaratively\n' >&2
  exit 1
fi

existing_arg=""
if [ -f "$target" ]; then
  existing_arg="$target"
fi

export APPLY_OSU_MANAGED="$managed"
export APPLY_OSU_EXISTING="$existing_arg"

awk '
function trim(s) {
  gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", s)
  return s
}
BEGIN {
  managed = ENVIRON["APPLY_OSU_MANAGED"]
  existing = ENVIRON["APPLY_OSU_EXISTING"]

  while ((getline line < managed) > 0) {
    sub(/^\xef\xbb\xbf/, "", line)
    gsub(/\r/, "", line)
    if (line ~ /^[ \t]*$/ || line ~ /^[ \t]*#/) continue
    eq = index(line, "=")
    if (eq < 1) continue
    key = trim(substr(line, 1, eq - 1))
    val = trim(substr(line, eq + 1))
    if (key == "") continue
    if (tolower(key) == "password") {
      print "nix-osu-stable: refusing to apply settings: Password must not be managed declaratively" > "/dev/stderr"
      exit 1
    }
    managed_keys[key] = 1
    managed_vals[key] = val
    managed_order[++nmanaged] = key
  }
  close(managed)

  if (existing != "") {
    while ((getline line < existing) > 0) {
      sub(/^\xef\xbb\xbf/, "", line)
      gsub(/\r/, "", line)
      if (line ~ /^[ \t]*$/) continue
      eq = index(line, "=")
      if (eq < 1) {
        print line
        continue
      }
      key = trim(substr(line, 1, eq - 1))
      if (key in managed_keys) continue
      print line
    }
    close(existing)
  }

  for (i = 1; i <= nmanaged; i++) {
    key = managed_order[i]
    print key " = " managed_vals[key]
  }
}
' >"$tmp"

# osu!stable uses CRLF
sed 's/$/\r/' "$tmp" >"${tmp}.crlf"
mv -f "${tmp}.crlf" "$target"
