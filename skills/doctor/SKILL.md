---
name: doctor
description: Самодиагностика enforcement — живы ли сторожа (хуки) в этом проекте. Проверяет профиль/heartbeat/краши/plugin. Триггеры — "/doctor", "проверь харнес", "хуки работают?", "почему сторожа молчат", "диагностика плагина".
when_to_use: Когда есть подозрение, что enforcement не активен (профиль pending, нет подтверждения активации после bootstrap, pre-commit заблокировал коммит, сторожа падали) или просто для проверки здоровья harness перед важной работой.
---

# /doctor — жив ли enforcement

Профиль строгости в файле — это заявление. Этот скилл проверяет ФАКТЫ: работают ли хуки
физически. Запускай диагностику сам (правило 8: не отправляй пользователя в терминал).

## Шаг 1: Снять показания (одним bash-блоком)

```bash
echo "=== Vibe Dev /doctor ==="
echo "— Папка: $(pwd)"
echo "— Vibe-проект: $([ -d .harness ] || [ -f feature_list.json ] && echo да || echo НЕТ)"
echo "— Профиль: $(cat .harness/profile 2>/dev/null || echo '(нет файла)')"
echo "— Движок проекта (пин): $(cat .harness/engine-version 2>/dev/null || echo '(нет — legacy)')"
PV=$(jq -r '.version // "?"' "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" 2>/dev/null)
echo "— Установлен плагин: ${PV:-?} ($(git -C "${CLAUDE_PLUGIN_ROOT}" log -1 --format='%h %cd' --date=short 2>/dev/null || echo 'не git-копия'))"
PIN=$(tr -d '[:space:]' < .harness/engine-version 2>/dev/null)
if [ -n "$PIN" ] && [ -n "$PV" ] && [ "$PV" != "?" ] && [ "${PV%%.*}" -gt "${PIN%%.*}" ] 2>/dev/null; then
  echo "— ⚠️ Канал доставки: установлен мажор ${PV%%.*} > пин проекта ${PIN%%.*} → прогони /upgrade-project (профиль отстаёт; код хуков уже обновлён)"
fi
if [ -f .harness/hooks-heartbeat ]; then
  HB_TS=$(awk '{print $1; exit}' .harness/hooks-heartbeat); NOW=$(date +%s)
  echo "— Heartbeat: $((NOW - HB_TS))с назад ($(cat .harness/hooks-heartbeat))"
else
  echo "— Heartbeat: НЕТ (ни один хук ни разу не сработал в этом проекте)"
fi
echo "— Краши сторожей: $(ls .harness/hook-crashes/ 2>/dev/null | tr '\n' ' ' || echo нет)"
[ -f .harness/hooks-disabled ] && echo "— ⚠️ hooks-disabled: backstop ОСОЗНАННО выключен"
[ -f .git/hooks/pre-commit ] && grep -q "Vibe Dev" .git/hooks/pre-commit 2>/dev/null \
  && echo "— pre-commit backstop: установлен" || echo "— pre-commit backstop: НЕ установлен"
echo "— Claude Code: $(claude --version 2>/dev/null || echo '(CLI не найден)')"
claude plugin list 2>/dev/null | grep -i vibe || echo "— Плагин: не виден в claude plugin list (или команда недоступна)"
```

## Шаг 2: Диагноз по таблице

| Симптом | Диагноз | Лечение |
|---|---|---|
| Профиль `pending-*` + heartbeat НЕТ | Хуки не работали ни разу: плагин не установлен/не включён, или сессия не в этой папке | `claude plugin list` → установить/включить; перезапустить сессию В папке проекта; первое сообщение активирует |
| Профиль `strict/standard` + heartbeat старше 30 мин | В ТЕКУЩЕЙ сессии хуки не работают (плагин выключили? `--safe-mode`? сессия в другой папке?) | Перезапустить сессию в папке проекта; проверить, что плагин enabled |
| Краши сторожей в `.harness/hook-crashes/` | Сторож падал — его проверки в те моменты НЕ выполнялись | Открыть лог, починить причину (или сообщить о баге плагина), удалить лог |
| pre-commit backstop НЕ установлен | Независимого канала нет — «театр строгости» не ловится на коммитах | `bash "${CLAUDE_PLUGIN_ROOT}/scripts/install-precommit.sh" "$(pwd)"` |
| `hooks-disabled` существует | Backstop выключен осознанно | Если работа в Claude Code возобновилась — удалить файл |
| Установлен мажор > пин проекта | Профиль проекта отстаёт от новой строгости плагина (код хуков применяется сразу, пин — нет) | `/upgrade-project` (dry-run → перечитает пин, применит новую строгость) |
| Всё зелёное | Enforcement жив | Ничего не делать |

## Шаг 3: Доложить пользователю

Одной короткой сводкой без жаргона: «сторожа работают» / «сторожа НЕ работают, причина — X,
чиню так-то». Если чинится командой — выполни сам и перепроверь Шаг 1, потом докладывай.

## Границы честности

- Heartbeat пишут SessionStart и UserPromptSubmit: свежий heartbeat = хуки этих событий живы.
  Это сильное свидетельство и для остальных (один hooks.json), но не прямой тест каждого.
- Диагностика читает артефакты; она не может «включить» плагин сама — включение делает
  пользователь/рестарт сессии. Команды для этого давай готовыми, выполняй что можешь сам.
