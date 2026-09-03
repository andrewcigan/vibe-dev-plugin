#!/bin/bash
# Эстафета по направлениям (v9 F6) — решение владельца: волна режется на направления,
# каждое направление идёт своей сессией, закрытие одного открывает следующее.
#
# ЗАЧЕМ. Волна из полутора десятков фич в одной сессии — это разрастание контекста и потеря
# нити: к середине работы начало уже сжато. Разделение по направлениям даёт каждой сессии свой
# чистый контекст, а порядок при этом не теряется, потому что очередь лежит в файле.
#
# КАК РЕЖЕТСЯ. По тому, какие файлы фичи трогают: фичи, делящие хотя бы один файл, попадают в
# одно направление (иначе две сессии писали бы в один файл и мешали друг другу). Получаются
# естественные направления — база данных, экраны, внешние связи.
#
# Использование:
#   bash scripts/wave-relay.sh plan [<путь>]   — показать разбиение и записать очередь
#   bash scripts/wave-relay.sh next [<путь>]   — что брать в следующую сессию
#   bash scripts/wave-relay.sh done [<путь>]   — направление закрыто, передать эстафету
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTION="${1:-plan}"; ROOT="${2:-$PWD}"
FL="$ROOT/feature_list.json"
QUEUE="$ROOT/.harness/relay.json"
[ -f "$FL" ] || { echo "Нет журнала фич в $ROOT" >&2; exit 1; }
mkdir -p "$ROOT/.harness"

python3 - "$FL" "$QUEUE" "$ACTION" <<'PYEOF'
import json, sys, os, datetime

fl, queue_path, action = sys.argv[1], sys.argv[2], sys.argv[3]
data = json.load(open(fl, encoding='utf-8'))

def all_feats():
    out = []
    for bucket, lst in (data.get('features') or {}).items():
        if isinstance(lst, list):
            for f in lst:
                if isinstance(f, dict):
                    out.append((bucket, f))
    return out

def load_queue():
    try:
        return json.load(open(queue_path, encoding='utf-8'))
    except Exception:
        return None

def split_directions(feats):
    """Фичи, делящие хотя бы один файл, идут в одно направление: две сессии не должны
    писать в один файл. Классическое объединение множеств."""
    parent = {}
    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]; x = parent[x]
        return x
    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb: parent[rb] = ra

    ids = [str(f.get('id')) for _, f in feats]
    for i in ids: parent[i] = i
    owner = {}
    for (_, f) in feats:
        fid = str(f.get('id'))
        for path in (f.get('affected_files') or []):
            key = str(path)
            if key in owner: union(owner[key], fid)
            else: owner[key] = fid
    groups = {}
    for (_, f) in feats:
        fid = str(f.get('id'))
        groups.setdefault(find(fid), []).append(f)
    return list(groups.values())

def name_of(group):
    """Имя направления — по общему верхнему каталогу затронутых файлов."""
    tops = set()
    for f in group:
        for p in (f.get('affected_files') or []):
            parts = str(p).split('/')
            tops.add(parts[0] if len(parts) > 1 else 'корень')
    if not tops: return "без файлов"
    return " + ".join(sorted(tops)[:3]) + ("…" if len(tops) > 3 else "")

WORK_STATES = {'active', 'up_next', 'awaiting_research', 'awaiting_demo_milestone', 'blocked', 'rollback'}
pending = [f for b, f in all_feats()
           if str(f.get('state') or b) in WORK_STATES or b in ('active_list', 'up_next')]

if action == 'plan':
    if not pending:
        print("В работе и в очереди нет фич — резать нечего."); raise SystemExit
    groups = split_directions([(None, f) for f in pending])
    # Группы с общим верхним каталогом сливаем: иначе две задачи одного слоя, не делящие
    # конкретный файл, уехали бы в разные сессии — дробление без пользы.
    merged = {}
    for g in groups:
        merged.setdefault(name_of(g), []).extend(g)
    groups = list(merged.values())
    groups.sort(key=lambda g: -len(g))
    q = {"created": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds'),
         "current": 0,
         "directions": [{"name": name_of(g), "features": [str(x.get('id')) for x in g],
                         "titles": [str(x.get('name') or x.get('id')) for x in g],
                         "state": "ожидает"} for g in groups]}
    json.dump(q, open(queue_path, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    n = len(groups)
    word = "направление" if n % 10 == 1 and n % 100 != 11 else (
           "направления" if n % 10 in (2, 3, 4) and n % 100 not in (12, 13, 14) else "направлений")
    print(f"Волна разрезана на {n} {word} (каждое — своя сессия):\n")
    for i, d in enumerate(q["directions"], 1):
        k = len(d['features'])
        zword = "задача" if k % 10 == 1 and k % 100 != 11 else (
                "задачи" if k % 10 in (2, 3, 4) and k % 100 not in (12, 13, 14) else "задач")
        print(f"  {i}. {d['name']} — {k} {zword}")
        for t in d["titles"][:4]:
            print(f"       · {t}")
        if len(d["titles"]) > 4:
            print(f"       · ещё {len(d['titles'])-4}")
    print(f"\nОчередь записана. Начать первое: bash scripts/wave-relay.sh next")

elif action == 'next':
    q = load_queue()
    if not q: print("Очереди нет — сначала: bash scripts/wave-relay.sh plan"); raise SystemExit
    i = q.get("current", 0)
    ds = q.get("directions", [])
    if i >= len(ds):
        print("Все направления волны закрыты. Эстафета завершена."); raise SystemExit
    d = ds[i]
    print(f"Направление {i+1} из {len(ds)}: {d['name']}")
    print(f"Задачи ({len(d['features'])}): " + ", ".join(d['features']))
    print("\nВ новой сессии этого проекта возьми ровно эти задачи и не трогай остальные:")
    print("порядок и границы уже зафиксированы в .harness/relay.json, а не в памяти.")

elif action == 'done':
    q = load_queue()
    if not q: print("Очереди нет."); raise SystemExit
    i = q.get("current", 0); ds = q.get("directions", [])
    if i < len(ds):
        ds[i]["state"] = "закрыто"
        q["current"] = i + 1
        json.dump(q, open(queue_path, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
        print(f"Направление «{ds[i]['name']}» закрыто.")
    if q["current"] < len(ds):
        nxt = ds[q["current"]]
        print(f"Следующее направление: {nxt['name']} — задачи: " + ", ".join(nxt['features']))
        print("Эстафета передана: закрытие одного направления открыло следующее.")
    else:
        print("Все направления волны закрыты. Эстафета завершена.")
else:
    print("Действия: plan | next | done"); raise SystemExit(2)
PYEOF
