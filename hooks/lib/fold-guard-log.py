#!/usr/bin/env python3
"""Свёртка журнала срабатываний сторожей (v9).

Наблюдение без предела роста само становится тем, за чем надо наблюдать: за четыре дня журнал
дорос до 2,1 МБ (19 831 запись) — та же болезнь, что лечилась в журналах фич.

Итоги за прошлое сохраняются ЧИСЛАМИ в guard-stats-summary.json и не теряются: свод
scripts/guard-stats.sh складывает их с живым хвостом. Подробные строки нужны только по свежим
событиям, поэтому хвост остаётся, а всё до него сворачивается в счётчики.

Использование: python3 fold-guard-log.py <путь-к-guard-stats.jsonl> [сколько-строк-оставить]
"""
import json
import os
import sys

KEEP_DEFAULT = 2000


def main() -> int:
    if len(sys.argv) < 2:
        return 2
    log = sys.argv[1]
    keep = int(sys.argv[2]) if len(sys.argv) > 2 else KEEP_DEFAULT
    summary_path = os.path.join(os.path.dirname(log), "guard-stats-summary.json")

    try:
        lines = open(log, encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        return 0
    if len(lines) <= keep:
        return 0

    old_lines, tail = lines[:-keep], lines[-keep:]
    try:
        summary = json.load(open(summary_path, encoding="utf-8"))
    except (OSError, ValueError):
        summary = {}

    counts = summary.get("totals", {})
    first_t = last_t = None
    for raw in old_lines:
        try:
            rec = json.loads(raw)
        except ValueError:
            continue
        first_t = first_t or rec.get("t")
        last_t = rec.get("t") or last_t
        bucket = counts.setdefault(rec.get("guard", "?"),
                                   {"BLOCK": 0, "WARN": 0, "pass": 0, "CRASH": 0})
        verdict = rec.get("verdict", "pass")
        bucket[verdict] = bucket.get(verdict, 0) + 1

    summary["totals"] = counts
    summary["folded_since"] = summary.get("folded_since") or first_t
    summary["folded_until"] = last_t
    summary["folded_records"] = summary.get("folded_records", 0) + len(old_lines)
    summary["note"] = ("Итоги свёрнутых записей журнала срабатываний: подробные строки за этот "
                       "период удалены, счётчики сохранены. Свод scripts/guard-stats.sh "
                       "складывает их с живым хвостом.")

    tmp = summary_path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(summary, fh, ensure_ascii=False, indent=1)
    os.replace(tmp, summary_path)

    tmp_log = log + ".tmp"
    with open(tmp_log, "w", encoding="utf-8") as fh:
        fh.write("\n".join(tail) + "\n")
    os.replace(tmp_log, log)
    return 0


if __name__ == "__main__":
    sys.exit(main())
