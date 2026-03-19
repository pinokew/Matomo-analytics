# Backup & Restore Runbook — Matomo Analytics

**Version:** 1.0  
**Date:** 2026-03-17  
**Owner:** DevOps / System Admin  

---

## 1. Overview

Цей runbook описує процедури резервного копіювання (backup) та відновлення (restore) Matomo Analytics бази даних. Стратегія ґрунтується на моделі **3-2-1**:

- **Рівень 1:** локальний `.sql.gz` архів у `$BACKUP_DIR` на хості
- **Рівень 2:** автоматичне завантаження на Google Drive через `rclone`
- **Рівень 3:** адміністративна відповідальність (NAS, офсайт-сховище)

**Basis for automation:**
- `scripts/backup.sh` — повний цикл dump/compress/upload/prune
- `scripts/restore.sh` — безпечне відновлення з комфортом та санітарною перевіркою
- `docker compose` — управління контейнерами Matomo та MariaDB

---

## 2. Prerequisites

### Залежності на хості

```bash
# Перевірити наявність命令:
command -v docker
command -v docker-compose
command -v rclone
command -v mysqldump (встановлено в контейнері)
```

### Environment variables в `.env`

```bash
# Database
DB_ROOT_PASS=<root_password>
DB_NAME=matomo
DB_USER=matomo
DB_PASS=<user_password>

# Volumes
VOL_DB_PATH=/srv/Matomo/./.data/db
VOL_MATOMO_DATA=/srv/Matomo/./.data/matomo

# Backup
BACKUP_DIR=/srv/Matomo/./.backups
BACKUP_RETENTION_DAYS=14

# Backup metrics (optional, node-exporter textfile collector)
NODE_EXPORTER_TEXTFILE_DIR=/srv/Matomo/./.data/node-exporter-textfile
BACKUP_METRICS_FILE=matomo_backup.prom
BACKUP_METRICS_ENV_LABEL=prod
BACKUP_METRICS_SERVICE_LABEL=matomo

# rclone
RCLONE_REMOTE=kdv-drive                    # remote name (e.g., Google Drive)
RCLONE_DEST_PATH=KDV_Backups/Matomo        # path relative to remote root
```

### Перевірка налаштування

```bash
# Перевірити, що контейнери запущені
docker compose ps
# Output should show: matomo-db (Healthy), matomo-app, matomo-cron

# Перевірити доступ до rclone remote
rclone lsf "${RCLONE_REMOTE}:/"
# Output should list directories in remote

# Перевірити env
bash scripts/verify-env.sh
# Output: "Environment validation passed"
```

---

## 3. Backup Procedure

### 3.1 Автоматичний backup (Cron)

**Рекомендуємо:** запланuvati щоденний backup через `systemd timer` або `crontab`.

```bash
# Приклад systemd timer (створюється окремо з Koha-стеку):
# /etc/systemd/system/matomo-backup.service
# /etc/systemd/system/matomo-backup.timer

# Або ручну запис у crontab (root або sudo):
0 2 * * * cd /home/pinokew/Matomo-analytics && bash scripts/backup.sh
# Це запускає backup щодня в 02:00
```

### 3.2 Ручний backup

```bash
cd /home/pinokew/Matomo-analytics

# Перевірити (dry-run) перед реальним виконанням
bash scripts/backup.sh --dry-run

# Виконати реальний backup
bash scripts/backup.sh
```

**Вивід:**

```
[backup] ENV loaded from: .env
[backup] target file: /srv/Matomo/./.backups/matomo_matomo_20260317_113822.sql.gz
[backup] retention days: 14
[backup] remote: kdv-drive:KDV_Backups/Matomo
[backup] creating database dump...
[backup] uploading to remote...
[backup] pruning local backups older than 14 days...
[backup] completed: /srv/Matomo/./.backups/matomo_matomo_20260317_113822.sql.gz
-rw-rw-r-- 1 user user 38K Mar 17 11:38 /srv/Matomo/./.backups/matomo_matomo_20260317_113822.sql.gz
```

### 3.3 Перевірка backup

```bash
# Локальна перевірка
ls -lh $BACKUP_DIR/matomo_*.sql.gz

# Перевірка на remote
rclone lsf "kdv-drive:KDV_Backups/Matomo"

# Перевірка розміру архіву
du -h /srv/Matomo/./.backups/matomo_*.sql.gz

# Перевірка метрик backup
tail -n 20 /srv/Matomo/./.data/node-exporter-textfile/matomo_backup.prom
# Очікувані метрики:
# - matomo_backup_last_run_timestamp
# - matomo_backup_last_success_timestamp
# - matomo_backup_last_status (1=success, 0=failure)
```

---

## 4. Restore Procedure

### 4.1 Підготовка (перед restore)

**⚠️ УВАГА:** Restore **перезапишет** БД. Це необоротна операція!

1. **Резервне копіювання поточної БД** (на випадок помилки):
   ```bash
   bash scripts/backup.sh
   ```

2. **Вибір backup-файлу:**
   ```bash
   # Перелічити доступні backup'и
   ls -1 /srv/Matomo/./.backups/matomo_*.sql.gz | sort -V
   
   # Найнешиший backup
   ls -1 /srv/Matomo/./.backups/matomo_*.sql.gz | sort -V | tail -1
   ```

3. **Вибір резервного копіювання з Google Drive (якщо потрібно):**
   ```bash
   # Звантажити з remote
   BACKUP_FILE="/tmp/matomo_restore.sql.gz"
   rclone copy "kdv-drive:KDV_Backups/Matomo/matomo_matomo_20260317_113822.sql.gz" "$BACKUP_FILE"
   ```

### 4.2 Виконання restore

```bash
cd /home/pinokew/Matomo-analytics

# Перевірка (зміст не змінюється):
bash scripts/restore.sh --help
# Output: "Usage: scripts/restore.sh [--force] <backup-file.sql.gz|backup-file.sql>"

# Интерактивный режим (з підтвердженням):
bash scripts/restore.sh /srv/Matomo/./.backups/matomo_matomo_20260317_113822.sql.gz
# Буде запита: "WARNING: restore will overwrite data in DB 'matomo'. Type YES to continue: "
# Введіть: YES

# Non-interactive режим (для CI/automation, потребує --force):
bash scripts/restore.sh --force /srv/Matomo/./.backups/matomo_matomo_20260317_113822.sql.gz
```

**Вивід успішного restore:**

```
[restore] ENV loaded from: .env
[restore] source backup: /srv/Matomo/./.backups/matomo_matomo_20260317_113822.sql.gz
[restore] target database: matomo
[restore] importing dump...
[restore] running post-restore sanity query...
[restore] completed successfully
```

### 4.3 Перевірка після restore

1. **Базова перевірка БД:**
   ```bash
   # Перелічити таблиці
   docker compose exec -T -e MYSQL_PWD=$DB_ROOT_PASS matomo-db \
     mariadb -uroot matomo -e "SHOW TABLES;"
   
   # Перевірити кількість записів (приклад)
   docker compose exec -T -e MYSQL_PWD=$DB_ROOT_PASS matomo-db \
     mariadb -uroot matomo -e "SELECT COUNT(*) FROM log_visit;"
   ```

2. **Вебасний інтерфейс:**
   - Перейти на https://matomo.pinokew.buzz
   - Перевірити login з адмін-акаунтом
   - Перевірити, що сайти (Site ID 1, 3) присутні
   - Перевірити налаштування (Privacy, Archiving, тощо)

3. **Real-Time дашборд:**
   - Admin → Dashboard → Real-Time
   - Мають відобразитись попередні трафіки (якщо є)

4. **Логи контейнерів:**
   ```bash
   docker compose logs matomo-db | tail -20
   docker compose logs matomo-app | tail -20
   ```

---

## 5. Disaster Recovery Scenarios

### Сценарій A: Локальна БД пошкоджена

```bash
# 1. Создать свежий диск (видалити)/або новий контейнер
docker compose down
rm -rf /srv/Matomo/./.data/db/*

# 2. Інініціалізувати томи
bash scripts/init-volumes.sh .env

# 3. Запустити контейнери (MariaDB ініціалізує нову БД)
docker compose up -d

# 4. Дочекатися, поки matomo-db стане Healthy
docker compose ps | grep matomo-db

# 5. Виконати restore з backup'а
bash scripts/restore.sh --force /srv/Matomo/./.backups/matomo_matomo_<latest>.sql.gz
```

### Сценарій B: Потрібно відновити з Google Drive

```bash
# 1. Завантажити backup з Google Drive
BACKUP_FILE="/tmp/matomo_restore_from_drive.sql.gz"
rclone copy "kdv-drive:KDV_Backups/Matomo/matomo_matomo_<date>.sql.gz" "$BACKUP_FILE"

# 2. Перевірити, що файл завантажився
ls -lh "$BACKUP_FILE"

# 3. Виконати restore
bash scripts/restore.sh --force "$BACKUP_FILE"

# 4. Видалити тимчасовий файл
rm "$BACKUP_FILE"
```

### Сценарій C: Rollback до попередньої версії

```bash
# 1. Перелічити локальні backup'и за датою
ls -1 /srv/Matomo/./.backups/matomo_*.sql.gz | sort -rV

# 2. Вибрати та перевірити розмір попереднього backup'а
ls -lh /srv/Matomo/./.backups/matomo_matomo_20260316_*.sql.gz

# 3. Виконати restore
BACKUP_FILE="/srv/Matomo/./.backups/matomo_matomo_20260316_023045.sql.gz"
bash scripts/restore.sh --force "$BACKUP_FILE"
```

---

## 6. Retention Policy & Cleanup

### Автоматична очистка (вбудована в backup.sh)

`backup.sh` автоматично видаляє локальні архіви старші за `BACKUP_RETENTION_DAYS` (default: 14 днів).

---

## 7. Restore Smoke Test Metrics (VictoriaMetrics/Grafana)

Для контролю відновлюваності використовується окремий smoke test restore у тимчасовий MariaDB контейнер.

```bash
cd /home/pinokew/Matomo-analytics

# Базовий запуск (бере останній backup із BACKUP_DIR)
bash scripts/test-restore.sh

# Явно вказати backup файл
bash scripts/test-restore.sh /srv/Matomo/./.backups/matomo_matomo_20260317_113822.sql.gz

# Dry-run для перевірки пайплайна запису метрик
bash scripts/test-restore.sh --dry-run
```

Скрипт записує метрики у textfile collector (`NODE_EXPORTER_TEXTFILE_DIR`):

- `matomo_restore_smoke_last_run_timestamp`
- `matomo_restore_smoke_last_success_timestamp`
- `matomo_restore_smoke_last_status` (1=success, 0=failure)

Рекомендовано запускати щотижня (наприклад, через systemd timer) і будувати Grafana alert на прострочку `matomo_restore_smoke_last_success_timestamp > 8 діб`.

```bash
# Поточна регуляція:
find "$BACKUP_DIR" -maxdepth 1 -type f -name "matomo_${DB_NAME}_*.sql.gz" \
  -mtime +"$BACKUP_RETENTION_DAYS" -delete
```

### Ручна очистка

```bash
# Видалити архіви старші за 30 днів
find /srv/Matomo/./.backups -name "*.sql.gz" -mtime +30 -delete

# Видалити архіви певної дати
rm /srv/Matomo/./.backups/matomo_matomo_202603*.sql.gz
```

### Google Drive очистка (опціонально)

```bash
# Перелічити всі backup'и на remote
rclone lsf "kdv-drive:KDV_Backups/Matomo" -R

# Видалити старі файли з Google Drive (ручно або через rclone sync)
rclone delete "kdv-drive:KDV_Backups/Matomo" --min-age 90d
```

---

## 7. Monitoring & Alerting

### Periodic Health Checks

```bash
# Script: matomo-backup-health-check.sh (рекомендується в cron)

#!/bin/bash
BACKUP_DIR="/srv/Matomo/./.backups"
LATEST_BACKUP=$(ls -1t "$BACKUP_DIR"/matomo_*.sql.gz 2>/dev/null | head -1)
HOURS_SINCE_BACKUP=$(( ($(date +%s) - $(stat -c %Y "$LATEST_BACKUP" 2>/dev/null || echo 0)) / 3600 ))

if [[ $HOURS_SINCE_BACKUP -gt 48 ]]; then
  echo "WARNING: Latest backup is ${HOURS_SINCE_BACKUP} hours old"
  # Отправить email/webhook
else
  echo "OK: Latest backup is ${HOURS_SINCE_BACKUP} hours old"
fi
```

### Log Monitoring

```bash
# Перевірити cron-архівацію в matomo-cron
docker compose logs matomo-cron | grep "Done archiving"

# Перевірити помилки в matomo-app
docker compose logs matomo-app | grep ERROR
```

---

## 8. Troubleshooting

| Проблема | Причина | Рішення |
|---|---|---|
| `backup.sh: command not found` | Скрипт не executable або неправильний shebang | `chmod +x scripts/backup.sh && bash -n scripts/backup.sh` |
| `ERROR: could not access service 'matomo-db'` | docker compose не запущена або контейнер не готовий | `docker compose ps && docker compose logs matomo-db` |
| `rclone copy: 404 not found` | Неправильний шлях на remote або remote не налаштований | `rclone listremotes && rclone lsf kdv-drive:/` |
| `Restore: syntax error in SQL` | Версія MariaDB/SQL несумісна | Перевірити version: `docker-compose exec -T matomo-db mariadb --version` |
| `Permission denied` при очистці томів | Docker volumes належать контейнеру UID (33 або 999) | Використовувати `docker run --rm -v ... alpine rm -rf` |
| Restore завис | Великий архів або повільне io | Перевірити: `docker stats`, дисковий простір, сіть rclone |

---

## 9. Testing & Validation

### Тестування restore в окремому середовищі

```bash
# 1. Создать нова .env для тестування
cp .env .env.test-restore
sed -i 's|VOL_DB_PATH=.*|VOL_DB_PATH=/srv/Matomo/./.data-test/db|' .env.test-restore
sed -i 's|VOL_MATOMO_DATA=.*|VOL_MATOMO_DATA=/srv/Matomo/./.data-test/matomo|' .env.test-restore

# 2. Инициализировать томы
ENV_FILE=.env.test-restore bash scripts/init-volumes.sh .env.test-restore

# 3. Запустить контейнери
ENV_FILE=.env.test-restore docker compose up -d

# 4. Дочекатися, поки healthy
sleep 30 && docker compose ps

# 5. Выполнить restore
ENV_FILE=.env.test-restore bash scripts/restore.sh --force /srv/Matomo/./.backups/matomo_matomo_<latest>.sql.gz

# 6. Проверить данные в тестовому окружении

# 7. Остановить и очистить
ENV_FILE=.env.test-restore docker compose down
rm -rf /srv/Matomo/./.data-test
rm .env.test-restore
```

---

## 10. Emergency Contacts & Escalation

| Сценарій | Контакт | Дія |
|---|---|---|
| DB недоступна | DevOps | 1. Перезапустити matomo-db; 2. Перевірити logs; 3. Якщо не допомагає → restore |
| Диск повний | Sysadmin | 1. Видалити старі backup'и: `find ... -mtime +30 -delete` 2. Перевірити `du -sh /srv/Matomo/` |
| rclone не завантажує | Network/DevOps | 1. `rclone version` 2. `rclone config` 3. Ручна upload на Google Drive |
| Restore не встає | DevOps | Див. Troubleshooting розділ 8 |

---

## 11. Appendix: Script Usage Reference

### backup.sh

```bash
Usage: bash scripts/backup.sh [--dry-run]

Environment Variables:
  ENV_FILE (default: .env)

Options:
  --dry-run        Show what would be executed without changing anything

Exit Codes:
  0 — success
  1 — error (missing var, docker not accessible, etc.)

Example:
  bash scripts/backup.sh                    # Real backup
  bash scripts/backup.sh --dry-run          # Dry-run, no changes
  ENV_FILE=.env.prod bash scripts/backup.sh # Use custom env
```

### restore.sh

```bash
Usage: bash scripts/restore.sh [--force] <backup-file>

Arguments:
  <backup-file>    Path to .sql or .sql.gz file (required)

Options:
  --force          Skip interactive confirmation (useful for CI/cron)
  -h, --help       Show usage

Environment Variables:
  ENV_FILE (default: .env)

Exit Codes:
  0 — success
  1 — error or user canceled

Example:
  bash scripts/restore.sh /srv/Matomo/./.backups/matomo_matomo_20260317_113822.sql.gz
  bash scripts/restore.sh --force /tmp/matomo_backup.sql.gz
  ENV_FILE=.env.test bash scripts/restore.sh /tmp/test_backup.sql
```

### verify-env.sh

```bash
Usage: bash scripts/verify-env.sh [env-file]

Arguments:
  [env-file]       Path to .env file (default: .env)

Exit Codes:
  0 — validation passed
  1 — validation failed

Example:
  bash scripts/verify-env.sh         # Check default .env
  bash scripts/verify-env.sh .env.prod
```

---

## 12. Версії та історія

| Версія | Дата | Зміни |
|---|---|---|
| 1.0 | 2026-03-17 | Первинна версія; backup/restore/retention; disaster recovery |

**Контакт для оновлень:** DevOps Team
