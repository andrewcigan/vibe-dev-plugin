#!/bin/bash
# Эталонный корпус сторожей (v9, волна 0 / F0.3).
#
# ЗАЧЕМ. Зафиксировать НАБЛЮДАЕМОЕ поведение каждого сторожа, чтобы любое расхождение после
# изменения (движок, правка обвязки, ремонт fail-loud) было видно числом, а не «вроде работает».
#
# ЧЕМ ЭТО НЕ ЯВЛЯЕТСЯ. Это не снимок «как есть = как надо». Ожидание задано ЗАРАНЕЕ и жёстко:
#   * при сломанной служебной утилите сторож ОБЯЗАН вернуть ненулевой код (иначе его проверка
#     молча не выполнилась, а действие прошло как разрешённое);
#   * на положительном контроле сторож ОБЯЗАН выдать вердикт (BLOCK или WARN) — иначе нельзя
#     отличить «жив, но повода не было» от «мёртв».
# Иначе болезнь становится эталоном и ремонт «зеленеет», ничего не починив.
#
# Использование: bash tests/hooks/baseline-probe.sh [выходной.json]
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENGINE="$(claude --version 2>/dev/null | awk '{print $1}' || echo unknown)"
OUT="${1:-$ROOT/tests/hooks/baseline-$ENGINE.json}"
SANDBOX="$(mktemp -d)"; trap 'rm -rf "$SANDBOX"' EXIT
mkdir -p "$SANDBOX/proj/.harness" "$SANDBOX/fake"
printf '#!/bin/sh\nexit 127\n' > "$SANDBOX/fake/jq";      chmod +x "$SANDBOX/fake/jq"
printf '#!/bin/sh\nexit 127\n' > "$SANDBOX/fake/python3"; chmod +x "$SANDBOX/fake/python3"
PROJ="$SANDBOX/proj"

PAYLOAD_OK='{"hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"src/app.ts","content":"const a=1"},"cwd":"'"$PROJ"'"}'
PAYLOAD_BAD='НЕ_JSON_ВООБЩЕ{{{'

# --- Карта вызова: у сторожей ТРИ разных протокола аргументов (наследие, чинится в F1.4). ---
# Единый вызов «всем одинаково» давал ложные замеры: часть сторожей выходила рано не потому,
# что нет нарушения, а потому что получила чужие аргументы.
argv_for() {
  case "$1" in
    architecture-research-gate|concurrent-write) printf '%s\t%s' "src/app.ts" "$PROJ" ;;
    state-transition)   printf '%s\t%s\t%s\t%s' "feature_list.json" "$PROJ" "$ROOT" "Write" ;;
    secret-scan-write)  printf '%s\t%s\t%s' "$PROJ" "src/app.ts" "Write" ;;
    folder-scope)       printf '%s\t%s' "$PROJ" "src/app.ts" ;;
    clarity-stop-gate)  printf '%s\t%s' "$PROJ" "strict" ;;
    *)                  printf '%s' "$PROJ" ;;
  esac
}

run_capped() { # таймер не должен держать stdout подстановки — иначе каждый прогон ждёт полный срок
  local secs="$1"; shift
  "$@" & local pid=$!
  { sleep "$secs"; kill -9 "$pid" 2>/dev/null; } >/dev/null 2>&1 & local watcher=$!
  wait "$pid" 2>/dev/null; local rc=$?
  kill -9 "$watcher" 2>/dev/null; wait "$watcher" 2>/dev/null
  return $rc
}

probe() { # $1=скрипт $2=сценарий -> "rc|вывод_есть"
  local script="$1" mode="$2" name rc out path="$PATH" payload="$PAYLOAD_OK"
  name="$(basename "$script" .sh)"
  case "$mode" in
    broken)    payload="$PAYLOAD_BAD" ;;
    nojq|nopy) path="$SANDBOX/fake:$PATH" ;;
  esac
  IFS=$'\t' read -r -a ARGS <<< "$(argv_for "$name")"
  out="$(HOOK_PAYLOAD="$payload" PATH="$path" run_capped 5 bash "$script" "${ARGS[@]}" 2>/dev/null </dev/null)"
  rc=$?
  printf '%s|%s' "$rc" "$([ -n "$out" ] && echo yes || echo no)"
}

# --- Положительные контроли: вход с НАСТОЯЩИМ нарушением, вердикт обязателен. ---
positive_control() { # $1=имя -> "вердикт|сработал"
  local name="$1" out=""
  case "$name" in
    secret-scan-write)
      out="$(HOOK_PAYLOAD='{"tool_name":"Write","tool_input":{"file_path":"src/cfg.ts","content":"const k=\"sk-ant-api03-AAAAAAAAAAAAAAAAAAAA\""}}' \
            bash "$ROOT/hooks/checks/secret-scan-write.sh" "$PROJ" "src/cfg.ts" "Write" 2>/dev/null </dev/null)" ;;
    folder-scope)
      out="$(HOOK_PAYLOAD='{"tool_name":"Write","tool_input":{"file_path":"/etc/passwd","content":"x"}}' \
            bash "$ROOT/hooks/checks/folder-scope.sh" "$PROJ" "/etc/passwd" 2>/dev/null </dev/null)" ;;
    enforcement-config-protect)
      # Охраняет режим строгости ПРОЕКТА (.harness/hook-mode и соседи), не файлы плагина.
      # Настоящее нарушение = агент сам понижает строгость до learn.
      out="$(HOOK_PAYLOAD='{"tool_name":"Write","tool_input":{"file_path":"'"$PROJ"'/.harness/hook-mode","content":"learn"}}' \
            bash "$ROOT/hooks/checks/enforcement-config-protect.sh" "$PROJ" 2>/dev/null </dev/null)" ;;
    *) printf 'n/a|n/a'; return ;;
  esac
  local verdict="none"
  case "$out" in BLOCK*) verdict=BLOCK ;; WARN*) verdict=WARN ;; ?*) verdict=text ;; esac
  printf '%s|%s' "$verdict" "$([ "$verdict" != "none" ] && echo yes || echo NO)"
}

printf '{\n  "engine": "%s",\n  "taken_at": "%s",\n' "$ENGINE" "$(date '+%Y-%m-%d %H:%M:%S')" > "$OUT"
printf '  "expectation": "при сломанной утилите rc!=0; на положительном контроле вердикт обязателен",\n  "guards": {\n' >> "$OUT"
first=1; fail_open=0; total=0
for f in "$ROOT"/hooks/checks/*.sh; do
  name="$(basename "$f" .sh)"; total=$((total+1))
  ok="$(probe "$f" ok)"; broken="$(probe "$f" broken)"
  nojq="$(probe "$f" nojq)"; nopy="$(probe "$f" nopy)"
  pos="$(positive_control "$name")"
  health=fail-open
  if [ "${nojq%%|*}" != "0" ] || [ "${nopy%%|*}" != "0" ]; then health=fail-loud; else fail_open=$((fail_open+1)); fi
  [ $first -eq 1 ] && first=0 || printf ',\n' >> "$OUT"
  printf '    "%s": {"ok":"%s","broken_input":"%s","jq_broken":"%s","python_broken":"%s","positive_control":"%s","health":"%s"}' \
    "$name" "$ok" "$broken" "$nojq" "$nopy" "$pos" "$health" >> "$OUT"
done
printf '\n  },\n  "summary": {"total": %s, "fail_open": %s, "fail_loud": %s}\n}\n' \
  "$total" "$fail_open" "$((total-fail_open))" >> "$OUT"
echo "$OUT"
