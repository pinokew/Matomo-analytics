# Privacy & Compliance — Matomo Analytics

## 1. Призначення

Цей документ фіксує privacy-first baseline для Matomo Analytics і слугує коротким operational reference для перевірки GDPR-вимог перед Go-Live.

Поточна модель проєкту:

- cookieless tracking увімкнено;
- IP-адреси анонімізуються;
- Do Not Track поважається;
- raw logs зберігаються 12 місяців;
- агреговані архіви не видаляються;
- секрети не зберігаються в git і беруться тільки з `.env`.

## 2. Privacy baseline

### 2.1 Обов'язкові вимоги

- **Cookieless Tracking:** увімкнено глобально в Matomo.
- **IP Anonymization:** маскування 2 байтів IP.
- **Do Not Track:** увімкнено.
- **Data Retention:** сирі логи зберігаються 12 місяців; агреговані звіти не видаляються.
- **No public ports:** стек Matomo не публікує порти напряму на хості.
- **Secrets in env only:** `.env` є єдиним джерелом секретів; файл не комітиться в git.

### 2.2 Канонічні значення

Згідно з roadmap і changelog, для production-ready стану мають бути застосовані такі значення:

| Налаштування | Значення |
| --- | --- |
| `PrivacyManager.forceCookielessTracking` | `1` |
| `PrivacyManager.ipAnonymizerEnabled` | `1` |
| `PrivacyManager.ipAddressMaskLength` | `2` |
| `Tracker.ignore_visits_do_not_track` | `1` |
| `delete_logs_older_than` | `365` |
| `delete_reports_enable` | `0` |

## 3. Де це реалізовано

### 3.1 У Matomo

Очікувані значення в Admin UI:

- `Administration -> Privacy -> Anonymize IP = Mask 2 bytes`
- `Administration -> Privacy -> Cookieless Tracking = Enabled`
- `Administration -> Privacy -> Honor Do Not Track = Enabled`
- `Administration -> Privacy -> Delete raw logs after = 12 months`
- `Administration -> Privacy -> Keep aggregated reports = Never delete`

### 3.2 У JS tracker snippets

Privacy вимоги підтримуються також на рівні клієнтських сніппетів:

- Koha snippet викликає `disableCookies()` і `setDoNotTrack(true)`.
- DSpace snippet викликає `disableCookies()` і `setDoNotTrack(true)`.

Це потрібно для того, щоб privacy baseline не залежав лише від UI-налаштувань Matomo.

### 3.3 У репозиторії

- [docker-compose.yaml](docker-compose.yaml) не містить `ports:` для Matomo-стеку.
- [scripts/verify-env.sh](scripts/verify-env.sh) вимагає `MATOMO_API_TOKEN` та backup/security змінні.
- [scripts/apply-matomo-config.sh](scripts/apply-matomo-config.sh) застосовує `Tracker.ignore_visits_do_not_track=1` і вимикає browser-triggered archiving.

## 4. Операційна перевірка перед Go-Live

### 4.1 Browser / DevTools

Перевірити вручну:

1. Відкрити Koha OPAC і DSpace у browser.
2. У `Application -> Cookies` переконатися, що `_pk_*` cookies відсутні.
3. У `Network` перевірити, що tracker йде на замаскований endpoint `/js/ping`.
4. У `Console` перевірити відсутність CSP-помилок.

### 4.2 Matomo UI

Перевірити вручну:

1. `Administration -> Privacy` — значення відповідають таблиці вище.
2. `Administration -> General Settings -> Archiving Settings`:
   - `Browser triggered archiving = Disabled`
3. `Real-Time`:
   - IP відображається в анонімізованому форматі `x.x.0.0`.

### 4.3 Host / Repo

Перевірити вручну:

```bash
bash scripts/verify-env.sh .env
bash scripts/check-ports-policy.sh docker-compose.yaml
git status --ignored | grep -E '^!! \.env$' || true
```

Очікування:

- `.env` не відстежується git;
- обов'язкові env-змінні задані;
- публічних портів немає.

## 5. MATOMO_API_TOKEN handling

`MATOMO_API_TOKEN` використовується для технічних перевірок і має оброблятись як секрет.

Обов'язкові правила:

- зберігати тільки в `.env` на хості;
- права на `.env` — `600`;
- не логувати значення токена;
- не передавати в commit, changelog чи документацію;
- не використовувати в прикладах з реальним значенням.

## 6. Відомі межі

- Відсутність `_pk_*` cookies треба підтверджувати саме в браузері; з repo це не доводиться.
- IP masking підтверджується в Matomo Real-Time або через API/SQL-перевірку, але не тільки з коду репозиторію.
- GDPR-відповідність залежить не лише від Matomo-конфігурації, а й від локальних політик установи, legal notice та доступів персоналу.

## 7. Статус

Станом на поточну ітерацію документація privacy/compliance для Go-Live Gate у repo присутня.
Фактична live-валідація браузерних симптомів і Matomo UI має виконуватись окремо перед оголошенням production-ready статусу.