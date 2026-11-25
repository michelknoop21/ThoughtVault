#!/usr/bin/env python3
"""Scores speaker turns against a hand-marked reference.

Usage: score.py reference.rttm hypothesis.(rttm|json)
       score.py --selftest

Prints the share of reference speech time that carries the right speaker,
after the best one-to-one mapping between hypothesis and reference speakers.
Time-weighted, not word-weighted: the reference has no word timings.
"""
import itertools
import json
import sys

FRAME = 0.01  # seconds


def read_rttm(path):
    turns = []
    for line in open(path, encoding="utf-8"):
        p = line.split()
        if len(p) >= 8 and p[0] == "SPEAKER":
            turns.append((float(p[3]), float(p[3]) + float(p[4]), p[7]))
    return turns


def read_json(path):
    """FluidAudio CLI output: any list of objects with start/end seconds and a speaker id."""
    def walk(node):
        if isinstance(node, list):
            for item in node:
                yield from walk(item)
        elif isinstance(node, dict):
            start = node.get("startTimeSeconds", node.get("start"))
            end = node.get("endTimeSeconds", node.get("end"))
            speaker = node.get("speakerId", node.get("speaker"))
            if start is not None and end is not None and speaker is not None:
                yield (float(start), float(end), str(speaker))
            else:
                for value in node.values():
                    yield from walk(value)
    return list(walk(json.load(open(path, encoding="utf-8"))))


def frames(turns):
    """frame index -> speaker; a later turn wins on overlap."""
    out = {}
    for start, end, speaker in turns:
        for i in range(round(start / FRAME), round(end / FRAME)):
            out[i] = speaker
    return out


def score(reference, hypothesis):
    ref, hyp = frames(reference), frames(hypothesis)
    overlap = {}
    for i, speaker in ref.items():
        if i in hyp:
            overlap[(speaker, hyp[i])] = overlap.get((speaker, hyp[i]), 0) + 1
    ref_speakers = sorted(set(ref.values()))
    hyp_speakers = sorted(set(hyp.values()))
    # ponytail: brute-force mapping, fine up to ~8 speakers; use the Hungarian method beyond that.
    padded = hyp_speakers + [None] * max(0, len(ref_speakers) - len(hyp_speakers))
    best = max(
        sum(overlap.get((r, h), 0) for r, h in zip(ref_speakers, perm))
        for perm in itertools.permutations(padded, len(ref_speakers))
    ) if ref_speakers else 0
    return {
        "correct_share": best / len(ref) if ref else 0.0,
        "reference_minutes": len(ref) * FRAME / 60,
        "reference_speakers": len(ref_speakers),
        "hypothesis_speakers": len(hyp_speakers),
    }


def selftest():
    reference = [(0, 10, "a"), (10, 20, "b")]
    assert score(reference, [(0, 10, "x"), (10, 20, "y")])["correct_share"] == 1.0
    assert score(reference, [(0, 20, "x")])["correct_share"] == 0.5
    swapped = score(reference, [(0, 5, "y"), (5, 10, "x"), (10, 20, "y")])
    assert abs(swapped["correct_share"] - 0.75) < 1e-9, swapped
    assert score(reference, [])["correct_share"] == 0.0
    print("selftest ok")


if __name__ == "__main__":
    if sys.argv[1:] == ["--selftest"]:
        selftest()
    elif len(sys.argv) == 3:
        hyp = read_json(sys.argv[2]) if sys.argv[2].endswith(".json") else read_rttm(sys.argv[2])
        print(json.dumps(score(read_rttm(sys.argv[1]), hyp), indent=2))
    else:
        sys.exit(__doc__)
