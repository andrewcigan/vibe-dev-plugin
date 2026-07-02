#!/bin/bash
# Vibe Dev — единый словарь паттернов ЖИВОГО ключа (ОДИН источник, не два).
# Переиспользуется:
#   - hooks/checks/secret-in-prompt.sh  (ключ во ВХОДЯЩЕМ чате пользователя → warn/ротация)
#   - hooks/checks/secret-scan-write.sh (хардкод ключа в src при Write/Edit → block)
# Ловим только форматы БОЕВЫХ ключей (голый "sk-" / любой KEY= шумит — не ловим), чтобы
# тестовые плейсхолдеры (YOUR_KEY, sk-ant-xxx) не давали ложных срабатываний.
VIBE_SECRET_RE='sk-ant-[A-Za-z0-9_-]{10,}|sk-proj-[A-Za-z0-9_-]{10,}|sk-or-v1-[A-Za-z0-9_-]{10,}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[A-Z0-9]{16}|xox[bp]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY'
