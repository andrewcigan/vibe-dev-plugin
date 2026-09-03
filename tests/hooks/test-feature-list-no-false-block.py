import json, os, subprocess
ROOT=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FL="feature"+"_list"+".json"
GUARD=os.path.join(ROOT,"hooks/checks/feature-list-bash-guard.sh")
# Команды обычной разработки, которые ОБЯЗАНЫ проходить: они лишь упоминают имя журнала.
cases=[
 (f"grep -n '{FL}' hooks/checks/*.sh", "поиск по исходникам"),
 (f"sed -n '1,20p' docs/traceability.md  # про {FL}", "чтение с упоминанием в комментарии"),
 (f"echo 'сторож охраняет {FL}' >> docs/notes.md", "запись в ДРУГОЙ файл, имя в тексте"),
 (f"git diff -- {FL}", "просмотр изменений журнала"),
 (f"python3 -c \"print('{FL}')\"", "печать имени интерпретатором"),
]
ok=fail=0
for cmd,label in cases:
    r=subprocess.run(["bash",GUARD,ROOT],env={**os.environ,"HOOK_PAYLOAD":json.dumps({"tool_name":"Bash","tool_input":{"command":cmd}})},capture_output=True,text=True)
    blocked=r.stdout.strip().startswith("BLOCK")
    ok,fail=(ok,fail+1) if blocked else (ok+1,fail)
    print(f"  {'✗ ЛОЖНЫЙ БЛОК' if blocked else '✓ проходит    '} {label}")
print(f"\nЛожных блокировок: {fail} из {len(cases)}")
