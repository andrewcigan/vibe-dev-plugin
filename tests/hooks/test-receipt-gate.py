"""Квитанция прогона при переходе в готовое состояние (v9 F4.1).

Проверяет: переход в готовое состояние без квитанции даёт сигнал; с квитанцией — тихо;
давно лежащая готовая запись и фича без команды проверки правилом не задеваются.
"""
import json, os, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GUARD = os.path.join(ROOT, "hooks/checks/state-transition.sh")
NAME = "feature" + "_list" + ".json"
CMD = "echo проверка"


def run(before, after, receipt_for=None):
    d = tempfile.mkdtemp(prefix="vibe-rcpt-")
    os.makedirs(os.path.join(d, ".harness", "receipts"), exist_ok=True)
    if receipt_for:
        with open(os.path.join(d, ".harness", "receipts", f"{receipt_for}-20260903T000000Z.json"),
                  "w", encoding="utf-8") as fh:
            json.dump({"feature": receipt_for, "exit_code": 0, "verdict": "passed"}, fh)
    path = os.path.join(d, NAME)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(before, fh, ensure_ascii=False)
    payload = json.dumps({"tool_name": "Write", "tool_input": {
        "file_path": path, "content": json.dumps(after, ensure_ascii=False)}})
    r = subprocess.run(["bash", GUARD, path, d, ROOT, "Write"],
                       env={**os.environ, "HOOK_PAYLOAD": payload}, capture_output=True, text=True)
    return r.stdout


def feat(fid, state, cmd=CMD):
    f = {"id": fid, "state": state, "affected_files": ["src/a.ts"]}
    if cmd:
        f["verification_command"] = cmd
    return f


def wrap(fs):
    return {"features": {"active_list": [x for x in fs if x["state"] == "active"],
                         "done": [x for x in fs if x["state"] != "active"]}}


CASES = [
    (wrap([feat("feat-100", "active")]), wrap([feat("feat-100", "passing")]), None,
     True, "переход в готовое без квитанции"),
    (wrap([feat("feat-101", "active")]), wrap([feat("feat-101", "passing")]), "feat-101",
     False, "переход в готовое с квитанцией"),
    (wrap([feat("feat-102", "passing")]), wrap([feat("feat-102", "passing")]), None,
     False, "давно готовая запись не задевается"),
    (wrap([feat("feat-103", "active", cmd=None)]), wrap([feat("feat-103", "passing", cmd=None)]), None,
     False, "нет команды проверки — другое правило"),
]

ok = fail = 0
for before, after, rec, should, label in CASES:
    out = run(before, after, rec)
    hit = "v9 F4.1" in out
    good = hit == should
    ok, fail = (ok + 1, fail) if good else (ok, fail + 1)
    print(f"  {'✓' if good else '✗'} {label:38} ожидали={'сигнал' if should else 'тихо':7} "
          f"получили={'сигнал' if hit else 'тихо'}")
print(f"\nИтог: PASS={ok} FAIL={fail}")
sys.exit(1 if fail else 0)
