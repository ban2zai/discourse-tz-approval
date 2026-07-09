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
- `categories` или `tags` — условия применимости;
- `approval groups` — группы, которые могут одобрять/снимать одобрение;
- `icon` — зарегистрированная SVG-иконка Discourse/FontAwesome;
- тексты кнопок, плашек, system post и notification description.

Prefix после создания не редактируется. Если нужен другой prefix, создай новый профиль: старые `TopicCustomField` уже записаны под прежним именем.

## Правила применимости

Для каждой темы выбирается один активный профиль: первый подходящий по `priority`.

Профиль применим, если:

1. `tz_approval_enabled = true`;
2. профиль включен;
3. тема подходит под `binding_mode` профиля:
   - `category` — категория темы есть в списке профиля;
   - `tag` — у темы есть хотя бы один тег из профиля.

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
GET /approvals/topic-id/:id/:token
```

`POST` endpoints принимают `topic_id`, профиль определяется сервером по теме.

`GET /approvals/topic-id/:id/:token` возвращает server-to-server статус одобрения по `topic_id`. GUID темы в ответ не входит; внешний сервис должен получать связку `guid -> topic_id` из `discourse-new-topic-field`.

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

Для workflow `topic-status/:topic_id` актуальные заготовки лежат в `n8n/`:

- `topic-status-data-explorer.sql` — запрос Data Explorer, который возвращает одну строку на каждый enabled approval-профиль;
- `topic-status-transform.js` — код n8n Code node, который собирает `approvals[]` и сохраняет legacy top-level `tz_*` поля.

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
- `db/migrate/*_create_tz_approval_profiles.rb` — таблица профилей.

Frontend:

- `assets/javascripts/discourse/api-initializers/*` — публичный UI темы;
- `assets/javascripts/admin/components/tz-approval-admin.gjs` — admin CRUD;
- `assets/javascripts/admin/templates/admin-plugins/tz-approval.gjs` — admin page.
