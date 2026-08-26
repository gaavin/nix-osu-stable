# shellcheck shell=bash
# Sync declarative beatmaps (set IDs) and skins (.osk URLs) into an osu! install.
#
# Usage: osu-sync-content <beatmaps-manifest> <skins-manifest> <osupath>
# Manifests are plain text, one entry per line (# comments and blanks ignored).
# Pass an empty/missing file to skip that category.
#
# Environment:
#   OSU_SYNC_DRY_RUN=1  Log actions without writing
#
# Beatmaps are fetched with packaged aria2c. Built-in mirrors are probed at
# runtime; missing sets are downloaded in one parallel aria2 run (-x5, -j=N)
# spread across reachable mirrors. Failures retry on the next mirror.
# Skins use a single URL at -x5.

set -euo pipefail

beatmaps_file="${1:-}"
skins_file="${2:-}"
osupath="${3:?osu install directory}"

dry_run="${OSU_SYNC_DRY_RUN:-0}"
UA='nix-osu-stable (https://github.com/gaavin/nix-osu-stable)'
CANARY_ID=75

# Prefer no-video / CheeseGull-style endpoints when a mirror has one.
BEATMAP_MIRRORS=(
  'https://catboy.best/d/{id}n'
  'https://osu.direct/api/d/{id}n'
  'https://api.nerinyan.moe/d/{id}?nv=true'
  'https://beatconnect.io/b/{id}'
  'https://dl.sayobot.cn/beatmaps/download/novideo/{id}'
)

songs_dir="$osupath/Songs"
skins_dir="$osupath/Skins"
state_dir="$osupath/.nix-osu-stable"
synced_skins="$state_dir/synced-skins"
working_mirrors=()

info() { printf 'nix-osu-stable: %s\n' "$*"; }
warn() { printf 'nix-osu-stable: %s\n' "$*" >&2; }

is_dry() { [ "$dry_run" = "1" ]; }

is_zip() {
  local f="$1"
  [ -s "$f" ] && [ "$(head -c 2 "$f")" = "PK" ]
}

mirror_host() {
  local u="$1"
  u="${u#http://}"
  u="${u#https://}"
  printf '%s' "${u%%/*}"
}

# --enable-http-keep-alive=false: aria2 otherwise reuses the TLS session across
# a 302 to a different hostname on the same IP (osu.direct → storage.osu.direct)
# and Cloudflare returns 403.
# --use-head=false: several mirrors stall or lie on HEAD.
# --no-conf: ignore the user's aria2.conf.
aria2_flags=(
  --no-conf
  -x5
  -s5
  --min-split-size=1M
  --file-allocation=none
  --allow-overwrite=true
  --auto-file-renaming=false
  --remove-control-file=true
  --always-resume=false
  --use-head=false
  --enable-http-keep-alive=false
  --max-tries=2
  --retry-wait=1
  --connect-timeout=8
  --timeout=45
  --user-agent="$UA"
  --console-log-level=error
  --summary-interval=0
  --download-result=hide
  --quiet=true
)

aria2_get() {
  local dest="$1" url="$2"
  local dir base
  dir="$(dirname "$dest")"
  base="$(basename "$dest")"
  aria2c "${aria2_flags[@]}" \
    --dir="$dir" \
    --out="$base" \
    "$url"
}

# One aria2 process, all URLs at once (-j = count), -x5 each.
aria2_batch() {
  local input="$1" jobs="$2"
  [ "$jobs" -gt 0 ] || return 0
  aria2c "${aria2_flags[@]}" \
    -j"$jobs" \
    --input-file="$input"
}

probe_one_mirror() {
  local template="$1" out="$2" url tmp
  url="${template//\{id\}/$CANARY_ID}"
  tmp="$(mktemp)"
  curl -sS -L --connect-timeout 4 --max-time 8 \
    -A "$UA" -o "$tmp" "$url" >/dev/null 2>&1 || true
  if [ "$(head -c 2 "$tmp" 2>/dev/null || true)" = "PK" ]; then
    printf '%s\n' "$template" >"$out"
  else
    : >"$out"
  fi
  rm -f "$tmp"
}

probe_mirrors() {
  working_mirrors=()
  if is_dry; then
    working_mirrors=("${BEATMAP_MIRRORS[@]}")
    return 0
  fi
  local probe_dir template i out hosts
  probe_dir="$(mktemp -d)"
  i=0
  for template in "${BEATMAP_MIRRORS[@]}"; do
    out="$probe_dir/$i"
    probe_one_mirror "$template" "$out" &
    i=$((i + 1))
  done
  wait || true
  i=0
  for template in "${BEATMAP_MIRRORS[@]}"; do
    out="$probe_dir/$i"
    if [ -s "$out" ]; then
      working_mirrors+=("$template")
      info "mirror up: $(mirror_host "$template")"
    else
      info "mirror skip: $(mirror_host "$template")"
    fi
    i=$((i + 1))
  done
  rm -rf "$probe_dir"
  if [ "${#working_mirrors[@]}" -eq 0 ]; then
    warn "no beatmap mirrors responded; beatmap sync will be skipped"
    return 0
  fi
  hosts=""
  for template in "${working_mirrors[@]}"; do
    hosts="$hosts $(mirror_host "$template")"
  done
  info "using ${#working_mirrors[@]} beatmap mirror(s):$hosts"
}

download_to() {
  local dest="$1" url="$2" tmp
  if is_dry; then
    info "dry-run: download $url -> $dest"
    return 0
  fi
  tmp="$(mktemp "${dest}.XXXXXX.tmp")"
  if aria2_get "$tmp" "$url" && is_zip "$tmp"; then
    rm -f "${tmp}.aria2"
    mv -f "$tmp" "$dest"
    return 0
  fi
  rm -f "$tmp" "${tmp}.aria2"
  return 1
}

sanitize_component() {
  local s="$1"
  s="$(printf '%s' "$s" | tr -d '\r')"
  s="$(printf '%s' "$s" | sed -E 's/[\/:*?"<>|]+/ /g; s/[[:space:]]+/ /g; s/^ //; s/ $//; s/\.+$//')"
  if [ -z "$s" ]; then
    printf 'unknown'
  else
    printf '%s' "$s"
  fi
}

read_osu_meta() {
  # Prints: artist<TAB>title from the first .osu under $1 (prefer ASCII tags).
  local root="$1" osu artist title artist_u title_u line key val in_meta
  osu="$(find "$root" -type f -name '*.osu' | head -n 1 || true)"
  [ -n "$osu" ] || return 1
  artist=""
  title=""
  artist_u=""
  title_u=""
  in_meta=0
  while IFS= read -r line || [ -n "$line" ]; do
    line="$(printf '%s' "$line" | tr -d '\r')"
    case "$line" in
      \[Metadata\])
        in_meta=1
        continue
        ;;
      \[*\])
        if [ "$in_meta" -eq 1 ]; then
          break
        fi
        continue
        ;;
    esac
    [ "$in_meta" -eq 1 ] || continue
    case "$line" in
      *:*)
        key="${line%%:*}"
        val="${line#*:}"
        key="$(printf '%s' "$key" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
        val="$(printf '%s' "$val" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
        case "$key" in
          Artist) artist="$val" ;;
          ArtistUnicode) artist_u="$val" ;;
          Title) title="$val" ;;
          TitleUnicode) title_u="$val" ;;
        esac
        ;;
    esac
  done <"$osu"
  [ -n "$artist" ] || artist="$artist_u"
  [ -n "$title" ] || title="$title_u"
  [ -n "$artist" ] || artist="Unknown Artist"
  [ -n "$title" ] || title="Unknown Title"
  printf '%s\t%s\n' "$artist" "$title"
}

read_skin_name() {
  local root="$1" ini name line
  ini="$(find "$root" -type f -iname 'skin.ini' | head -n 1 || true)"
  [ -n "$ini" ] || return 1
  name=""
  while IFS= read -r line || [ -n "$line" ]; do
    line="$(printf '%s' "$line" | tr -d '\r')"
    case "$line" in
      [Nn][Aa][Mm][Ee]:*)
        name="${line#*:}"
        name="$(printf '%s' "$name" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
        if [ -n "$name" ]; then
          printf '%s\n' "$name"
          return 0
        fi
        ;;
    esac
  done <"$ini"
  return 1
}

beatmap_present() {
  local id="$1" entry
  [ -d "$songs_dir" ] || return 1
  for entry in "$songs_dir"/*; do
    [ -e "$entry" ] || continue
    case "$(basename "$entry")" in
      "$id" | "$id "*) return 0 ;;
    esac
  done
  [ -f "$songs_dir/${id}.osz" ] && return 0
  return 1
}

install_beatmap_archive() {
  local id="$1" archive="$2" extract meta artist title dest
  extract="$(mktemp -d "$songs_dir/.nix-osu-stable-extract-${id}.XXXXXX")"
  if ! unzip -q -o "$archive" -d "$extract"; then
    warn "failed to extract beatmap set $id"
    rm -rf "$extract"
    return 0
  fi
  if meta="$(read_osu_meta "$extract")"; then
    artist="$(printf '%s' "$meta" | cut -f1)"
    title="$(printf '%s' "$meta" | cut -f2)"
  else
    artist="Unknown Artist"
    title="Unknown Title"
  fi
  artist="$(sanitize_component "$artist")"
  title="$(sanitize_component "$title")"
  dest="$songs_dir/${id} ${artist} - ${title}"
  if [ -e "$dest" ]; then
    info "Beatmap set $id already present as $(basename "$dest")"
    rm -rf "$extract"
    return 0
  fi
  mkdir -p "$dest"
  find "$extract" -mindepth 1 -maxdepth 1 -exec mv -f {} "$dest/" \;
  rm -rf "$extract"
  info "Installed beatmap set $id -> $(basename "$dest")"
}

skin_url_synced() {
  local url="$1"
  [ -f "$synced_skins" ] || return 1
  grep -Fxq "$url" "$synced_skins"
}

mark_skin_synced() {
  local url="$1"
  mkdir -p "$state_dir"
  touch "$synced_skins"
  if ! grep -Fxq "$url" "$synced_skins"; then
    printf '%s\n' "$url" >>"$synced_skins"
  fi
}

install_skin() {
  local url="$1" archive extract_root extract base name dest top_count top
  case "$url" in
    http://* | https://*) ;;
    *)
      warn "skipping invalid skin URL: $url"
      return 0
      ;;
  esac

  if skin_url_synced "$url"; then
    return 0
  fi

  base="$(basename "${url%%\?*}")"
  base="$(printf '%s' "$base" | sed -E 's/\.[Oo][Ss][Kk]$//')"
  base="$(sanitize_component "${base:-skin}")"

  info "Downloading skin"
  info "  from: $url"

  if is_dry; then
    info "dry-run: would install skin from $url into $skins_dir"
    return 0
  fi

  mkdir -p "$skins_dir" "$state_dir"
  archive="$(mktemp "$skins_dir/.nix-osu-stable-skin.XXXXXX.osk")"
  extract_root="$(mktemp -d "$skins_dir/.nix-osu-stable-skin-extract.XXXXXX")"
  extract="$extract_root"

  cleanup_skin() {
    rm -rf "$extract_root"
    rm -f "$archive"
  }

  if ! download_to "$archive" "$url"; then
    warn "failed to download skin: $url"
    cleanup_skin
    return 0
  fi

  if ! unzip -q -o "$archive" -d "$extract_root"; then
    warn "failed to extract skin: $url"
    cleanup_skin
    return 0
  fi

  # Single top-level directory → treat that as the skin root.
  top_count="$(find "$extract_root" -mindepth 1 -maxdepth 1 | wc -l)"
  if [ "$top_count" -eq 1 ]; then
    top="$(find "$extract_root" -mindepth 1 -maxdepth 1)"
    if [ -d "$top" ]; then
      extract="$top"
    fi
  fi

  if name="$(read_skin_name "$extract")"; then
    name="$(sanitize_component "$name")"
  else
    name="$base"
  fi
  dest="$skins_dir/$name"

  if [ -e "$dest" ]; then
    info "Skin already present: $name"
    mark_skin_synced "$url"
    cleanup_skin
    return 0
  fi

  mkdir -p "$dest"
  find "$extract" -mindepth 1 -maxdepth 1 -exec mv -f {} "$dest/" \;
  cleanup_skin
  mark_skin_synced "$url"
  info "Installed skin -> $name"
}

foreach_manifest_line() {
  local file="$1"
  local callback="$2"
  local line
  [ -n "$file" ] || return 0
  [ -r "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line="$(printf '%s' "$line" | tr -d '\r')"
    case "$line" in
      '' | \#*) continue ;;
    esac
    line="$(printf '%s' "$line" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
    [ -n "$line" ] || continue
    "$callback" "$line"
  done <"$file"
}

beatmap_ids=()
collect_beatmap() { beatmap_ids+=("$1"); }

run_beatmaps() {
  local id i n round jobs work input template url hosts
  local -a missing remaining next

  if [ "${#beatmap_ids[@]}" -eq 0 ]; then
    return 0
  fi
  missing=()
  for id in "${beatmap_ids[@]}"; do
    if ! printf '%s' "$id" | grep -Eq '^[0-9]+$'; then
      warn "skipping invalid beatmap set id: $id"
      continue
    fi
    beatmap_present "$id" || missing+=("$id")
  done
  if [ "${#missing[@]}" -eq 0 ]; then
    return 0
  fi

  probe_mirrors
  if [ "${#working_mirrors[@]}" -eq 0 ] && ! is_dry; then
    return 0
  fi

  hosts=""
  for template in "${working_mirrors[@]}"; do
    hosts="$hosts $(mirror_host "$template")"
  done

  if is_dry; then
    info "dry-run: download ${#missing[@]} set(s) across$hosts"
    for id in "${missing[@]}"; do
      info "dry-run: would install beatmap $id into $songs_dir"
    done
    return 0
  fi

  mkdir -p "$songs_dir"
  work="$(mktemp -d "$songs_dir/.nix-osu-stable-dl.XXXXXX")"
  remaining=("${missing[@]}")
  n="${#working_mirrors[@]}"
  round=0
  while [ "${#remaining[@]}" -gt 0 ] && [ "$round" -lt "$n" ]; do
    jobs="${#remaining[@]}"
    info "downloading $jobs set(s) across$hosts (round $((round + 1))/$n)"
    input="$work/aria2.round-$round"
    : >"$input"
    i=0
    for id in "${remaining[@]}"; do
      template="${working_mirrors[$(((i + round) % n))]}"
      url="${template//\{id\}/$id}"
      printf '%s\n  dir=%s\n  out=%s.osz\n' "$url" "$work" "$id" >>"$input"
      i=$((i + 1))
    done
    aria2_batch "$input" "$jobs" || true
    next=()
    for id in "${remaining[@]}"; do
      rm -f "$work/${id}.osz.aria2"
      if is_zip "$work/${id}.osz"; then
        continue
      fi
      rm -f "$work/${id}.osz"
      next+=("$id")
    done
    remaining=("${next[@]}")
    round=$((round + 1))
  done

  for id in "${missing[@]}"; do
    if is_zip "$work/${id}.osz"; then
      install_beatmap_archive "$id" "$work/${id}.osz"
      rm -f "$work/${id}.osz"
    else
      warn "failed to download beatmap set $id (mirrors missing or network error)"
    fi
  done
  rm -rf "$work"
}

mkdir -p "$osupath"
foreach_manifest_line "$beatmaps_file" collect_beatmap
run_beatmaps
foreach_manifest_line "$skins_file" install_skin
