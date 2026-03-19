# 📊 Product Requirements Document (PRD): Централізована система аналітики Matomo

**Статус:** Draft / На затвердженні  
**Версія:** 1.3 (синхронізовано з `docs/ROADMAP.md`)  
**Дата:** Березень 2026  
**Власник продукту:** DevOps / System Admin Team  
**Цільові системи:** Koha LMS, DSpace 9, Web-портали установи

---

## 1. Контекст і цілі

### 1.1 Мета проєкту

Розгорнути production-ready, безпечну та незалежну систему аналітики на базі Matomo як єдиний центр збору статистики для Koha OPAC, DSpace 9 та наступних цифрових сервісів установи.

### 1.2 Проблема

Фрагментована або зовнішня аналітика (напр. GA4) створює ризики для Patron Privacy, ускладнює GDPR-compliance і суперечить політиці Security-First.

### 1.3 Product Outcome

До Go-Live система має забезпечити:

- централізовану multi-site аналітику (мінімум Koha + DSpace);
- privacy-first збір (cookieless, IP anonymization, DNT);
- production-експлуатацію (CLI archiving, backup, retention, базовий моніторинг);
- керований доступ персоналу через SSO (MS365 / Entra ID).

---

## 2. Scope та пріоритети

### 2.1 In Scope

- Docker Compose стек Matomo: `mariadb:11` + `matomo:apache` + `matomo-cron (fpm-alpine)`.
- Ingress через зовнішній серверний ingress/tunnel шар → Traefik у мережі `proxy-net`; у межах цього репозиторію керуємо лише підключенням `matomo-app` до `proxy-net` і Traefik labels.
- AdBlock mitigation через Traefik `ReplacePathRegex` для `/js/app.js` і `/js/ping`.
- Інтеграція Koha через `patch-koha-templates.sh` (patch-based, ідемпотентно).
- Інтеграція DSpace 9 (Angular), включно з Site Search і download tracking.
- CSP для Koha/DSpace (Report-Only → enforcement).
- Backup 3-2-1 (локально + Google Drive/rclone), retention policy, SSO, базові дашборди.

### 2.2 Out of Scope

- Аналітика серверних логів (ELK/інший окремий стек).
- Розробка кастомних Matomo-плагінів.
- Jaeger/Tempo/розподілене трасування.
- Alertmanager/PagerDuty інтеграція.

---

## 3. Бізнес-цілі та KPI

| Бізнес-ціль | KPI / Критерій успіху |
| --- | --- |
| Data Privacy & Compliance | 100% cookieless tracking, IP masking (2 bytes), DNT enabled |
| Уніфікація аналітики | Koha (Site ID 1) і DSpace (Site ID 3) у єдиній Matomo-панелі |
| Точність каталожної аналітики | Koha Site Search (`q`) відстежується стабільно; ціль >95% пошукових сесій |
| Точність репозитарної аналітики | DSpace search (`query/filter`) + bitstream downloads фіксуються в Matomo |
| Performance | `matomo.js` завантажується < 200ms; коректні Cache-Control заголовки |

---

## 4. Архітектурні вимоги

### 4.1 Принципи

- env-SSOT: всі змінні й секрети в `.env` (не в git).
- Immutable Deployments: конфігурація через env/volumes, без ручного редагування контейнерів.
- No public ports: зовнішній доступ тільки через зовнішній ingress-шар → Traefik.
- Security-First + Privacy-First.

### 4.2 Цільова топологія

- `matomo-app` (мережі: `matomonet` + `proxy-net`) — єдина точка входу в стек.
- `matomo-db` і `matomo-cron` — тільки в `matomonet (internal: true)`.
- Зовнішній ingress/tunnel шар працює поза цим репозиторієм і всі його зовнішні роуті дивляться на `http://traefik:80`.
- Matomo не має прямого мережевого доступу до Koha-мережі; взаємодія тільки через browser tracker.

### 4.3 Security baseline

- `security_opt: [no-new-privileges:true]` для контейнерів.
- `cap_drop: [ALL]` не вводиться до окремого staged-аудиту (Post-Prod).
- Gitleaks/CI блокує секрети в git history.

---

## 5. Функціональні вимоги (FR)

### FR1 — Multi-site management

- Site ID 1: Koha OPAC.
- Site ID 3: DSpace Repository.

### FR2 — Privacy-First tracking (Critical)

- IP anonymization: mask 2 bytes.
- Cookieless tracking: обов'язкове `disableCookies()` у всіх сніппетах.
- Do Not Track: enabled.

### FR3 — Site Search tracking

- Koha: query parameter `q`.
- DSpace: query `query`, category/filter `filter`.

### FR4 — Downloads tracking

- DSpace bitstream URL pattern: `/bitstream/handle/...`.
- Мінімум: `enableLinkTracking()` + Download URL patterns.
- Розширення (за потреби): Angular router events + `trackLink()`.

### FR5 — Tracker masking / AdBlock mitigation

- Трекер URL у клієнті: `https://analytics.mylibrary.edu/js/ping`.
- Traefik middleware:
  - `^/js/app.js$` → `/matomo.js`
  - `^/js/ping$` → `/matomo.php`

### FR6 — Koha integration method (обов'язково)

- Інтеграція виконується patch-based через `patch-koha-templates.sh` або еквівалентний модуль `scripts/patch/patch-koha-matomo.sh`.
- Вимоги: ідемпотентність, відсутність дублювання сніппету, відтворюваність після оновлень контейнерів.

### FR7 — Access control

- До Go-Live має бути увімкнено SSO (MS365 / Entra ID, LoginSaml).
- Один локальний fallback-адмін дозволено і має бути задокументований.

---

## 6. Нефункціональні вимоги (NFR)

### NFR1 — Security

- CSP для Koha/DSpace: мінімум `script-src`, `connect-src`, `img-src` з `https://analytics.mylibrary.edu`.
- Впровадження CSP тільки через послідовність Report-Only → аудит violations → enforcement.

### NFR2 — Backup & Retention

- Щоденний бекап MariaDB (`.sql.gz`) локально + копія в Google Drive через rclone.
- `backup.sh` підтримує `--dry-run`, працює env-driven без hardcode.
- Retention: raw logs = 12 months; archives = never delete.

### NFR3 — Archiving & Performance

- Browser-triggered archiving = OFF.
- CLI archiving виконується щогодини (`matomo-cron`), лог містить `Done archiving!`.
- `matomo.js` має коректний cache-control і цільове завантаження < 200ms.

### NFR4 — Мінімальний операційний моніторинг

- Джерело метрик: VictoriaMetrics (single source of metrics для host/container/service checks).
- Алертинг: Grafana Alerting (усі operational alerts визначаються та маршрутизуються через Grafana).
- Health & availability метрики: `matomo_up`/`probe_success` і `matomo_db_health`; алерт при неуспіху понад 5 хв.
- Capacity monitoring для `VOL_DB_PATH`, `VOL_MATOMO_DATA`, `BACKUP_DIR` з warning/critical порогами з env.
- Archiving freshness: алерт, якщо `matomo_archiving_last_success_timestamp` прострочений > 2 год.
- Backup freshness: алерт, якщо `matomo_backup_last_success_timestamp` прострочений > 26 год (щоденний backup).
- Restore readiness: алерт, якщо `matomo_restore_smoke_last_success_timestamp` прострочений > 8 діб (щотижневий smoke restore).

---

## 7. План реалізації (Rollout Phases)

### Phase 1 — Pre-Prod Foundation (P0, T+0 → T+3 дні)

- Підняти стек, мережі, Traefik labels, `.env` SSOT, verify/check scripts, CI checks.
- Вихід: Matomo доступний за `https://analytics.mylibrary.edu`, всі сервіси `Up/healthy`, публічні порти відсутні.

### Phase 2 — Production-Ready Minimum (P0, T+3 → T+10 днів)

- Privacy policy в Matomo, Koha tracker + CSP через patch script, backup + rclone, SSO, data retention.
- Вихід: Koha дані видимі в Real-Time, cookieless підтверджено, archiving/backup/SSO працюють.

### Phase 3 — DSpace 9 Integration (P1, T+10 → T+17 днів)

- Site ID 3, інтеграція в Angular UI, bitstream tracking, CSP для DSpace.
- Вихід: downloads + search з DSpace відстежуються, `_pk_*` cookies відсутні.

### Phase 4 — Production Readiness & Go-Live (P0/P1, T+17 → T+21 днів)

- Прохід повного Go-Live Gate, executive dashboard, обов'язкова документація.

---

## 8. Go-Live acceptance criteria (витяг)

Система не вважається production-ready без виконання всіх груп критеріїв:

- Security & Privacy: cookieless, IP mask, DNT, no public ports, зовнішній ingress до Traefik активний, SSO готовий.
- Performance & Archiving: `matomo.js < 200ms`, browser archiving off, CLI archiving ok.
- Tracking: Koha search, DSpace downloads, Custom Dimension (Device Type) записуються.
- Data & Backup: локальний + remote backup підтверджено, retention policy активна.
- CSP: 0 критичних violations у Koha і DSpace (після переходу з Report-Only).

---

## 9. Ризики та відкриті питання

### Основні ризики

- CSP може порушити рендеринг (мітигація: staged rollout через Report-Only).
- Часткова втрата трафіку через adblock (мітигація: masked tracker URL через Traefik).
- Неправильне мапування ролей у SSO (мітигація: тестовий акаунт до відключення локального входу).

### Open Questions (актуальні)

- DSpace 9 bitstream routing: достатньо `enableLinkTracking()` чи потрібен router-level `trackLink()`.
- Підтвердження політики зберігання `MATOMO_API_TOKEN` у `.env` (права, логування, доступ).

---

## 10. Узгодження документів

Цей PRD синхронізований із `docs/ROADMAP.md` версії 1.3.  
У випадку майбутніх розбіжностей операційний пріоритет має `docs/ROADMAP.md`.