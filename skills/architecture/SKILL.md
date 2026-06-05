---
name: architecture
description: V0 архитектура с TOC bottleneck-анализом. Запускает architect (Opus). ≤10 компонентов, Mermaid диаграмма, invariants как constraints, top-3 риска. FAST + FULL обе используют. Триггеры — "/architecture", "архитектура", "spроектируй систему".
when_to_use: После интервью (FAST) или после /research (FULL). Создаёт docs/ARCHITECTURE.md как основу для choose-stack.
---

# /architecture

V0 архитектура через architect agent.

## Что происходит

1. Subagent `architect` (Opus) читает AGENTS.md, PRODUCT.md, domain-rules.yaml, (FULL) research/*
2. Identify bottleneck (TOC) — узкое место для главной функции
3. ≤10 компонентов (Karpathy Simplicity First)
4. Mermaid-диаграмма data flow
5. Invariants из domain-rules → архитектурные constraints
6. Top-3 риска с mitigation

## Output

- `docs/ARCHITECTURE.md`
- `docs/PRODUCT.md` (если ещё не было)

## Stage verifier check

После /architecture — `stage-verifier` подтверждает:
- Bottleneck явно указан
- Компонентов ≤10
- Mermaid присутствует

## Дальше

`/choose-stack` — стек под bottleneck.

## Quality Gate

Финальное сообщение без technical A/B. Прямой: «архитектура готова, узкое место — X, дальше /choose-stack».
