"""Рождение записи сразу в готовом статусе (v9 F4.2).

Проверяет: новая запись в терминальном состоянии без доказательства и без честной пометки
происхождения даёт сигнал; с доказательством или с признанным переносом — проходит;
запись, существовавшая раньше, правилом не задевается.
"""
import json, os, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GUARD = os.path.join(ROOT, "hooks/checks/state-transition.sh")
NAME = "feature" + "_list" + ".json"


def run(before, after):
    d = tempfile.mkdtemp(prefix="vibe-born-")
    os.makedirs(os.path.join(d, ".harness"), exist_ok=True)
    path = os.path.join(d, NAME)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(before, fh, ensure_ascii=False)
    payload = json.dumps({"tool_name": "Write", "tool_input": {
        "file_path": path, "content": json.dumps(after, ensure_ascii=False)}})
    r = subprocess.run(["bash", GUARD, path, d, ROOT, "Write"],
                       env={**os.environ, "HOOK_PAYLOAD": payload}, capture_output=True, text=True)
    return r.stdout


def wrap(feats):
    return {"features": {"captured": [], "up_next": [], "active_list": [], "done": feats}}


OLD = wrap([{"id": "feat-001", "state": "passing", "evidence": "прогон 2026-09-01"}])

CASES = [
    (OLD, wrap([OLD["features"]["done"][0],
                {"id": "feat-777", "state": "passing"}]),
     True, "новая запись сразу готова, без доказательства"),
    (OLD, wrap([OLD["features"]["done"][0],
                {"id": "feat-778", "state": "passing", "evidence": "e2e прогон, 12 сценариев"}]),
     False, "новая запись готова, но с доказательством"),
    (OLD, wrap([OLD["features"]["done"][0],
                {"id": "feat-779", "state": "passing", "provenance": {"origin": "inference"}}]),
     False, "перенос признан честно"),
    (OLD, wrap([OLD["features"]["done"][0]]),
     False, "существовавшая запись не задевается"),
]

ok = fail = 0
for before, after, should, label in CASES:
    out = run(before, after)
    hit = "v9 F4.2" in out
    good = hit == should
    ok, fail = (ok + 1, fail) if good else (ok, fail + 1)
    print(f"  {'✓' if good else '✗'} {label:44} ожидали={'сигнал' if should else 'тихо':7} "
          f"получили={'сигнал' if hit else 'тихо'}")
print(f"\nИтог: PASS={ok} FAIL={fail}")
sys.exit(1 if fail else 0)
