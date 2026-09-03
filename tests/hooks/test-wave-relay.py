"""Эстафета по направлениям (v9 F6).

Проверяет: волна режется по слоям, задачи с общим файлом не расходятся по разным сессиям,
очередь переживает закрытие направления, и после последнего эстафета завершается.
"""
import json, os, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RELAY = os.path.join(ROOT, "scripts/wave-relay.sh")
NAME = "feature" + "_list" + ".json"

FEATS = [
    {"id": "feat-01", "name": "Схема пользователей", "state": "up_next",
     "affected_files": ["db/schema.sql", "db/migrate.sql"]},
    {"id": "feat-02", "name": "Схема заказов", "state": "up_next", "affected_files": ["db/schema.sql"]},
    {"id": "feat-03", "name": "Экран входа", "state": "up_next",
     "affected_files": ["app/login.tsx", "app/ui.css"]},
    {"id": "feat-04", "name": "Экран заказов", "state": "up_next",
     "affected_files": ["app/orders.tsx", "app/ui.css"]},
    {"id": "feat-05", "name": "Приём оплаты", "state": "up_next", "affected_files": ["integrations/pay.ts"]},
    {"id": "feat-06", "name": "Отправка писем", "state": "up_next", "affected_files": ["integrations/mail.ts"]},
    {"id": "feat-07", "name": "Панель заказов", "state": "active", "affected_files": ["app/orders.tsx"]},
    {"id": "feat-08", "name": "Готовая задача", "state": "passing", "affected_files": ["app/old.tsx"]},
]

d = tempfile.mkdtemp(prefix="vibe-relay-")
os.makedirs(os.path.join(d, ".harness"), exist_ok=True)
with open(os.path.join(d, NAME), "w", encoding="utf-8") as fh:
    json.dump({"features": {
        "active_list": [f for f in FEATS if f["state"] == "active"],
        "up_next": [f for f in FEATS if f["state"] == "up_next"],
        "done": [f for f in FEATS if f["state"] == "passing"]}}, fh, ensure_ascii=False)


def call(action):
    return subprocess.run(["bash", RELAY, action, d], capture_output=True, text=True).stdout


ok = fail = 0
def check(cond, label):
    global ok, fail
    ok, fail = (ok + 1, fail) if cond else (ok, fail + 1)
    print(f"  {'✓' if cond else '✗'} {label}")


out = call("plan")
q = json.load(open(os.path.join(d, ".harness", "relay.json"), encoding="utf-8"))
names = [x["name"] for x in q["directions"]]
check(len(q["directions"]) == 3, f"волна разрезана на 3 направления (получили {len(q['directions'])})")
check(sorted(names) == ["app", "db", "integrations"], f"направления по слоям: {names}")

app = next(x for x in q["directions"] if x["name"] == "app")
check("feat-04" in app["features"] and "feat-07" in app["features"],
      "задачи с общим файлом не разошлись по разным сессиям")
check("feat-08" not in json.dumps(q, ensure_ascii=False), "завершённая задача в эстафету не попала")

first = call("next")
check("Направление 1 из 3" in first, "следующая сессия знает своё направление")

call("done")
q2 = json.load(open(os.path.join(d, ".harness", "relay.json"), encoding="utf-8"))
check(q2["current"] == 1 and q2["directions"][0]["state"] == "закрыто",
      "закрытие направления передало эстафету дальше")

call("done"); last = call("done")
check("Эстафета завершена" in last, "после последнего направления эстафета завершается")

print(f"\nИтог: PASS={ok} FAIL={fail}")
sys.exit(1 if fail else 0)
