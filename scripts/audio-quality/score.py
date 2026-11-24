"""Score reviewed paired transcriptions locally; emit metrics, never transcript text.

Input: {"same_model_and_settings": true, "clips": [{"kind": "clean"|"problem",
"reference_reviewed": true, "reference": "...", "original": "...",
"candidate": "...", "original_fact_errors": 0, "candidate_fact_errors": 0}]}.
Fact counts must be manually checked for names, numbers and agreements.
"""
import json
import re
import sys


def word_errors(reference, hypothesis):
    reference, hypothesis = [re.findall(r"\w+", text.casefold()) for text in (reference, hypothesis)]
    if not reference:
        raise ValueError("Reference must contain words")
    row = list(range(len(hypothesis) + 1))
    for i, word in enumerate(reference, 1):
        next_row = [i]
        for j, other in enumerate(hypothesis, 1):
            next_row.append(min(next_row[-1] + 1, row[j] + 1, row[j - 1] + (word != other)))
        row = next_row
    return row[-1], len(reference)


def score(data):
    clips = data["clips"]
    if not clips or {clip["kind"] for clip in clips} != {"clean", "problem"}:
        raise ValueError("Both clean and problem clips are required")
    totals = {kind: [0, 0, 0] for kind in ("clean", "problem")}
    facts_ok = True
    clean_ok = True
    for clip in clips:
        counts = [clip[key] for key in ("original_fact_errors", "candidate_fact_errors")]
        if any(type(count) is not int or count < 0 for count in counts):
            raise ValueError("Reviewed non-negative fact error counts are required")
        facts_ok &= counts[1] <= counts[0]
        original, words = word_errors(clip["reference"], clip["original"])
        candidate, _ = word_errors(clip["reference"], clip["candidate"])
        if clip["kind"] == "clean":
            clean_ok &= (candidate - original) / words <= .01 + 1e-12
        values = totals[clip["kind"]]
        values[0] += original
        values[1] += candidate
        values[2] += words
    metrics = {kind: {"original_wer": a / n, "candidate_wer": b / n, "words": n}
               for kind, (a, b, n) in totals.items()}
    clean, problem = metrics["clean"], metrics["problem"]
    eligible = data.get("same_model_and_settings") is True and all(c.get("reference_reviewed") is True for c in clips)
    improved = problem["original_wer"] > 0 and problem["candidate_wer"] <= problem["original_wer"] * .95
    return {"metrics": metrics, "review_complete": eligible, "critical_facts_ok": facts_ok,
            "passes": eligible and improved and clean_ok and facts_ok}


if __name__ == "__main__":
    with open(sys.argv[1]) as source:
        result = score(json.load(source))
    print(json.dumps(result, indent=2))
    sys.exit(0 if result["passes"] else 1)
