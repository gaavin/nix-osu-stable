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
# runtime; every reachable mirror is used in parallel at -x5. First finished
# valid .osz wins. Skins use a single URL at -x5.

set -euo pipefail

beatmaps_file="${1:-}"
skins_file="${2:-}"
osupath="${3:?osu install directory}"

dry_run="${OSU_SYNC_DRY_RUN:-0}"
UA='nix-osu-stable (https://github.com/gaavin/nix-osu-stable)'
CANARY_ID=75
MAP_JOBS=6

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
aria2_get() {
  local dest="$1"
  shift
  local dir base split
  dir="$(dirname "$dest")"
  base="$(basename "$dest")"
  split=$((5 * $#))
  [ "$split" -lt 5 ] && split=5
  aria2c --no-conf \
    -x5 -s"$split" \
    --min-split-size=1M \
    --file-allocation=none \
    --allow-overwrite=true \
    --auto-file-renaming=false \
    --remove-control-file=true \
    --always-resume=false \
    --use-head=false \
    --enable-http-keep-alive=false \
    --max-tries=3 \
    --retry-wait=1 \
    --connect-timeout=8 \
    --timeout=45 \
    --user-agent="$UA" \
    --dir="$dir" \
    --out="$base" \
    --console-log-level=warn \
    --summary-interval=0 \
    --download-result=hide \
    "$@"
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

# Download $dest from one or more URLs. Multiple URLs are raced in parallel,
# each at -x5; the first finished zip wins and the rest are killed.
download_to() {
  local dest="$1"
  shift
  local url tmp work i winner pid st f
  local -a pids

  if is_dry; then
    for url in "$@"; do
      info "dry-run: download $url -> $dest"
    done
    return 0
  fi

  if [ "$#" -eq 0 ]; then
    return 1
  fi

  if [ "$#" -eq 1 ]; then
    tmp="$(mktemp "${dest}.XXXXXX.tmp")"
    if aria2_get "$tmp" "$1" && is_zip "$tmp"; then
      rm -f "${tmp}.aria2"
      mv -f "$tmp" "$dest"
      return 0
    fi
    rm -f "$tmp" "${tmp}.aria2"
    return 1
  fi

  work="$(mktemp -d "${dest}.XXXXXX.race")"
  pids=()
  i=0
  for url in "$@"; do
    aria2_get "$work/p$i" "$url" >/dev/null 2>&1 &
    pids+=("$!")
    i=$((i + 1))
  done

  winner=""
  while [ -z "$winner" ]; do
    local alive=0
    for i in "${!pids[@]}"; do
      pid="${pids[$i]}"
      [ "$pid" != "0" ] || continue
      if kill -0 "$pid" 2>/dev/null; then
        alive=1
        continue
      fi
      st=0
      wait "$pid" || st=$?
      pids[$i]=0
      f="$work/p$i"
      if [ "$st" -eq 0 ] && is_zip "$f"; then
        winner="$f"
        break
      fi
    done
    if [ -n "$winner" ]; then
      break
    fi
    if [ "$alive" -eq 0 ]; then
      break
    fi
    sleep 0.05
  done

  for i in "${!pids[@]}"; do
    pid="${pids[$i]}"
    if [ "$pid" != "0" ]; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  done

  if [ -n "$winner" ]; then
    mv -f "$winner" "$dest"
    rm -rf "$work"
    return 0
  fi
  rm -rf "$work"
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

install_beatmap() {
  local id="$1" archive extract meta artist title dest
  local -a urls
  local template host_list

  if ! printf '%s' "$id" | grep -Eq '^[0-9]+$'; then
    warn "skipping invalid beatmap set id: $id"
    return 0
  fi
  if beatmap_present "$id"; then
    return 0
  fi
  if [ "${#working_mirrors[@]}" -eq 0 ]; then
    return 0
  fi

  urls=()
  host_list=""
  for template in "${working_mirrors[@]}"; do
    urls+=("${template//\{id\}/$id}")
    host_list="$host_list $(mirror_host "$template")"
  done

  info "Downloading beatmap set $id"
  info "  mirrors:$host_list"

  if is_dry; then
    info "dry-run: would install beatmap $id into $songs_dir"
    return 0
  fi

  mkdir -p "$songs_dir"
  archive="$(mktemp "$songs_dir/.nix-osu-stable-${id}.XXXXXX.osz")"
  extract="$(mktemp -d "$songs_dir/.nix-osu-stable-extract-${id}.XXXXXX")"

  cleanup_beatmap() {
    rm -rf "$extract"
    rm -f "$archive"
  }

  if ! download_to "$archive" "${urls[@]}"; then
    warn "failed to download beatmap set $id (mirrors missing or network error)"
    cleanup_beatmap
    return 0
  fi

  if ! unzip -q -o "$archive" -d "$extract"; then
    warn "failed to extract beatmap set $id"
    cleanup_beatmap
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
    cleanup_beatmap
    return 0
  fi

  mkdir -p "$dest"
  find "$extract" -mindepth 1 -maxdepth 1 -exec mv -f {} "$dest/" \;
  rm -rf "$extract"
  rm -f "$archive"
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
  local id missing=0 running=0
  if [ "${#beatmap_ids[@]}" -eq 0 ]; then
    return 0
  fi
  for id in "${beatmap_ids[@]}"; do
    if ! beatmap_present "$id"; then
      missing=1
      break
    fi
  done
  if [ "$missing" -eq 0 ]; then
    return 0
  fi
  probe_mirrors
  if [ "${#working_mirrors[@]}" -eq 0 ] && ! is_dry; then
    return 0
  fi
  if is_dry || [ "${#beatmap_ids[@]}" -eq 1 ] || [ "$MAP_JOBS" -le 1 ]; then
    for id in "${beatmap_ids[@]}"; do
      install_beatmap "$id"
    done
    return 0
  fi
  for id in "${beatmap_ids[@]}"; do
    if [ "$running" -ge "$MAP_JOBS" ]; then
      wait -n || true
      running=$((running - 1))
    fi
    install_beatmap "$id" &
    running=$((running + 1))
  done
  wait || true
}

mkdir -p "$osupath"
foreach_manifest_line "$beatmaps_file" collect_beatmap
run_beatmaps
foreach_manifest_line "$skins_file" install_skin
