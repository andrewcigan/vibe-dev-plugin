"""Свёртка журнала срабатываний (v9).

Проверяет: журнал не растёт бесконечно; счётчики за свёрнутый период не теряются;
свод складывает свёрнутые итоги с живым хвостом; повторная свёртка накапливает, а не затирает.
"""
import json, os, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FOLD = os.path.join(ROOT, "hooks/lib/fold-guard-log.py")
STATS = os.path.join(ROOT, "scripts/guard-stats.sh")

d = tempfile.mkdtemp(prefix="vibe-fold-")
os.makedirs(os.path.join(d, ".harness"), exist_ok=True)
log = os.path.join(d, ".harness", "guard-stats.jsonl")

with open(log, "w", encoding="utf-8") as fh:
    for i in range(5000):
        verdict = "BLOCK" if i % 100 == 0 else "pass"
        fh.write(json.dumps({"t": f"2026-09-0{1 + i % 5}T00:00:00Z", "guard": "секрет-в-коде",
                             "verdict": verdict, "rc": 0, "event": "PreToolUse", "gist": ""},
                            ensure_ascii=False) + "\n")

ok = fail = 0
def check(cond, label):
    global ok, fail
    ok, fail = (ok + 1, fail) if cond else (ok, fail + 1)
    print(f"  {'✓' if cond else '✗'} {label}")

before = sum(1 for _ in open(log, encoding="utf-8"))
subprocess.run([sys.executable, FOLD, log, "2000"], check=True)
after = sum(1 for _ in open(log, encoding="utf-8"))
check(before == 5000 and after == 2000, f"журнал обрезан до хвоста ({before} → {after})")

summary = json.load(open(os.path.join(d, ".harness", "guard-stats-summary.json"), encoding="utf-8"))
folded_blocks = summary["totals"]["секрет-в-коде"]["BLOCK"]
check(summary["folded_records"] == 3000, f"свёрнуто записей учтено верно ({summary['folded_records']})")
check(folded_blocks == 30, f"запреты за свёрнутый период не потеряны ({folded_blocks})")

out = subprocess.run(["bash", STATS, d], capture_output=True, text=True).stdout
check("свёрнутых в итоги" in out, "свод сообщает про свёрнутый период")
check("50" in out.split("Итого:")[1].split("\n")[0], "свод складывает свёрнутое с живым (50 запретов)")

# Повторная свёртка должна НАКАПЛИВАТЬ итоги, а не затирать прошлые.
with open(log, "a", encoding="utf-8") as fh:
    for i in range(3000):
        fh.write(json.dumps({"t": "2026-09-06T00:00:00Z", "guard": "секрет-в-коде",
                             "verdict": "pass", "rc": 0, "event": "PreToolUse", "gist": ""},
                            ensure_ascii=False) + "\n")
subprocess.run([sys.executable, FOLD, log, "2000"], check=True)
summary2 = json.load(open(os.path.join(d, ".harness", "guard-stats-summary.json"), encoding="utf-8"))
check(summary2["totals"]["секрет-в-коде"]["BLOCK"] >= folded_blocks,
      "повторная свёртка накапливает, а не затирает прошлые итоги")

print(f"\nИтог: PASS={ok} FAIL={fail}")
sys.exit(1 if fail else 0)
