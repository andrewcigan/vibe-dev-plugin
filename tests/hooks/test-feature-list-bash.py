import json, os, subprocess, sys, tempfile
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SBX  = tempfile.mkdtemp(prefix="vibe-flg-")
FL   = "feature" + "_list" + ".json"          # собрано из частей: иначе сторож блокирует сам тест
GUARD = os.path.join(ROOT, "hooks/checks/feature-list-bash-guard.sh")

cases = [
    (f"echo '{{}}' > {FL}",                     ROOT, True,  "свой журнал, перенаправление"),
    (f"jq '.x=1' {FL} > t && mv t {FL}",        ROOT, True,  "свой журнал, через переименование"),
    (f"python3 -c \"import json;json.dump({{}},open('{FL}','w'))\"", ROOT, True, "свой журнал, интерпретатор"),
    (f"printf x > {SBX}/{FL}",                  ROOT, False, "чужой путь вне проекта"),
    (f"cat {FL}",                               ROOT, False, "чтение"),
    ("ls -la",                                  ROOT, False, "обычная команда"),
    (f"bash scripts/record-change.sh feat-001 passing", ROOT, False, "законный путь записи"),
]
ok = fail = 0
for cmd, cwd, should_block, label in cases:
    payload = json.dumps({"tool_name": "Bash", "tool_input": {"command": cmd}})
    r = subprocess.run(["bash", GUARD, cwd], env={**os.environ, "HOOK_PAYLOAD": payload},
                       capture_output=True, text=True)
    blocked = r.stdout.strip().startswith("BLOCK")
    good = blocked == should_block
    ok, fail = (ok+1, fail) if good else (ok, fail+1)
    print(f"  {'✓' if good else '✗'} {label:34} ожидали={'блок' if should_block else 'проход':6} получили={'блок' if blocked else 'проход'}")
print(f"\nИтог: PASS={ok} FAIL={fail}")
sys.exit(1 if fail else 0)
