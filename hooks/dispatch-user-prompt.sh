#!/bin/bash
# Vibe Dev v6 — UserPromptSubmit dispatcher (точка входа на событие UserPromptSubmit). H6.
#
# Поток: stdin JSON -> guard (vibe-проект?) -> профиль -> handoff-reminder
#        -> inject additionalContext (cold-start чеклист) или тихий pass.
#
# handoff-reminder — warn-уровень (inject, НЕ block): промпт пользователя легитимен,
# блокировать его нельзя; напоминание видно модели. Активен standard,strict; minimal — off.
# Контракт UserPromptSubmit: docs/hooks-contract-verified-2026-06-03.md §4 (stdout как контекст).

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib/hook-io.sh"

hook_read_stdin
CWD="$(hook_field '.cwd')"
[ -z "$CWD" ] && CWD="$PWD"

# Guard: только vibe-target-проекты.
hook_is_vibe_project "$CWD" || hook_emit_pass

# Активация (v6.2 F2): heartbeat «хуки живы» + перевод pending-профиля в боевой.
# UserPromptSubmit срабатывает каждое сообщение -> bootstrap активируется без рестарта.
hook_write_heartbeat "$CWD"
ACTIVATED="$(hook_activate_pending_profile "$CWD")"

# Новый промпт пользователя = новая цепочка хода: сброс общего cap Stop-блоков (F3)
# и счётчика дописок clarity-gate (F4).
rm -f "$CWD/.harness/stop-chain-count" "$CWD/.harness/clarity-stop-count" 2>/dev/null

PROFILE="$(hook_profile "$CWD")"
ROOT="$(hook_plugin_root)"

# Активен только в standard,strict.
if ! profile_in "standard,strict" "$PROFILE"; then
  [ -n "$ACTIVATED" ] && hook_emit_context "UserPromptSubmit" "✅ Vibe Dev: enforcement активирован живым хуком — профиль «${ACTIVATED}» подтверждён."
  hook_emit_pass
fi

PIECES=""
[ -n "$ACTIVATED" ] && PIECES="✅ Vibe Dev: enforcement активирован живым хуком — профиль «${ACTIVATED}» подтверждён (скажи пользователю одной строкой)."

# H6: сигнал завершения сессии -> cold-start чеклист + маркер handoff-pending.
# hook_run_check (fail-loud): краш проверки -> абзац-предупреждение + crash-артефакт.
HANDOFF="$(HOOK_PAYLOAD="$HOOK_INPUT" hook_run_check "$CWD" "handoff-reminder" text "$ROOT/hooks/checks/handoff-reminder.sh" "$CWD")"
if [ -n "$(printf '%s' "$HANDOFF" | tr -d '[:space:]')" ]; then
  case "$HANDOFF" in
    "⚠️ сторож"*)
      # Проверка УПАЛА, не успев ничего решить — это НЕ сигнал завершения: маркеры не ставим,
      # но предупреждение о краше доносим.
      ;;
    *)
      # Маркер для SessionStart-probe (loop H6): следующий старт проверит, обновился ли
      # SESSION.md после этого сигнала. Если нет — handoff мог не записаться -> warn.
      mkdir -p "$CWD/.harness/locks" 2>/dev/null
      : > "$CWD/.harness/handoff-pending" 2>/dev/null
      # closing-mode (F7, П6): на время закрытия — деградация прав (PreToolUse-гейт:
      # запись только в state-файлы, Bash только git/read-only). Снимется следующим
      # промптом без сигнала завершения (ветка else ниже).
      : > "$CWD/.harness/locks/closing-mode" 2>/dev/null
      ;;
  esac
  if [ -n "$PIECES" ]; then
    PIECES="$PIECES
—
$HANDOFF"
  else
    PIECES="$HANDOFF"
  fi
else
  # Промпт БЕЗ сигнала завершения: пользователь продолжает работу — режим закрытия снят
  # (его инструкция главнее; закрывает FP «на сегодня всё… хотя нет, поправь ещё кнопку»).
  rm -f "$CWD/.harness/locks/closing-mode" 2>/dev/null
fi

# interrupt-recovery (v6.2.1): хвост последнего хода оборван техническим прерыванием
# (обрыв клиента/доставка сообщения), в новом промпте нет стоп-слов -> inject «продолжай,
# это был обрыв, не запрет» (агент не стоит часами после лживого "user rejected").
IRECOV="$(HOOK_PAYLOAD="$HOOK_INPUT" hook_run_check "$CWD" "interrupt-recovery" text "$ROOT/hooks/checks/interrupt-recovery.sh" "$CWD")"
if [ -n "$(printf '%s' "$IRECOV" | tr -d '[:space:]')" ]; then
  if [ -n "$PIECES" ]; then
    PIECES="$PIECES
—
$IRECOV"
  else
    PIECES="$IRECOV"
  fi
fi

# Анти-залипание (прокси №1 tunnel-vision): стоп-сигнал / коррекция курса -> напоминание
# (смена УРОВНЯ, не способа). Маркер handoff НЕ ставит — это не завершение сессии.
STUCK="$(HOOK_PAYLOAD="$HOOK_INPUT" hook_run_check "$CWD" "stuck-signal" text "$ROOT/hooks/checks/stuck-signal-reminder.sh" "$CWD")"

# research-skip (F6, lock-паттерн): явная фраза «пропусти рисёрч» -> хук (не агент!) пишет
# маркер .harness/locks/research-skipped с цитатой; гейт архитектуры его уважает.
RSKIP="$(HOOK_PAYLOAD="$HOOK_INPUT" hook_run_check "$CWD" "research-skip" text "$ROOT/hooks/checks/research-skip-listener.sh" "$CWD")"
if [ -n "$(printf '%s' "$RSKIP" | tr -d '[:space:]')" ]; then
  if [ -n "$PIECES" ]; then
    PIECES="$PIECES
—
$RSKIP"
  else
    PIECES="$RSKIP"
  fi
fi

# secret-skip (v7 P14 escape, lock-паттерн): явная фраза «ключ тестовый / забей» -> хук (не агент!)
# пишет одноразовый маркер .harness/locks/secret-scan-off; secret-scan-write снимает по нему блок.
SSKIP="$(HOOK_PAYLOAD="$HOOK_INPUT" hook_run_check "$CWD" "secret-skip" text "$ROOT/hooks/checks/secret-skip-listener.sh" "$CWD")"
if [ -n "$(printf '%s' "$SSKIP" | tr -d '[:space:]')" ]; then
  if [ -n "$PIECES" ]; then
    PIECES="$PIECES
—
$SSKIP"
  else
    PIECES="$SSKIP"
  fi
fi

# secret-in-prompt (F8): живой ключ в сообщении пользователя -> предупреждение о ротации
# (inject, не block: ключ уже в контексте — задача предупредить и направить в .env).
SECR="$(HOOK_PAYLOAD="$HOOK_INPUT" hook_run_check "$CWD" "secret-in-prompt" text "$ROOT/hooks/checks/secret-in-prompt.sh" "$CWD")"
if [ -n "$(printf '%s' "$SECR" | tr -d '[:space:]')" ]; then
  if [ -n "$PIECES" ]; then
    PIECES="$PIECES
—
$SECR"
  else
    PIECES="$SECR"
  fi
fi
if [ -n "$(printf '%s' "$STUCK" | tr -d '[:space:]')" ]; then
  if [ -n "$PIECES" ]; then
    PIECES="$PIECES
—
$STUCK"
  else
    PIECES="$STUCK"
  fi
fi

if [ -n "$(printf '%s' "$PIECES" | tr -d '[:space:]')" ]; then
  hook_emit_context "UserPromptSubmit" "$PIECES"
fi
hook_emit_pass
