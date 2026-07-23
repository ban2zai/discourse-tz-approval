# discourse-tz-approval

Плагин Discourse для профильного одобрения тем. Базовый профиль — «ТЗ» с prefix `tz`; остальные профили создаются админом на странице `/admin/plugins/tz-approval`.

## Что делает плагин

- Добавляет кнопку одобрения/снятия одобрения в подвал темы.
- Показывает статус одобрения в списке тем, заголовке темы, первом посте и small action сообщениях.
- Хранит состояние в `TopicCustomField` с prefix профиля:
  - `tz_approved`;
  - `tz_approved_by_id`;
  - `tz_approved_at`;
  - `tz_approval_post_id`.
- Для нового профиля с prefix `second_line` поля будут:
  - `second_line_approved`;
  - `second_line_approved_by_id`;
  - `second_line_approved_at`;
  - `second_line_approval_post_id`.
- Добавляет search-фильтры вида `status:<prefix>-approved` и `status:<prefix>-unapproved`.
- Оставляет старые endpoints `/tz-approval/approve` и `/tz-approval/unapprove`.
- Не владеет внешним GUID темы. GUID lookup должен жить в плагине `discourse-new-topic-field`; этот плагин принимает `topic_id` и возвращает только статус одобрения.

## Настройки

Глобальные настройки остаются в `config/settings.yml`:

| Настройка | Что делает |
| --- | --- |
| `tz_approval_enabled` | Включает/выключает механизм. |
| `tz_author_approval_delay` | Задержка, после которой автор темы может сам одобрить свою тему. |
| `tz_approval_binding_mode` | Legacy seed-настройка дефолтного профиля ТЗ: `tag` или `category`. |
| `tz_approval_tags` | Legacy tags для seed дефолтного ТЗ-профиля. |
| `tz_approval_categories` | Legacy categories для seed дефолтного ТЗ-профиля. |
| `tz_approval_allowed_groups` | Legacy groups для seed дефолтного ТЗ-профиля. |
| `tz_approval_icon` | Legacy icon для seed дефолтного ТЗ-профиля. |
| `tz_approval_status_token` | Secret token для server-to-server status endpoint. |

Новые профили настраиваются в админке, а не через `SiteSetting`.

## Как создать профиль

Открой:

```text
/admin/plugins/tz-approval
```

Нажми **Новый профиль** и заполни:

- `key` — внутренний ключ, например `second_line`;
- `prefix` — prefix для API/БД, например `second_line`;
- `label` — название в интерфейсе, например `Вторая линия`;
- `priority` — чем меньше число, тем раньше профиль применяется при пересечении категорий;
- `binding_mode` — `category` или `tag`;
- `Требовать GUID задачи` — для category-профиля запрещает не-администраторам создавать и
  переносить темы без связи с задачей;
- `categories` или `tags` — условия применимости;
- `approval groups` — группы, которые могут одобрять/снимать одобрение;
- `icon` — зарегистрированная SVG-иконка Discourse/FontAwesome;
- тексты кнопок, плашек, system post и notification description.

Prefix после создания не редактируется. Если нужен другой prefix, создай новый профиль: старые `TopicCustomField` уже записаны под прежним именем.

После создания нового профиля перезапусти Discourse, чтобы зарегистрировать типы custom fields и быстрые status-фильтры. Прелоад полей в списках тем работает динамически и подхватывает новый профиль без рестарта.

## Правила применимости

Для каждой темы выбирается один активный профиль: первый подходящий по `priority`.

Профиль применим, если:

1. `tz_approval_enabled = true`;
2. профиль включен;
3. тема подходит под `binding_mode` профиля:
   - `category` — категория темы есть в списке профиля;
   - `tag` — у темы есть хотя бы один тег из профиля.

Если у effective-профиля с привязкой по категории включено **Требовать GUID задачи**, создание
или перенос темы в такую категорию разрешены только при наличии связи из
`discourse-new-topic-field`. При создании дополнительно проверяются нормализация GUID, подпись и
отсутствие существующей темы с тем же GUID. Администратор и операции создания с
`skip_validations` обходят запрет. Для tag-профиля флаг всегда принудительно выключен.

Зависимость безопасная: отсутствие или отключение `discourse-new-topic-field` не мешает загрузке
плагина, но защищенная операция блокируется.

Одобрить могут:

- staff;
- пользователи из групп профиля;
- автор темы после `tz_author_approval_delay`.

Снять одобрение могут:

- staff;
- пользователи из групп профиля;
- автор темы, если он сам одобрял тему.

## API

Доступные endpoints:

```text
POST /tz-approval/approve
POST /tz-approval/unapprove
GET /approvals/topic-id/:id
GET /approvals/topic-id/:id/:token
```

`POST` endpoints принимают `topic_id`, профиль определяется сервером по теме.

`GET /approvals/topic-id/:id` возвращает server-to-server статус одобрения по `topic_id`. Рекомендуемый способ авторизации — заголовок:

```text
X-TZ-Approval-Token: <token>
```

Legacy URL `GET /approvals/topic-id/:id/:token` остаётся рабочим для существующих интеграций, но токен в path может попадать в access logs. Query-параметр `?token=<token>` тоже поддерживается.

GUID темы в ответ не входит; внешний сервис должен получать связку `guid -> topic_id` из `discourse-new-topic-field`.

Пример ответа:

```json
{
  "success": "OK",
  "approval_profile_key": "second_line",
  "approval_profile_prefix": "second_line",
  "approval_label": "Вторая линия",
  "approval_icon": "clipboard-check",
  "approved": true,
  "approved_by_id": 10,
  "approved_by_username": "moderator",
  "approved_at": "2026-07-04T08:00:00Z",
  "can_approve": false,
  "can_unapprove": true,
  "tz_approved": false
}
```

Для legacy-интеграций профиль ТЗ продолжает возвращать `tz_approved`, `tz_approved_by_id`, `tz_approved_at`, `can_approve_tz`, `can_unapprove_tz`.

## n8n / Data Explorer

Для n8n используй status endpoint выше. Ответ уже содержит `approvals[]` и legacy top-level `tz_*` поля, поэтому отдельные заготовки из папки `n8n/` в репозитории больше не поставляются.

Пустые `TopicCustomField` не создаются заранее: отсутствие `<prefix>_approved` считается `approved: false`.

## Search

Для ТЗ:

```text
status:tz-approved
status:tz-unapproved
```

Для любого нового профиля:

```text
status:<prefix-with-dashes>-approved
status:<prefix-with-dashes>-unapproved
```

Например profile prefix `second_line`:

```text
status:second-line-approved
status:second-line-unapproved
```

## Разработка

Backend:

- `plugin.rb` — profile lookup, serializers, Guardian, search filters, routes;
- `app/models/tz_approval/profile_record.rb` — DB-модель профиля;
- `app/controllers/tz_approval/approvals_controller.rb` — approve/unapprove;
- `app/controllers/tz_approval/admin/profiles_controller.rb` — admin CRUD;
- `app/services/tz_approval/task_guid_requirement.rb` — проверка связи с задачей при создании и переносе;
- `db/migrate/*_create_tz_approval_profiles.rb` — таблица профилей.

Frontend:

- `assets/javascripts/discourse/api-initializers/*` — публичный UI темы;
- `assets/javascripts/admin/components/tz-approval-admin.gjs` — admin CRUD;
- `assets/javascripts/admin/templates/admin-plugins/tz-approval.gjs` — admin page.
