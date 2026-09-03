"""Проверка: остановленная в v9 блокировка по свежести датчика больше не мешает коммиту."""
import os, subprocess, tempfile, shutil, pathlib

PLUGIN = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
d = tempfile.mkdtemp(prefix="vibe-precommit-")
h = pathlib.Path(d, ".harness"); h.mkdir()
subprocess.run(["git", "init", "-q"], cwd=d, check=True)
(h / "profile").write_text("strict", encoding="utf-8")
(h / "hooks-heartbeat").write_text("1000000000\n", encoding="utf-8")   # метка 2001 года
shutil.copy(os.path.join(PLUGIN, "templates/git-pre-commit.sh"),
            os.path.join(d, ".git/hooks/pre-commit"))
os.chmod(os.path.join(d, ".git/hooks/pre-commit"), 0o755)
pathlib.Path(d, "file.txt").write_text("тест\n", encoding="utf-8")
subprocess.run(["git", "add", "file.txt"], cwd=d, check=True)
r = subprocess.run(["git", "-c", "user.email=t@t", "-c", "user.name=t",
                    "commit", "-m", "протухшая метка не должна блокировать"],
                   cwd=d, capture_output=True, text=True)
import sys
print("код возврата коммита:", r.returncode)
if r.returncode != 0:
    print("ЗАБЛОКИРОВАН. Причина:")
    print((r.stderr or r.stdout)[:400])
else:
    print("КОММИТ ПРОШЁЛ — блокировка по свежести датчика действительно снята")

# Контроль: неподтверждённый профиль по-прежнему обязан останавливать коммит.
(h / "profile").write_text("pending-strict", encoding="utf-8")
pathlib.Path(d, "file2.txt").write_text("тест2\n", encoding="utf-8")
subprocess.run(["git", "add", "file2.txt"], cwd=d, check=True)
r2 = subprocess.run(["git", "-c", "user.email=t@t", "-c", "user.name=t",
                     "commit", "-m", "неподтверждённый профиль"],
                    cwd=d, capture_output=True, text=True)
print("\nконтроль (неподтверждённый профиль): код", r2.returncode,
      "→", "останавливает (верно)" if r2.returncode != 0 else "ПРОПУСТИЛ (защита потеряна)")

sys.exit(0 if (r.returncode == 0 and r2.returncode != 0) else 1)
