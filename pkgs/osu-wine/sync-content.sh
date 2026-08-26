# shellcheck shell=bash
# Sync declarative beatmaps (catboy.best set IDs) and skins (.osk URLs)
# into an osu! install directory.
#
# Usage: osu-sync-content <beatmaps-manifest> <skins-manifest> <osupath>
# Manifests are plain text, one entry per line (# comments and blanks ignored).
# Pass an empty/missing file to skip that category.
#
# Environment:
#   OSU_BEATMAP_MIRROR  URL template with {id} (default: https://catboy.best/d/{id}n)
#   OSU_SYNC_DRY_RUN=1  Log actions without writing
#
# Downloads use packaged aria2c (-x5). Catboy's /d/{id}n is the no-video
# set archive (much smaller than /d/{id}); append n is their documented
# CheeseGull-compatible download form.

set -euo pipefail

beatmaps_file="${1:-}"
skins_file="${2:-}"
osupath="${3:?osu install directory}"

# Quoted separately: `${var:-https://.../{id}n}` would close on the `}` in `{id}`.
default_mirror='https://catboy.best/d/{id}n'
mirror_template="${OSU_BEATMAP_MIRROR:-$default_mirror}"
dry_run="${OSU_SYNC_DRY_RUN:-0}"

songs_dir="$osupath/Songs"
skins_dir="$osupath/Skins"
state_dir="$osupath/.nix-osu-stable"
synced_skins="$state_dir/synced-skins"

info() { printf 'nix-osu-stable: %s\n' "$*"; }
warn() { printf 'nix-osu-stable: %s\n' "$*" >&2; }

is_dry() { [ "$dry_run" = "1" ]; }

download_to() {
  local url="$1" dest="$2" tmp dir base
  if is_dry; then
    info "dry-run: download $url -> $dest"
    return 0
  fi
  tmp="$(mktemp "${dest}.XXXXXX.tmp")"
  dir="$(dirname "$tmp")"
  base="$(basename "$tmp")"
  # -x5 needs -s5 and a small min-split-size; default 20M would not split typical .osz files.
  # Do not use --use-head: catboy's /d/ front-end often stalls on HEAD.
  if ! aria2c -x5 -s5 \
    --min-split-size=1M \
    --file-allocation=none \
    --allow-overwrite=true \
    --auto-file-renaming=false \
    --remove-control-file=true \
    --always-resume=true \
    --max-tries=5 \
    --retry-wait=2 \
    --connect-timeout=15 \
    --timeout=60 \
    --user-agent="nix-osu-stable (https://github.com/gaavin/nix-osu-stable)" \
    --dir="$dir" \
    --out="$base" \
    --console-log-level=warn \
    --summary-interval=0 \
    --download-result=hide \
    "$url"; then
    rm -f "$tmp" "${tmp}.aria2"
    return 1
  fi
  if [ ! -s "$tmp" ]; then
    rm -f "$tmp" "${tmp}.aria2"
    return 1
  fi
  # .osz / .osk are zip archives
  if [ "$(head -c 2 "$tmp")" != "PK" ]; then
    rm -f "$tmp" "${tmp}.aria2"
    warn "download is not a zip archive: $url"
    return 1
  fi
  rm -f "${tmp}.aria2"
  mv -f "$tmp" "$dest"
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
  local id="$1" url archive extract meta artist title dest
  if ! printf '%s' "$id" | grep -Eq '^[0-9]+$'; then
    warn "skipping invalid beatmap set id: $id"
    return 0
  fi
  if beatmap_present "$id"; then
    return 0
  fi

  url="${mirror_template//\{id\}/$id}"
  info "Downloading beatmap set $id"
  info "  from: $url"

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

  if ! download_to "$url" "$archive"; then
    warn "failed to download beatmap set $id (mirror missing or network error)"
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

  if ! download_to "$url" "$archive"; then
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

mkdir -p "$osupath"
foreach_manifest_line "$beatmaps_file" install_beatmap
foreach_manifest_line "$skins_file" install_skin
