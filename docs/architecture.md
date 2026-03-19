# Architecture — Matomo Analytics

## 1. Призначення

Цей документ описує цільову архітектуру Matomo-стеку для Phase 1 (Pre-Prod Foundation) і є базою для подальших інтеграцій з Koha та DSpace.

## 2. Короткий опис

Matomo розгортається як окремий Docker Compose стек. Зовнішній HTTPS-трафік обробляється спільним серверним ingress/tunnel шаром поза цим репозиторієм і передається до існуючого Traefik у мережі `proxy-net` за адресою `http://traefik:80`. Внутрішня база MariaDB ізольована в `matomonet` і не має прямого публічного доступу.

## 3. Компоненти

- `matomo-db`
  - Образ задається через `MARIADB_IMAGE`.
  - Працює тільки в мережі `matomonet`.
  - Зберігає дані в `VOL_DB_PATH`.
  - Має healthcheck через `mariadb-admin ping`.

- `matomo-app`
  - Образ задається через `MATOMO_IMAGE`.
  - Підключений до `matomonet` і `proxy-net`.
  - Є точкою входу для Traefik.
  - Зберігає Matomo-дані в `VOL_MATOMO_DATA`.

- `matomo-cron`
  - Образ задається через `CRON_IMAGE`.
  - Працює тільки в `matomonet`.
  - Виконує `core:archive` у циклі раз на годину.

## 4. Мережі

- `matomonet`
  - `internal: true`
  - Для `matomo-db`, `matomo-app`, `matomo-cron`
  - Ізолює БД та внутрішні сервіси від зовнішнього доступу

- `proxy-net`
  - `external: true`
  - Для `matomo-app`
  - Використовується для інтеграції з існуючим Traefik

## 5. Потік трафіку

1. Користувач відкриває `https://analytics.mylibrary.edu`.
2. Зовнішній серверний ingress/tunnel шар передає трафік на `http://traefik:80`.
3. Traefik у `proxy-net` маршрутизує запит до `matomo-app` за labels.
4. `matomo-app` працює з `matomo-db` через `matomonet`.

## 6. AdBlock mitigation

У Traefik labels для `matomo-app` налаштовано маскування tracker endpoints:

- `/js/app.js` -> `/matomo.js`
- `/js/ping` -> `/matomo.php`

Це потрібно для подальшої інтеграції Koha/DSpace і зменшення втрат трафіку через блокувальники.

## 7. Security baseline

- Жодних `ports:` у `docker-compose.yaml`.
- Секрети зберігаються тільки в `.env`.
- Для сервісів використовується `no-new-privileges:true`.
- `cap_drop: [ALL]` поки не застосовується.
- Конфігурація образів і параметрів винесена в env, без hardcode.

## 8. Поточний статус Phase 1

Станом на поточну ітерацію підготовлено:

- `docker-compose.yaml`
- `.env.example`
- `.github/workflows/ci-checks.yml`
- `scripts/verify-env.sh`
- `scripts/check-ports-policy.sh`
- `scripts/backup.sh` (каркас)
- `scripts/restore.sh` (каркас)
- `scripts/check-disk.sh`

## 9. Поза межами цього документа

Ще не описуються деталі:

- інтеграція Koha трекера;
- інтеграція DSpace 9;
- CSP rollout;
- SSO configuration;
- повна backup/restore логіка.
