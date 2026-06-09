#!/usr/bin/env python3
"""RUBP encoder conformance for the NES client.

Runs the real client encoders from ../src/rubp.asm on a real NES under Emu198x
(emu198x-nes, headless) and diffs the messages they build against the golden
fixtures in rubp-messages-v1.json — the same vectors the iOS reference and the
Go server validate against. No networking, no running game.

The harness ROM boots from the reset vector, drives HELLO / PLAY_CARD /
DRAW_CARD with the fixture's field values into a RAM capture region, and parks;
emu198x-nes runs it and memory_reads the regions back as JSON.

Decoders (WELCOME / GAME_STATE) are a follow-up: the NES client has no parsers
or game-state variables yet, so this pass covers the encoders only.

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
ROM = os.path.join(BUILD, "harness.nes")
SCRIPT = os.path.join(BUILD, "session.json")
EMU = os.environ.get(
    "EMU198X_NES",
    os.path.expanduser("~/Projects/198x/Emu198x/target/debug/emu198x-nes"),
)

# Capture addresses — must match harness.asm.
ENC_SLOTS = {"hello": 0x0500, "play_card": 0x0540, "draw_card": 0x0580}
DONE = 0x05FF

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


def golden(fixtures, name):
    for m in fixtures["messages"]:
        if m["name"] == name:
            return bytes.fromhex(m["hex"])
    raise KeyError(name)


def assemble():
    os.makedirs(BUILD, exist_ok=True)
    obj = os.path.join(BUILD, "harness.o")
    subprocess.run(["ca65", "-o", obj, "harness.asm"], cwd=HERE, check=True)
    subprocess.run(["ld65", "-o", ROM, "-C", "harness.cfg", obj], cwd=HERE, check=True)


def capture():
    if not os.path.exists(EMU):
        sys.exit(f"emu198x-nes not found at {EMU}\n"
                 f"build it: cargo build -p emu198x-nes --no-default-features")
    reads = [(DONE, 1)] + [(a, 64) for a in ENC_SLOTS.values()]
    steps = [{"action": "run_frames", "frames": 30}]
    steps += [{"action": "memory_read", "addr": a, "len": n} for a, n in reads]
    with open(SCRIPT, "w") as f:
        json.dump(steps, f)

    out = subprocess.run(
        [EMU, "--headless", "--rom", ROM, "--script", SCRIPT],
        cwd=HERE, check=True, capture_output=True, text=True,
    ).stdout
    got = {}
    for o in json.loads(out).get("observations", []):
        if o.get("kind") == "memory_read":
            got[o["addr"]] = bytes(o["bytes"])
    if got.get(DONE, b"\0")[:1] != b"\xaa":
        raise RuntimeError("harness did not finish (done marker not set) — try more run_frames")
    return got


def main():
    fixtures = json.load(open(FIXTURES))
    assemble()
    got = capture()

    print(f"RUBP encoder conformance — NES client vs {fixtures['fixture']}\n")
    failed = False
    for name, addr in ENC_SLOTS.items():
        produced, gold = got[addr], golden(fixtures, name)
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

    if failed:
        print("RESULT: bugs/unexpected differences present — see [BUG]/[UNEXPECTED] above.")
        sys.exit(1)
    print("RESULT: encoders conformant; differences are platform identity, player name, or documented gaps.")


if __name__ == "__main__":
    main()
