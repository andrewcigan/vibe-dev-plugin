#!/bin/bash
# Vibe Dev v8 — единая цифра готовности харнеса: объективные метрики (L5-F5, c11).
#
# /audit сводит здоровье харнеса в ОДИН показатель. 7-tuple (Instructions/State/Verification/
# Scope/Lifecycle/Learning/Cost) выставляет evaluator-agent (fresh context, субъективно-чек-лист).
# Этот скрипт даёт ОБЪЕКТИВНУЮ (детерминированную из файлов) часть — три v8-метрики:
#   - provenance_integrity: доля фич в горячем с валидной провенанс-головой И когерентных с логом
#     (голова seq не впереди лога). Провал = история требований дырявая (c4).
#   - archive_evidence: доля архивных стабов с телом в archive.json и совпадающим evidence_hash (c10).
#   - budget_coverage: доля активных/up_next фич с заданным tool_call_budget (L5-F6; информативно).
#
# Единая цифра здоровья = МИНИМУМ (узкое место, не среднее — принцип evaluator) объективных
# метрик; /audit берёт min(health_objective, bottleneck-балл 7-tuple × 20). Диагностика, НЕ гейт.
#
# Использование: bash scripts/audit-health.sh [<путь-проекта>]  (печатает метрики; exit 0)
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../hooks/lib/resolve-paths.sh"

ROOT="$(vibe_resolve_root "${1:-$PWD}" strict)" || exit 1
FL="$(vibe_path_feature_list "$ROOT")"
LOG="$(vibe_path_provenance_log "$ROOT")"
ARCH="$(vibe_path_archive "$ROOT")"
[ -f "$FL" ] || { echo "❌ Нет feature_list.json в $ROOT" >&2; exit 1; }

FL="$FL" LOG="$LOG" ARCH="$ARCH" python3 <<'PY'
import json, os, hashlib

FL, LOG, ARCH = os.environ["FL"], os.environ["LOG"], os.environ["ARCH"]

def load(p, default):
    try: return json.load(open(p, encoding="utf-8"))
    except Exception: return default

data = load(FL, {})
events = []
if os.path.exists(LOG):
    for ln in open(LOG, encoding="utf-8"):
        ln = ln.strip()
        if ln:
            try: events.append(json.loads(ln))
            except Exception: pass
def logmax(feat):
    s = [e.get("seq", -1) for e in events if e.get("feat") == feat and isinstance(e.get("seq"), int)]
    return max(s) if s else -1

# --- собрать фичи горячего (не-стабы) и стабы (архивные ссылки) ---
hot, stubs = [], []
for _b, feats in (data.get("features") or {}).items():
    if not isinstance(feats, list): continue
    for f in feats:
        if not isinstance(f, dict): continue
        if "evidence_hash" in f: stubs.append(f)
        else: hot.append(f)

# --- 1. provenance_integrity: валидная голова + когерентность ---
def head_ok(f):
    p = f.get("provenance")
    if not isinstance(p, dict): return False
    if not p.get("origin"): return False
    sr = p.get("source_ref")
    if not (isinstance(sr, dict) and sr.get("kind")): return False
    if not str(p.get("captured_at") or "").strip(): return False
    if not p.get("by"): return False
    hs = p.get("seq", 0)
    if not isinstance(hs, int): hs = 0
    if hs >= 1 and logmax(f.get("id")) < hs: return False   # голова впереди лога
    return True
prov_ok = sum(1 for f in hot if head_ok(f))
prov_total = len(hot)
prov_pct = round(100 * prov_ok / prov_total) if prov_total else 100

# --- 2. archive_evidence: стаб → тело в архиве с совпадающим hash ---
arch = load(ARCH, {})
archived = {a.get("id"): a for a in (arch.get("archived") or []) if isinstance(a, dict)}
def bhash(f):
    return "sha256:" + hashlib.sha256(json.dumps(f, sort_keys=True, ensure_ascii=False).encode("utf-8")).hexdigest()
arch_ok = 0
for s in stubs:
    body = archived.get(s.get("id"))
    if body and bhash(body) == s.get("evidence_hash"):
        arch_ok += 1
arch_total = len(stubs)
arch_pct = round(100 * arch_ok / arch_total) if arch_total else 100

# --- 3. budget_coverage: активные/up_next с tool_call_budget ---
def state_of(f): return f.get("state", "")
workable = [f for f in hot if state_of(f) in ("active", "up_next", "captured")]
bud_ok = sum(1 for f in workable if isinstance(f.get("tool_call_budget"), int))
bud_total = len(workable)
bud_pct = round(100 * bud_ok / bud_total) if bud_total else 100

# единая объективная цифра = узкое место (min), не среднее
health_obj = min(prov_pct, arch_pct)   # budget_coverage — информативно, не штрафует health

print("provenance_integrity: %d%% (%d/%d фич с валидной головой и когерентны с логом)" % (prov_pct, prov_ok, prov_total))
print("archive_evidence:     %d%% (%d/%d архивных стабов с совпадающим evidence_hash)" % (arch_pct, arch_ok, arch_total))
print("budget_coverage:      %d%% (%d/%d рабочих фич с tool_call_budget; информативно)" % (bud_pct, bud_ok, bud_total))
print("health_objective:     %d (узкое место provenance/archive — НЕ среднее)" % health_obj)
print("# Единая цифра /audit = min(health_objective, bottleneck 7-tuple × 20). Диагностика, не гейт.")
PY
