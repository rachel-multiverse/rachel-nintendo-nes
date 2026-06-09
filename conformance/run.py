#!/usr/bin/env python3
"""RUBP codec conformance for the NES client.

Runs the real client codec from ../src/rubp.asm on a real NES under Emu198x
(emu198x-nes, headless) and checks it against the golden fixtures in
rubp-messages-v1.json — the same vectors the iOS reference and the Go server
validate against. No networking, no running game.

Two phases:

  Encoders (harness.asm) — drive HELLO / PLAY_CARD / DRAW_CARD with the
    fixture's field values and diff the 64-byte message each builds against its
    golden vector. Differing bytes are classified OK-NAME / OK-PLATFORM / GAP /
    BUG / UNEXPECTED.

  Decoders (decoders.asm) — feed the golden WELCOME / GAME_STATE vectors into
    the parsers and check each extracted value against the same vector decoded
    at the spec's offsets (an independent oracle: a parser reading the wrong
    offset fails).

Both harnesses boot straight from the reset vector, run every test into a RAM
capture region, and park; emu198x-nes runs them and memory_reads the regions
back as JSON.

Exit status is non-zero on any BUG / UNEXPECTED / decoder mismatch.

Usage:  python3 run.py
Needs: ca65 + ld65 (cc65), and emu198x-nes (set EMU198X_NES, or it defaults to
       ~/Projects/198x/Emu198x/target/debug/emu198x-nes).
"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BUILD = os.path.join(HERE, "build")
FIXTURES = os.path.join(HERE, "rubp-messages-v1.json")
EMU = os.environ.get(
    "EMU198X_NES",
    os.path.expanduser("~/Projects/198x/Emu198x/target/debug/emu198x-nes"),
)

# ---- Encoder harness (harness.asm) ------------------------------------------
ENC_ROM = os.path.join(BUILD, "harness.nes")
ENC_SLOTS = {"hello": 0x0500, "play_card": 0x0540, "draw_card": 0x0580}
ENC_DONE = 0x05FF

# Per-message, per-offset explanations for known differences from the golden
# vectors. Anything that differs and is NOT listed here is reported UNEXPECTED.
KNOWN = {
    "hello": {
        # The player name is user data; the client sends its own ("NES").
        **{o: ("OK-NAME", "player name vs fixture's 'Alice' (user data)") for o in range(16, 32)},
        33: ("OK-PLATFORM", "platform ID 0x00C0 (NES) vs fixture's 0x0031 (iOS)"),
        # specVersion (34/35) is now emitted; reconnectToken stays a gap (no reclaim).
        **{o: ("GAP", "reconnectToken not emitted (no reconnect support)") for o in range(36, 44)},
    },
    "play_card": {},
    "draw_card": {},
}
FAIL_STATUSES = {"BUG", "UNEXPECTED"}

# ---- Decoder harness (decoders.asm) -----------------------------------------
DEC_ROM = os.path.join(BUILD, "decoders.nes")
DEC_SLOTS = {"welcome": (0x0500, 6), "game_state": (0x0510, 25)}
DEC_DONE = 0x05FF
CONN_WAITING = 3  # parse_welcome sets this


def golden(fixtures, name):
    for m in fixtures["messages"]:
        if m["name"] == name:
            return bytes.fromhex(m["hex"])
    raise KeyError(name)


def assemble(src, rom):
    os.makedirs(BUILD, exist_ok=True)
    obj = os.path.join(BUILD, os.path.splitext(os.path.basename(src))[0] + ".o")
    subprocess.run(["ca65", "-o", obj, src], cwd=HERE, check=True)
    subprocess.run(["ld65", "-o", rom, "-C", "harness.cfg", obj], cwd=HERE, check=True)


def capture(rom, regions, done_addr):
    """Run a harness ROM under emu198x-nes and read back memory regions.

    regions: {name: (addr, length)}. Returns {name: bytes}.
    """
    if not os.path.exists(EMU):
        sys.exit(f"emu198x-nes not found at {EMU}\n"
                 f"build it: cargo build -p emu198x-nes --no-default-features")
    steps = [{"action": "run_frames", "frames": 30},
             {"action": "memory_read", "addr": done_addr, "len": 1}]
    steps += [{"action": "memory_read", "addr": a, "len": n} for a, n in regions.values()]

    script = os.path.join(BUILD, "session.json")
    with open(script, "w") as f:
        json.dump(steps, f)

    out = subprocess.run(
        [EMU, "--headless", "--rom", rom, "--script", script],
        cwd=HERE, check=True, capture_output=True, text=True,
    ).stdout
    reads = {}
    for o in json.loads(out).get("observations", []):
        if o.get("kind") == "memory_read":
            reads[o["addr"]] = bytes(o["bytes"])

    if reads.get(done_addr, b"\0")[:1] != b"\xaa":
        raise RuntimeError("harness did not finish (done marker not set) — try more run_frames")
    return {name: reads[addr] for name, (addr, _length) in regions.items()}


# -----------------------------------------------------------------------------
# Encoder phase
# -----------------------------------------------------------------------------
def check_encoders(fixtures):
    assemble("harness.asm", ENC_ROM)
    got = capture(ENC_ROM, {n: (a, 64) for n, a in ENC_SLOTS.items()}, ENC_DONE)

    print("ENCODERS — message the client builds vs golden vector\n")
    failed = False
    for name in ENC_SLOTS:
        produced, gold = got[name], golden(fixtures, name)
        known = KNOWN.get(name, {})
        diffs = [i for i in range(64) if produced[i] != gold[i]]
        statuses = [(i, *known.get(i, ("UNEXPECTED", "no explanation on file"))) for i in diffs]
        bug = any(s in FAIL_STATUSES for _, s, _ in statuses)
        failed = failed or bug
        verdict = "CONFORMANT" if not diffs else ("FAIL" if bug else "conformant (documented gaps only)")
        print(f"== {name:<10} {verdict} ==")
        if not diffs:
            print("   byte-for-byte match\n")
            continue
        for i, status, note in statuses:
            print(f"   @{i:2d}  NES={produced[i]:02x} golden={gold[i]:02x}  [{status}] {note}")
        print()
    return failed


# -----------------------------------------------------------------------------
# Decoder phase
# -----------------------------------------------------------------------------
def emit_byte_table(label, data):
    lines = [f"{label}:"]
    for i in range(0, len(data), 16):
        lines.append("    .byte " + ", ".join(f"${b:02x}" for b in data[i:i + 16]))
    return "\n".join(lines)


def gen_vectors_inc(fixtures):
    os.makedirs(BUILD, exist_ok=True)
    body = [
        "; Generated by run.py from rubp-messages-v1.json — do not edit.",
        '.segment "RODATA"',
        emit_byte_table("welcome_msg", golden(fixtures, "welcome")),
        emit_byte_table("game_state_msg", golden(fixtures, "game_state")),
        "",
    ]
    with open(os.path.join(BUILD, "vectors.inc"), "w") as f:
        f.write("\n".join(body))


def u16be(b, off):
    return (b[off] << 8) | b[off + 1]


def check_decoders(fixtures):
    gen_vectors_inc(fixtures)
    assemble("decoders.asm", DEC_ROM)
    got = capture(DEC_ROM, DEC_SLOTS, DEC_DONE)

    w = golden(fixtures, "welcome")
    wp = w[16:]   # WELCOME payload
    wc = got["welcome"]
    # Expected values decoded from the golden vector at the SPEC's offsets.
    welcome_checks = [
        ("assignedPlayerID",   wc[0] | (wc[1] << 8), u16be(wp, 0)),
        ("gameID",             wc[2] | (wc[3] << 8), u16be(wp, 2)),
        ("playerCount",        wc[4],                wp[4]),
        ("connState=WAITING",  wc[5],                CONN_WAITING),
    ]

    g = golden(fixtures, "game_state")
    gp = g[16:]   # GAME_STATE payload
    gc = got["game_state"]
    gs_checks = [
        ("currentPlayer", gc[0], gp[0]),
        ("direction",     gc[1], gp[1]),
        ("topCard",       gc[2], gp[2]),
        ("nominatedSuit", gc[3], gp[3]),
        ("pendingDraws",  gc[4], gp[4]),
        ("deckCount",     gc[5], gp[6]),
    ]
    for i in range(8):
        gs_checks.append((f"playerCount[{i}]", gc[6 + i], gp[7 + i]))
    gs_checks += [
        ("isGameOver",  gc[14], gp[15]),
        ("winnerIndex", gc[15], gp[16]),
    ]
    for i in range(8):
        gs_checks.append((f"stateHash[{i}]", gc[16 + i], gp[24 + i]))
    gs_checks.append(("hashValid", gc[24], 1 if (gp[23] & 0x01) else 0))

    print("DECODERS — value the parser extracted vs golden vector at spec offsets\n")
    failed = False
    for name, checks in [("welcome", welcome_checks), ("game_state", gs_checks)]:
        bad = [(label, got_v, want_v) for label, got_v, want_v in checks if got_v != want_v]
        failed = failed or bool(bad)
        print(f"== {name:<10} {'PASS' if not bad else 'FAIL'} ==")
        if bad:
            for label, got_v, want_v in bad:
                print(f"   {label:<18} got={got_v:#04x} want={want_v:#04x}")
        else:
            print(f"   all {len(checks)} fields extracted correctly")
        print()
    return failed


def main():
    fixtures = json.load(open(FIXTURES))
    print(f"RUBP codec conformance — NES client vs {fixtures['fixture']}\n")
    failed = check_encoders(fixtures)
    failed |= check_decoders(fixtures)
    if failed:
        print("RESULT: failures present — see FAIL / [BUG] / [UNEXPECTED] above.")
        sys.exit(1)
    print("RESULT: encoders conformant (platform/name/gaps only); "
          "decoders extract every field correctly.")


if __name__ == "__main__":
    main()
