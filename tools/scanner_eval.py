#!/usr/bin/env python3
"""Accuracy of the leaf scanner on a labelled set of photos.

Usage: python3 tools/scanner_eval.py labels.csv predictions.csv
labels.csv:       photo,true_label
predictions.csv:  photo,predicted_label
Labels are compared ignoring case, spaces and underscores.
"""
import csv
import sys
from collections import Counter, defaultdict


def norm(s):
    return s.strip().lower().replace("_", " ").replace("-", " ")


def read(path):
    with open(path, newline="") as f:
        rows = list(csv.reader(f))
    if rows and rows[0] and rows[0][0].strip().lower() == "photo":
        rows = rows[1:]
    return {r[0].strip(): r[1].strip() for r in rows if len(r) >= 2 and r[0].strip()}


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    truth, pred = read(sys.argv[1]), read(sys.argv[2])
    missing = [p for p in truth if p not in pred]
    photos = [p for p in truth if p in pred]
    if not photos:
        sys.exit("No photos appear in both files.")
    right = sum(norm(truth[p]) == norm(pred[p]) for p in photos)
    print(f"Photos scored: {len(photos)}  (missing predictions: {len(missing)})")
    print(f"Overall accuracy: {right / len(photos):.1%}  ({right} of {len(photos)})")

    per = defaultdict(lambda: [0, 0])
    confusion = Counter()
    for p in photos:
        t, q = norm(truth[p]), norm(pred[p])
        per[t][1] += 1
        if t == q:
            per[t][0] += 1
        else:
            confusion[(t, q)] += 1
    print("\nPer disease (correct / total):")
    for t, (a, n) in sorted(per.items(), key=lambda kv: kv[1][0] / kv[1][1]):
        print(f"  {t:<28} {a}/{n}  {a / n:.0%}")
    if confusion:
        print("\nMost common mistakes (true -> predicted):")
        for (t, q), n in confusion.most_common(8):
            print(f"  {t} -> {q}: {n}")
    healthy = [p for p in photos if norm(truth[p]) == "healthy"]
    if healthy:
        fa = sum(norm(pred[p]) != "healthy" for p in healthy)
        print(f"\nHealthy leaves called sick: {fa} of {len(healthy)}")
    print("\nReport the number of photos next to the accuracy. Small samples have wide error bars.")


if __name__ == "__main__":
    main()
