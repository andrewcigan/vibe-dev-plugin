"""Живой прогон для фичи с внешней связью (v9 F4.3).

Проверяет: переход в готовое состояние у фичи с внешней связью требует квитанции живого
прогона; обычная квитанция не засчитывается; у фичи без внешней связи правило не применяется.
"""
import json, os, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GUARD = os.path.join(ROOT, "hooks/checks/state-transition.sh")
NAME = "feature" + "_list" + ".json"


def run(before, after, receipt=None):
    d = tempfile.mkdtemp(prefix="vibe-live-")
    rec = os.path.join(d, ".harness", "receipts")
    os.makedirs(rec, exist_ok=True)
    if receipt:
        fid, live = receipt
        with open(os.path.join(rec, f"{fid}-20260903T000000Z.json"), "w", encoding="utf-8") as fh:
            json.dump({"feature": fid, "exit_code": 0, "verdict": "passed", "live": live}, fh)
    path = os.path.join(d, NAME)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(before, fh, ensure_ascii=False)
    payload = json.dumps({"tool_name": "Write", "tool_input": {
        "file_path": path, "content": json.dumps(after, ensure_ascii=False)}})
    r = subprocess.run(["bash", GUARD, path, d, ROOT, "Write"],
                       env={**os.environ, "HOOK_PAYLOAD": payload}, capture_output=True, text=True)
    return r.stdout


def feat(fid, state, surface=None):
    f = {"id": fid, "state": state, "affected_files": ["src/a.ts"], "verification_command": "npm test"}
    if surface:
        f["surface"] = surface
    return f


def wrap(fs):
    return {"features": {"active_list": [x for x in fs if x["state"] == "active"],
                         "done": [x for x in fs if x["state"] != "active"]}}


CASES = [
    (wrap([feat("feat-200", "active", "integration")]), wrap([feat("feat-200", "passing", "integration")]),
     ("feat-200", False), True, "внешняя связь, квитанция без живого прогона"),
    (wrap([feat("feat-201", "active", "integration")]), wrap([feat("feat-201", "passing", "integration")]),
     ("feat-201", True), False, "внешняя связь, живой прогон есть"),
    (wrap([feat("feat-202", "active")]), wrap([feat("feat-202", "passing")]),
     ("feat-202", False), False, "обычная фича — правило не применяется"),
]

ok = fail = 0
for before, after, rec, should, label in CASES:
    out = run(before, after, rec)
    hit = "v9 F4.3" in out
    good = hit == should
    ok, fail = (ok + 1, fail) if good else (ok, fail + 1)
    print(f"  {'✓' if good else '✗'} {label:44} ожидали={'сигнал' if should else 'тихо':7} "
          f"получили={'сигнал' if hit else 'тихо'}")
print(f"\nИтог: PASS={ok} FAIL={fail}")
sys.exit(1 if fail else 0)
