#!/usr/bin/env python3
"""Word error rate of a transcript against a reference transcript.

    wer.py REFERENCE.txt HYPOTHESIS.txt [HYPOTHESIS.txt ...]

Speaker labels at the start of a line ("Naam:", "Spreker 2:") and filler words are dropped from both
texts, case and punctuation are ignored. Prints numbers only, never transcript text, unless --names is
given: then it lists the reference names the hypothesis misses.
"""
import argparse
import re

LABEL = re.compile(r'(?m)^[^:\n]{1,40}:\s')
FILLER = {'eh', 'ehm', 'uh', 'uhm', 'hm', 'hmm', 'mm'}


def words(text):
    return [w for w in re.findall(r"[0-9a-zà-ÿ]+", LABEL.sub('', text).lower()) if w not in FILLER]


def errors(ref, hyp):
    """Substitutions, deletions and insertions of the cheapest word alignment."""
    row = [(j, 0, 0, j) for j in range(len(hyp) + 1)]  # (cost, substitutions, deletions, insertions)
    for i, r in enumerate(ref, 1):
        new = [(i, 0, i, 0)]
        for j, h in enumerate(hyp, 1):
            c, s, d, n = row[j - 1]
            best = (c, s, d, n) if r == h else (c + 1, s + 1, d, n)
            c, s, d, n = row[j]
            if c + 1 < best[0]:
                best = (c + 1, s, d + 1, n)
            c, s, d, n = new[j - 1]
            if c + 1 < best[0]:
                best = (c + 1, s, d, n + 1)
            new.append(best)
        row = new
    return row[-1][1:]


def names(text):
    """Capitalised words that do not start a sentence and occur at least twice."""
    found = re.findall(r"(?<![.!?:]\s)(?<!^)\b[A-ZÀ-Ý][a-zà-ÿ]{2,}(?:-[A-Z][a-zà-ÿ]+)?\b", LABEL.sub('', text), re.M)
    return sorted({n for n in found if found.count(n) >= 2})


def long_runs(text, limit=60):
    return sum(len(part.split()) > limit for part in re.split(r'[.!?]', LABEL.sub('', text)))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('reference')
    parser.add_argument('hypotheses', nargs='+')
    parser.add_argument('--names', action='store_true', help='list the reference names a hypothesis misses')
    args = parser.parse_args()
    ref_text = open(args.reference, encoding='utf-8').read()
    ref, ref_names = words(ref_text), names(ref_text)
    print('| Transcriptie | Woorden | WER | Vervangen | Ontbrekend | Extra | Stukken > 60 woorden zonder leesteken | Namen terug |')
    print('|---|---|---|---|---|---|---|---|')
    for path in args.hypotheses:
        text = open(path, encoding='utf-8').read()
        hyp = words(text)
        s, d, n = errors(ref, hyp)
        low = text.lower()
        missed = [name for name in ref_names if name.lower() not in low]
        share = lambda x: f'{100 * x / len(ref):.1f}%'
        print(f'| {path.rsplit("/", 1)[-1]} | {len(hyp)} van {len(ref)} | {share(s + d + n)} | {share(s)} | {share(d)} | {share(n)} '
              f'| {long_runs(text)} | {len(ref_names) - len(missed)}/{len(ref_names)} |')
        if args.names and missed:
            print('  mist: ' + ', '.join(missed))


def demo():
    assert words('Spreker 1: Ehm, de Offerte komt.') == ['de', 'offerte', 'komt']
    assert errors('a b c d'.split(), 'a x c'.split()) == (1, 1, 0)
    assert errors('a b'.split(), 'a b c'.split()) == (0, 0, 1)
    assert long_runs('kort. ' + 'woord ' * 61) == 1


if __name__ == '__main__':
    demo()
    main()
