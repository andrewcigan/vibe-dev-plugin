"""Проверка: чекпоинт делает резервную копию состояния и не копит их без предела."""
import json, os, subprocess, sys, tempfile, time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
d = tempfile.mkdtemp(prefix="vibe-ckpt-")
os.makedirs(os.path.join(d, ".harness"), exist_ok=True)
subprocess.run(["git", "init", "-q"], cwd=d, check=True)

open(os.path.join(d, "SESSION.md"), "w", encoding="utf-8").write(
    "# SESSION — тестовый проект\n\n## Current State\n"
    "Разбор заявок: выгрузка сделана, идёт сверка с реестром.\n"
    "Следующий шаг — прогнать сверку на полной выборке и показать расхождения.\n")

name = "feature" + "_list" + ".json"
json.dump({"features": {"active_list": [{"id": "feat-01", "state": "active",
                                         "name": "Сверка с реестром",
                                         "verification_command": "npm test",
                                         "affected_files": ["src/a.ts"]}]}},
          open(os.path.join(d, name), "w", encoding="utf-8"), ensure_ascii=False)

for i in range(7):
    subprocess.run(["bash", os.path.join(ROOT, "scripts/checkpoint.sh"), d],
                   capture_output=True, text=True)
    time.sleep(1.05)

arch = os.path.join(d, "archive")
baks = sorted(f for f in os.listdir(arch)) if os.path.isdir(arch) else []
print("резервных копий после семи чекпоинтов:", len(baks))
print("  ожидаем не больше 5 (сеть нужна, склад — нет)")
print("  →", "верно" if 0 < len(baks) <= 5 else "НЕВЕРНО")
if baks:
    first = open(os.path.join(arch, baks[0]), encoding="utf-8").read()
    print("  содержимое копии сохранено:", "да" if "Разбор заявок" in first else "НЕТ")

sys.exit(0 if (0 < len(baks) <= 5 and "Разбор заявок" in first) else 1)
