import json, os, subprocess, sys
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
G = os.path.join(ROOT, "hooks/checks/role-scope-guard.sh")
cases = [
 ({"agent_type":"vibe-dev:architect","tool_name":"Write","tool_input":{"file_path":"src/app.ts"}}, True,  "архитектор пишет код"),
 ({"agent_type":"vibe-dev:architect","tool_name":"Write","tool_input":{"file_path":"docs/ARCHITECTURE.md"}}, False, "архитектор пишет документ"),
 ({"agent_type":"vibe-dev:architect","tool_name":"Bash","tool_input":{"command":"cat > src/app.ts <<EOF"}}, True, "архитектор пишет код через оболочку"),
 ({"agent_type":"vibe-dev:architect","tool_name":"Bash","tool_input":{"command":"ls -la src/"}}, False, "архитектор смотрит код"),
 ({"agent_type":"vibe-dev:implementer","tool_name":"Write","tool_input":{"file_path":"src/app.ts"}}, False, "исполнитель пишет код"),
 ({"agent_type":"vibe-dev:data-model-reviewer","tool_name":"Write","tool_input":{"file_path":"db/schema.sql"}}, True, "критик модели правит схему"),
 ({"tool_name":"Write","tool_input":{"file_path":"src/app.ts"}}, False, "главная сессия (роль не указана)"),
]
ok=fail=0
for payload, should_block, label in cases:
    r=subprocess.run(["bash",G,ROOT],env={**os.environ,"HOOK_PAYLOAD":json.dumps(payload)},capture_output=True,text=True)
    blocked=r.stdout.strip().startswith("BLOCK")
    good = blocked==should_block
    ok,fail=(ok+1,fail) if good else (ok,fail+1)
    print(f"  {'✓' if good else '✗'} {label:38} ожидали={'блок' if should_block else 'проход':6} получили={'блок' if blocked else 'проход'}")
print(f"\nИтог: PASS={ok} FAIL={fail}")
sys.exit(1 if fail else 0)
