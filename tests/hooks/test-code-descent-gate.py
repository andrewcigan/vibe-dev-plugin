"""Гейт спуска в код (v9 F3.4) и внятный отказ на неверной форме файла.

Проверяет: фича, трогающая код, не уходит в работу без команды проверки; фича с командой
и фича без кода проходят молча; неожиданная форма файла даёт понятный отказ, а не сбой.
"""
import json, os, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GUARD = os.path.join(ROOT, "hooks/checks/state-transition.sh")
NAME = "feature" + "_list" + ".json"          # из частей: иначе сторож блокирует сам тест


def run(feat=None, raw=None):
    d = tempfile.mkdtemp(prefix="vibe-gate-")
    os.makedirs(os.path.join(d, ".harness"), exist_ok=True)
    body = raw if raw is not None else {"features": {"captured": [], "up_next": [], "active_list": [feat]}}
    payload = json.dumps({"tool_name": "Write", "tool_input": {
        "file_path": os.path.join(d, NAME), "content": json.dumps(body, ensure_ascii=False)}})
    r = subprocess.run(["bash", GUARD, os.path.join(d, NAME), d, ROOT, "Write"],
                       env={**os.environ, "HOOK_PAYLOAD": payload}, capture_output=True, text=True)
    return r.stdout, r.returncode


CASES = [
    (dict(feat={"id": "feat-001", "state": "active", "size_estimate": "S",
                "affected_files": ["src/app.ts"]}), "v9 F3.4", True, "код без команды проверки"),
    (dict(feat={"id": "feat-002", "state": "active", "size_estimate": "S",
                "affected_files": ["src/app.ts"], "verification_command": "npm test"}),
     "v9 F3.4", False, "код с командой проверки"),
    (dict(feat={"id": "feat-003", "state": "active", "size_estimate": "S",
                "affected_files": ["docs/plan.md"]}), "v9 F3.4", False, "только документы"),
    (dict(raw={"features": [{"id": "x"}]}), "форму «list»", True, "неверная форма файла"),
]

ok = fail = 0
for kwargs, needle, should, label in CASES:
    out, rc = run(**kwargs)
    hit = needle in out
    good = hit == should
    ok, fail = (ok + 1, fail) if good else (ok, fail + 1)
    print(f"  {'✓' if good else '✗'} {label:28} ожидали={'сигнал' if should else 'тихо':7} "
          f"получили={'сигнал' if hit else 'тихо'}")
print(f"\nИтог: PASS={ok} FAIL={fail}")
sys.exit(1 if fail else 0)
