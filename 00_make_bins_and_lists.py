#!/usr/bin/env python3
import argparse
import csv
import os
import random
from pathlib import Path


def make_bin_label(lo, hi):
    return f"{int(lo):02d}_{int(hi):02d}"


def nearest_bin(age, starts, bin_size):
    centers = [s + bin_size / 2.0 for s in starts]
    idx = min(range(len(centers)), key=lambda i: abs(age - centers[i]))
    s = starts[idx]
    return s, s + bin_size


def read_rows(csv_path):
    with open(csv_path, newline="") as f:
        reader = csv.DictReader(f)
        required = {"subject_id", "age", "t1_brain"}
        missing = required - set(reader.fieldnames or [])
        if missing:
            raise ValueError(f"Missing required CSV columns: {sorted(missing)}")
        rows = []
        for row in reader:
            sid = row["subject_id"].strip()
            age = float(row["age"])
            t1 = row["t1_brain"].strip()
            if not sid or not t1:
                continue
            rows.append({"subject_id": sid, "age": age, "t1_brain": t1})
        return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", required=True)
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--bin-start", type=int, default=10)
    ap.add_argument("--bin-end", type=int, default=100)
    ap.add_argument("--bin-size", type=int, default=10)
    ap.add_argument("--max-per-bin", type=int, default=0)
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()

    outdir = Path(args.outdir)
    meta_dir = outdir / "meta"
    bin_dir = outdir / "age_bins"
    meta_dir.mkdir(parents=True, exist_ok=True)
    bin_dir.mkdir(parents=True, exist_ok=True)

    rows = read_rows(args.csv)
    random.seed(args.seed)

    starts = list(range(args.bin_start, args.bin_end, args.bin_size))
    bins = {(s, s + args.bin_size): [] for s in starts}
    assigned = []

    for r in rows:
        age = r["age"]
        # Put 100-year-olds into the 90-100 bin, and clamp out-of-range values.
        if age == args.bin_end:
            age = args.bin_end - 1e-6
        if age < args.bin_start or age > args.bin_end:
            continue
        s = int((age - args.bin_start) // args.bin_size) * args.bin_size + args.bin_start
        lo, hi = s, s + args.bin_size
        if (lo, hi) not in bins:
            continue
        bins[(lo, hi)].append(r)
        ns, nh = nearest_bin(r["age"], starts, args.bin_size)
        assigned.append({**r, "bin_lo": lo, "bin_hi": hi, "nearest_bin_lo": ns, "nearest_bin_hi": nh})

    # Optional downsampling within bins
    chosen_bins = {}
    for (lo, hi), items in bins.items():
        items = sorted(items, key=lambda x: (x["age"], x["subject_id"]))
        if args.max_per_bin and len(items) > args.max_per_bin:
            # Age-stratified-ish random selection: random after sorting for reproducibility.
            tmp = items[:]
            random.shuffle(tmp)
            items = sorted(tmp[: args.max_per_bin], key=lambda x: (x["age"], x["subject_id"]))
        chosen_bins[(lo, hi)] = items

    # Write manifests
    summary_rows = []
    for (lo, hi), items in chosen_bins.items():
        label = make_bin_label(lo, hi)
        this_dir = bin_dir / label
        this_dir.mkdir(parents=True, exist_ok=True)
        list_txt = this_dir / "subjects.txt"
        list_csv = this_dir / "subjects.csv"
        with open(list_txt, "w") as ftxt, open(list_csv, "w", newline="") as fcsv:
            writer = csv.DictWriter(fcsv, fieldnames=["subject_id", "age", "t1_brain"])
            writer.writeheader()
            for it in items:
                ftxt.write(it["t1_brain"] + "\n")
                writer.writerow(it)
        if items:
            ages = [x["age"] for x in items]
            summary_rows.append({
                "bin": label,
                "n": len(items),
                "age_min": min(ages),
                "age_max": max(ages),
                "age_mean": sum(ages) / len(ages),
            })
        else:
            summary_rows.append({"bin": label, "n": 0, "age_min": "", "age_max": "", "age_mean": ""})

    with open(meta_dir / "all_subjects_with_bins.csv", "w", newline="") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=["subject_id", "age", "t1_brain", "bin_lo", "bin_hi", "nearest_bin_lo", "nearest_bin_hi"],
        )
        writer.writeheader()
        writer.writerows(assigned)

    with open(meta_dir / "bin_summary.csv", "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["bin", "n", "age_min", "age_max", "age_mean"])
        writer.writeheader()
        writer.writerows(summary_rows)

    print(f"Wrote bin manifests to: {bin_dir}")
    print(f"Wrote summaries to: {meta_dir}")


if __name__ == "__main__":
    main()
