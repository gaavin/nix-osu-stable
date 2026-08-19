#!/usr/bin/env python3
"""Audio-stack inspector and osu!stable hit-error helper for nix-osu-stable.

Estimates PipeWire/winepipewire period latency, reads the in-game Universal
Offset from osu!.*.cfg, and (optionally) infers remaining offset from a
standard-mode replay + beatmap by matching keydowns to hit circles.
"""

from __future__ import annotations

import argparse
import hashlib
import lzma
import math
import os
import re
import statistics
import struct
import sys
from pathlib import Path
from typing import Iterable

KEY_CLICK = 1 | 2 | 4 | 8  # M1, M2, K1, K2
MOD_DT = 64
MOD_HT = 256
MOD_NC = 512
MOD_RELAX = 128
MOD_AUTO = 2048
MOD_AUTOPILOT = 8192
MOD_CINEMA = 4194304

# winepulse-era starting point from osu-winello / this README historically.
PULSE_OFFSET_NORMAL = (-40, -35)
PULSE_OFFSET_COMPAT = (-25, -25)
# winepipewire.drv testers (osu-winello#256): ~5 ms less on Offset Wizard.
PIPEWIRE_OFFSET_DELTA_MS = 5


class Replay:
    def __init__(self) -> None:
        self.mode = 0
        self.version = 0
        self.beatmap_hash = ""
        self.player = ""
        self.mods = 0
        self.n300 = 0
        self.n100 = 0
        self.n50 = 0
        self.nmiss = 0
        self.frames: list[tuple[int, int]] = []  # (time_ms, keys)


def _uleb128(data: bytes, offset: int) -> tuple[int, int]:
    result = 0
    shift = 0
    while True:
        byte = data[offset]
        offset += 1
        result |= (byte & 0x7F) << shift
        if byte & 0x80 == 0:
            return result, offset
        shift += 7


def _unpack_osu_string(data: bytes, offset: int) -> tuple[str, int]:
    flag = data[offset]
    offset += 1
    if flag == 0x00:
        return "", offset
    if flag != 0x0B:
        raise ValueError(f"invalid osu string flag 0x{flag:02x}")
    length, offset = _uleb128(data, offset)
    s = data[offset : offset + length].decode("utf-8")
    return s, offset + length


def parse_osr(path: Path) -> Replay:
    data = path.read_bytes()
    off = 0
    r = Replay()
    r.mode = data[off]
    off += 1
    r.version = struct.unpack_from("<I", data, off)[0]
    off += 4
    r.beatmap_hash, off = _unpack_osu_string(data, off)
    r.player, off = _unpack_osu_string(data, off)
    _replay_hash, off = _unpack_osu_string(data, off)
    r.n300, r.n100, r.n50 = struct.unpack_from("<HHH", data, off)
    off += 6
    _geki, _katu, r.nmiss = struct.unpack_from("<HHH", data, off)
    off += 6
    off += 4  # score
    off += 2  # combo
    off += 1  # perfect
    r.mods = struct.unpack_from("<I", data, off)[0]
    off += 4
    _life, off = _unpack_osu_string(data, off)
    off += 8  # timestamp
    replay_len = struct.unpack_from("<I", data, off)[0]
    off += 4
    raw = lzma.decompress(data[off : off + replay_len], format=lzma.FORMAT_AUTO)
    r.frames = _parse_frames(raw.decode("ascii"))
    return r


def _parse_frames(payload: str) -> list[tuple[int, int]]:
    payload = payload.rstrip(",")
    t = 0
    frames: list[tuple[int, int]] = []
    events = payload.split(",") if payload else []
    for i, event in enumerate(events):
        parts = event.split("|")
        if len(parts) < 4:
            continue
        delta = int(float(parts[0]))
        if delta == -12345 and i == len(events) - 1:
            continue
        x = float(parts[1])
        y = float(parts[2])
        keys = int(float(parts[3]))
        t += delta
        if i < 2 and x == 256 and y == -500:
            continue
        frames.append((t, keys))
    return frames


def keydowns(frames: Iterable[tuple[int, int]]) -> list[int]:
    prev = 0
    downs: list[int] = []
    for t, keys in frames:
        click = keys & KEY_CLICK
        if click and not (prev & KEY_CLICK):
            downs.append(t)
        prev = keys
    return downs


def parse_circles(osu_text: str) -> tuple[list[int], float]:
    """Return (circle times ms, overall difficulty)."""
    od = 5.0
    in_diff = False
    in_objects = False
    times: list[int] = []
    for line in osu_text.splitlines():
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            in_diff = stripped.lower() == "[difficulty]"
            in_objects = stripped.lower() == "[hitobjects]"
            continue
        if in_diff and stripped.lower().startswith("overalldifficulty"):
            od = float(stripped.split(":", 1)[1].strip())
        if not in_objects or not stripped:
            continue
        parts = stripped.split(",")
        if len(parts) < 4:
            continue
        t = int(float(parts[2]))
        obj_type = int(parts[3])
        if obj_type & 1:  # hit circle (new combo bit may also be set)
            times.append(t)
    return times, od


def clock_rate(mods: int) -> float:
    if mods & MOD_HT:
        return 0.75
    if mods & (MOD_DT | MOD_NC):
        return 1.5
    return 1.0


def match_errors(
    circle_times: list[int],
    downs: list[int],
    rate: float,
    window_ms: float = 400.0,
) -> list[float]:
    scaled = [c * rate for c in circle_times]
    used: set[int] = set()
    errors: list[float] = []
    for ct in scaled:
        best_i = None
        best_abs = window_ms + 1
        for i, dt in enumerate(downs):
            if i in used:
                continue
            err = dt - ct
            a = abs(err)
            if a <= window_ms and a < best_abs:
                best_abs = a
                best_i = i
        if best_i is not None:
            used.add(best_i)
            errors.append(downs[best_i] - ct)
    return errors


def summarize(errors: list[float]) -> dict[str, float]:
    if not errors:
        return {}
    return {
        "n": float(len(errors)),
        "mean": statistics.fmean(errors),
        "median": float(statistics.median(errors)),
        "stdev": float(statistics.stdev(errors)) if len(errors) > 1 else 0.0,
        "late_pct": 100.0 * sum(1 for e in errors if e > 0) / len(errors),
    }


def parse_quantum(value: str | None, default: int = 128) -> int:
    if not value:
        return default
    m = re.match(r"^\s*(\d+)", value)
    if not m:
        return default
    n = int(m.group(1))
    return n if 16 <= n <= 8192 else default


def period_ms(quantum: int, rate: int = 48000) -> float:
    return 1000.0 * quantum / rate


def recommended_offset(driver: str) -> tuple[tuple[int, int], tuple[int, int], str]:
    driver = (driver or "").lower()
    if "pipewire" in driver:
        lo, hi = PULSE_OFFSET_NORMAL
        nlo, nhi = lo + PIPEWIRE_OFFSET_DELTA_MS, hi + PIPEWIRE_OFFSET_DELTA_MS
        clo, chi = PULSE_OFFSET_COMPAT[0] + PIPEWIRE_OFFSET_DELTA_MS, PULSE_OFFSET_COMPAT[1] + PIPEWIRE_OFFSET_DELTA_MS
        note = (
            "winepipewire.drv skips the Pulse compatibility layer. testers on the "
            "11.12-3/osu-winello#256 build measured ~5 ms less delay on Offset Wizard "
            "than winepulse — not a 20–30 ms miracle. leftover offset is still osu!/WASAPI/Wine."
        )
        return (nlo, nhi), (clo, chi), note
    note = "winepulse path: keep the classic osu-winello starting offsets."
    return PULSE_OFFSET_NORMAL, PULSE_OFFSET_COMPAT, note


def read_osu_cfg_offset(osu_path: Path) -> tuple[Path | None, int | None, dict[str, str]]:
    keys: dict[str, str] = {}
    cfgs = sorted(osu_path.glob("osu!.*.cfg"), key=lambda p: p.stat().st_mtime, reverse=True)
    if not cfgs:
        plain = osu_path / "osu!.cfg"
        cfgs = [plain] if plain.is_file() else []
    chosen = cfgs[0] if cfgs else None
    offset = None
    if chosen is None:
        return None, None, keys
    text = chosen.read_text(encoding="utf-8", errors="replace")
    for line in text.splitlines():
        if "=" not in line or line.lstrip().startswith("#"):
            continue
        k, v = line.split("=", 1)
        k, v = k.strip(), v.strip()
        if re.search(r"offset|compat|audio", k, re.I):
            keys[k] = v
        if k.lower() == "offset":
            try:
                offset = int(float(v))
            except ValueError:
                pass
    return chosen, offset, keys


def find_beatmap(songs: Path, md5: str) -> Path | None:
    want = md5.lower()
    if not songs.is_dir() or not want:
        return None
    for dirpath, _dirs, files in os.walk(songs):
        for name in files:
            if not name.endswith(".osu"):
                continue
            p = Path(dirpath) / name
            digest = hashlib.md5(p.read_bytes()).hexdigest()
            if digest.lower() == want:
                return p
    return None


def latest_osr(osu_path: Path) -> Path | None:
    candidates: list[Path] = []
    for folder in (osu_path / "Replays", osu_path / "Data" / "r"):
        if folder.is_dir():
            candidates.extend(folder.glob("*.osr"))
    if not candidates:
        return None
    return max(candidates, key=lambda p: p.stat().st_mtime)


def analyze_replay(osr_path: Path, beatmap: Path) -> dict:
    replay = parse_osr(osr_path)
    if replay.mode != 0:
        raise SystemExit(f"only osu!standard replays are supported (mode={replay.mode})")
    banned = replay.mods & (MOD_RELAX | MOD_AUTO | MOD_AUTOPILOT | MOD_CINEMA)
    if banned:
        raise SystemExit("replay uses relax/auto/autopilot/cinema; hit-error is not meaningful")
    circles, od = parse_circles(beatmap.read_text(encoding="utf-8", errors="replace"))
    rate = clock_rate(replay.mods)
    downs = keydowns(replay.frames)
    errors = match_errors(circles, downs, rate)
    stats = summarize(errors)
    window_300 = max(0.0, 80.0 - 6.0 * od) / rate
    return {
        "replay": replay,
        "circles": len(circles),
        "downs": len(downs),
        "od": od,
        "rate": rate,
        "window_300_ms": window_300,
        "errors": errors,
        "stats": stats,
    }


def print_latency_report(args: argparse.Namespace) -> int:
    driver = os.environ.get("WINE_AUDIO_DRIVER", "")
    pw_q = parse_quantum(os.environ.get("WINE_PIPEWIRE_QUANTUM") or os.environ.get("PIPEWIRE_QUANTUM"))
    rate = 48000
    m = re.search(r"/(\d+)", os.environ.get("PIPEWIRE_QUANTUM") or "")
    if m:
        rate = int(m.group(1))
    pms = period_ms(pw_q, rate)
    normal, compat, note = recommended_offset(driver)

    print("nix-osu-stable latency")
    print(f"  WINE_AUDIO_DRIVER     = {driver or '(unset → wine default, usually pulse)'}")
    print(f"  WINE_PIPEWIRE_QUANTUM = {os.environ.get('WINE_PIPEWIRE_QUANTUM', '(unset, driver default 128)')}")
    print(f"  PIPEWIRE_QUANTUM      = {os.environ.get('PIPEWIRE_QUANTUM', '(unset)')}")
    print(f"  period (quantum/rate) = {pms:.2f} ms  ({pw_q}/{rate})")
    print()
    print(f"  {note}")
    print()
    print("  Start here, then fine-tune with Options → Audio → Offset / Offset Wizard:")
    print(f"    normal mode:               {normal[0]} to {normal[1]} ms")
    print(f"    audio compatibility mode:  {compat[0]} to {compat[1]} ms")
    print()
    print("  Period math is only the PipeWire buffer. osu! still needs tens of ms of")
    print("  Universal Offset on Wine; dropping quantum from 128 → 64 saves ~1.3 ms,")
    print("  not 20 ms. If audio crackles, raise WINE_PIPEWIRE_QUANTUM (and matching")
    print("  PipeWire min quantum) toward 128 or 256.")

    osu_path = Path(args.osu_path).expanduser() if args.osu_path else None
    if osu_path and osu_path.is_dir():
        cfg, offset, extra = read_osu_cfg_offset(osu_path)
        print()
        if cfg:
            print(f"  osu config: {cfg}")
            print(f"  Universal Offset = {offset if offset is not None else '(not set)'}")
            for k, v in extra.items():
                if k.lower() != "offset":
                    print(f"  {k} = {v}")
        else:
            print(f"  no osu!.*.cfg under {osu_path} yet (launch the game once)")

    _try_pw_dump()
    return 0


def _try_pw_dump() -> None:
    """Best-effort live PipeWire quantum if pw-cli/pw-metadata exists."""
    import shutil
    import subprocess

    meta = shutil.which("pw-metadata")
    if not meta:
        print()
        print("  live PipeWire: pw-metadata not on PATH (install pipewire tools to inspect)")
        return
    try:
        out = subprocess.run(
            [meta, "-n", "settings"],
            check=False,
            capture_output=True,
            text=True,
            timeout=3,
        )
    except (OSError, subprocess.TimeoutExpired):
        return
    print()
    print("  pw-metadata -n settings:")
    for line in (out.stdout or "").splitlines():
        if "clock" in line.lower() or "quantum" in line.lower() or "rate" in line.lower():
            print(f"    {line.strip()}")


def print_hiterror(args: argparse.Namespace) -> int:
    osu_path = Path(args.osu_path).expanduser() if args.osu_path else Path(".")
    osr_arg = args.replay or args.replay_file
    osr = Path(osr_arg).expanduser() if osr_arg else latest_osr(osu_path)
    if osr is None or not osr.is_file():
        print("no .osr found; pass a replay path or play a map first (Replays/)", file=sys.stderr)
        return 1
    print(f"replay: {osr}")
    r = parse_osr(osr)
    print(f"  player={r.player}  mode={r.mode}  mods={r.mods}  300/100/50/miss={r.n300}/{r.n100}/{r.n50}/{r.nmiss}")
    print(f"  beatmap md5={r.beatmap_hash}")
    beatmap = Path(args.beatmap).expanduser() if args.beatmap else None
    if beatmap is None:
        print("  searching Songs/ for matching .osu (md5)…")
        beatmap = find_beatmap(osu_path / "Songs", r.beatmap_hash)
    if beatmap is None:
        print("  beatmap not found. pass --beatmap path/to/map.osu", file=sys.stderr)
        return 1
    print(f"  beatmap: {beatmap}")
    result = analyze_replay(osr, beatmap)
    stats = result["stats"]
    print(f"  circles={result['circles']} keydowns={result['downs']} OD={result['od']:.1f} rate={result['rate']}")
    if not stats:
        print("  no circle/keydown pairs inside ±400 ms")
        return 1
    mean = stats["mean"]
    print(
        f"  signed hit error: mean={mean:+.1f} ms  median={stats['median']:+.1f} ms  "
        f"stdev={stats['stdev']:.1f} ms  n={int(stats['n'])}  late={stats['late_pct']:.0f}%"
    )
    print("  (positive mean = hits late vs circles → more negative Universal Offset)")
    _, current, _ = read_osu_cfg_offset(osu_path)
    adj = int(round(mean))
    if current is not None:
        print(f"  current Offset={current}  suggested starting point={current - adj}")
    else:
        print(f"  suggested Offset change: {-adj:+d} ms (subtract the mean error)")
    print("  this includes human error — confirm with Offset Wizard on a sparse map.")
    return 0


def _pack_string(s: str) -> bytes:
    if not s:
        return b"\x00"
    raw = s.encode("utf-8")
    n = len(raw)
    uleb = bytearray()
    while True:
        byte = n & 0x7F
        n >>= 7
        if n:
            uleb.append(byte | 0x80)
        else:
            uleb.append(byte)
            break
    return b"\x0b" + bytes(uleb) + raw


def _self_test() -> int:
    # One circle at 1000 ms, keydown at 1012 ms → +12 ms late.
    osu = "[Difficulty]\nOverallDifficulty:5\n[HitObjects]\n256,192,1000,1,0,0:0:0:0:\n"
    circles, od = parse_circles(osu)
    assert circles == [1000], circles
    assert od == 5.0
    frames = [(0, 0), (1012, 5), (1020, 0)]
    downs = keydowns(frames)
    assert downs == [1012], downs
    errs = match_errors(circles, downs, 1.0)
    assert errs == [12.0], errs
    s = summarize(errs)
    assert math.isclose(s["mean"], 12.0)
    assert parse_quantum("64/48000") == 64
    assert math.isclose(period_ms(128), 1000 * 128 / 48000)
    n, c, _note = recommended_offset("pipewire")
    assert n == (-35, -30), n
    assert c == (-20, -20), c
    n2, _, _ = recommended_offset("pulse")
    assert n2 == (-40, -35)
    # DT: object 1000 ms at 1.5x → 1500 ms clock; press at 1505 → +5
    errs_dt = match_errors([1000], [1505], 1.5)
    assert errs_dt == [5.0], errs_dt

    payload = "0|256|-500|0,0|256|-500|0,1012|128|128|5,"
    compressed = lzma.compress(payload.encode("ascii"), format=lzma.FORMAT_ALONE)
    blob = bytearray()
    blob.append(0)  # std
    blob += struct.pack("<I", 20260819)
    blob += _pack_string("deadbeefcafebabe")
    blob += _pack_string("tester")
    blob += _pack_string("replayhash")
    blob += struct.pack("<HHHHHH", 1, 0, 0, 0, 0, 0)
    blob += struct.pack("<I", 100000)
    blob += struct.pack("<H", 1)
    blob.append(1)
    blob += struct.pack("<I", 0)
    blob += _pack_string("")
    blob += struct.pack("<q", 0)
    blob += struct.pack("<I", len(compressed))
    blob += compressed
    blob += struct.pack("<q", 0)
    tmp = Path("/tmp/nix-osu-stable-selftest.osr")
    tmp.write_bytes(blob)
    parsed = parse_osr(tmp)
    tmp.unlink(missing_ok=True)
    assert parsed.player == "tester"
    assert parsed.beatmap_hash == "deadbeefcafebabe"
    assert keydowns(parsed.frames) == [1012], parsed.frames
    print("osu-latency self-test: ok")
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--osu-path", default=os.environ.get("OSUPATH", ""), help="osu! game directory")
    p.add_argument("--replay", help=".osr to analyse (default: newest under Replays/)")
    p.add_argument(
        "replay_file",
        nargs="?",
        help="optional .osr path (same as --replay)",
    )
    p.add_argument("--beatmap", help=".osu file; default is md5 search in Songs/")
    p.add_argument("--hiterror", action="store_true", help="analyse a replay instead of the stack summary")
    p.add_argument("--self-test", action="store_true")
    args = p.parse_args(argv)
    if args.self_test:
        return _self_test()
    if args.hiterror or args.replay or args.replay_file:
        return print_hiterror(args)
    return print_latency_report(args)


if __name__ == "__main__":
    sys.exit(main())
