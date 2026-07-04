# discourse-tz-approval

Плагин Discourse для механизма профильного одобрения тем. Базовый профиль — «ТЗ», дополнительный профиль — «Вторая линия». Для каждой темы применяется только один профиль: сначала проверяется ТЗ, затем «Вторая линия».

Целевой стек: Discourse 2026.x, Glimmer topic list, без `.raw.hbs`/старых handlebars-overrides.

## Что делает плагин

- Добавляет кнопку в подвал темы: **«Одобрить ТЗ»** или **«Снять одобрение»**.
- Показывает статус одобрения:
  - иконкой в списке тем рядом со статусами темы;
  - иконкой в заголовке темы;
  - плашкой внутри первого поста;
  - системным small action сообщением в потоке ответов.
- Пишет состояние в `TopicCustomField`, без отдельной таблицы и миграций.
- Для каждого профиля использует свой prefix в API/БД: например `tz_approved` или `second_line_approved`.
- Добавляет фильтры расширенного поиска:
  - `status:tz-approved`;
  - `status:tz-unapproved`.
- Обновляет открытую тему через `MessageBus`, чтобы другим пользователям прилетал reload topic/stream.

## Установка

На хосте Discourse:

```bash
cd /var/discourse/shared/standalone/plugins
git clone https://github.com/ban2zai/discourse-tz-approval.git

cd /var/discourse
./launcher rebuild app
```

После изменения JS/SCSS плагина обычно нужен именно `rebuild app`, а не только `restart app`, потому что frontend assets собираются при rebuild.

## Настройки

Настройки находятся в `config/settings.yml`.

| Настройка | Тип | По умолчанию | Что делает |
| --- | --- | --- | --- |
| `tz_approval_enabled` | boolean | `true` | Полностью включает/выключает механизм. |
| `tz_approval_binding_mode` | enum | `tag` | Режим применимости: `tag` — по тегам, `category` — по категориям. |
| `tz_approval_tags` | list | `тех-задание` | Список тегов для режима `tag`. Достаточно одного совпавшего тега. В режиме `category` игнорируется. |
| `tz_approval_prefix` | string | `tz` | Префикс custom fields/API для профиля ТЗ. По умолчанию сохраняет старые поля `tz_approved`, `tz_approved_by_id`, `tz_approved_at`. |
| `tz_approval_allowed_groups` | group_list | пусто | Группы, которым разрешено одобрять и снимать одобрение ТЗ. Staff имеет доступ всегда. |
| `tz_approval_categories` | category_list | пусто | Список категорий для режима `category`. Пусто означает «не выбрано ни одной категории». Подкатегории не наследуются автоматически. |
| `tz_author_approval_delay` | integer | `600` | Задержка в секундах, после которой автор темы может сам одобрить свое ТЗ. |
| `tz_approval_icon` | icon | `file-signature` | Иконка статуса ТЗ. Нужно использовать имя зарегистрированной FontAwesome/Discourse SVG-иконки. |
| `tz_approval_light_color` | string | `#d9a441` | Цвет для светлой темы, зарезервирован под визуальную настройку. |
| `tz_approval_dark_color` | string | `#d9a441` | Цвет для темной темы, зарезервирован под визуальную настройку. |
| `second_line_approval_enabled` | boolean | `false` | Включает профиль одобрения «Вторая линия». |
| `second_line_approval_prefix` | string | `second_line` | Префикс custom fields/API для профиля «Вторая линия». |
| `second_line_approval_categories` | category_list | пусто | Категории, в которых применяется профиль «Вторая линия». |
| `second_line_approval_allowed_groups` | group_list | пусто | Группы, которым разрешено одобрять и снимать одобрение второй линии. |
| `second_line_approval_icon` | icon | `clipboard-check` | Иконка статуса второй линии. |
| `second_line_approval_label` | string | `Вторая линия` | Название профиля, которое возвращается в JSON. |

`*_approval_prefix` должен состоять из латинских букв, цифр и `_`. Некорректный prefix заменяется безопасным значением по умолчанию.

Текущий базовый цвет интерфейса задан CSS-переменной:

```scss
--tz-approval-color: light-dark(#d9a441, #d9a441);
```

Если нужно быстро поменять цвет без правки логики, переопредели `--tz-approval-color` в теме или stylesheet плагина.

## Права и тайминги

Плагин применим к теме только если:

1. `tz_approval_enabled = true`;
2. в режиме `tag` у темы есть хотя бы один тег из `tz_approval_tags`;
3. в режиме `category` категория темы выбрана в `tz_approval_categories`.

В режиме `tag` выбранные категории не влияют на применимость. В режиме `category` теги не влияют на применимость. Если `tz_approval_binding_mode = category`, а `tz_approval_categories` пустой, профиль ТЗ не работает ни в одной теме.

Профиль «Вторая линия» всегда включается по категориям из `second_line_approval_categories`. Если тема попадает и в ТЗ, и во вторую линию, применяется профиль ТЗ.

Одобрить ТЗ могут:

- админы и модераторы (`staff`) — без задержки;
- пользователи из `tz_approval_allowed_groups` — без задержки;
- автор темы — только после `tz_author_approval_delay` секунд с момента создания темы.

Снять одобрение могут:

- админы и модераторы;
- пользователи из `tz_approval_allowed_groups`;
- автор темы, но только если он сам одобрял это ТЗ.

Пример: при `tz_author_approval_delay = 600` автор темы увидит возможность одобрить свое ТЗ примерно через 10 минут после создания темы. Staff и разрешенные группы не ждут этот таймер.

## Как выглядит в интерфейсе

### Кнопка в теме

Кнопка добавляется через `registerTopicFooterButton`:

- если ТЗ не одобрено и пользователь имеет право — **«Одобрить ТЗ»**;
- если ТЗ одобрено и пользователь имеет право — **«Снять одобрение»**.

### Список тем

У одобренных тем появляется иконка ТЗ внутри `.topic-statuses`, рядом с другими статусами темы, например Solved.

Стабильные селекторы:

- `.tz-approval-topic-status`;
- `.--tz-approved`;
- `[data-tz-approval-topic-status]`;
- `.status-tz-approved` на строке темы.

### Заголовок темы

Если тема одобрена, такая же иконка добавляется в заголовок темы рядом со статусами. Иконка вставляется и в основной заголовок, и в sticky/compact заголовок.

Стабильный селектор:

- `[data-tz-approval-topic-title-status]`.

### Первый пост

Внутри первого поста после cooked-содержимого отображается плашка:

- `ТЗ одобрено — Автор темы`, если одобрил автор темы;
- `ТЗ одобрено — @username`, если одобрил другой пользователь.

Для не-автора имя кликабельное и открывает user card через стандартный `UserLink`.

Стабильные селекторы:

- `.tz-approval-post-badge`;
- `[data-tz-approval-post-badge]`;
- `.tz-approval-post-badge__icon`;
- `.tz-approval-post-badge__text`;
- `.tz-approval-post-badge__user`.

### Small action сообщение

При одобрении или снятии одобрения создается системное small action сообщение от `system`.

Примеры текста:

- `Автор темы одобрил это ТЗ`;
- `@username одобрил это ТЗ`;
- `Автор темы снял одобрение с этого ТЗ`;
- `@username снял одобрение с этого ТЗ`.

Если используется `@username`, Discourse готовит mention как кликабельный профиль/user card. Само mention-уведомление при этом не отправляется: системный пост нужен только для истории в теме. Автор темы получает отдельное Discourse-уведомление типа `tz_approval` (`notification_type = 167`), когда ТЗ одобряет или снимает одобрение другой пользователь. В `data.action` передается `approved` или `unapproved`. Время сообщения отображается штатной логикой Discourse для small action posts.

Стабильные селекторы:

- `.tz-approval-small-action-post`;
- `.tz-approval-small-action`;
- `[data-tz-approval-small-action]`;
- `.tz-approval-small-action__icon`;
- `.tz-approval-small-action__title`;
- `.tz-approval-small-action__time`;
- `.tz-approval-small-action__message`.

## Расширенный поиск

Плагин добавляет два фильтра:

```text
status:tz-approved
status:tz-unapproved
status:second-line-approved
status:second-line-unapproved
```

`status:tz-approved` возвращает применимые темы, которые:

- имеют `tz_approved = true`.

`status:tz-unapproved` возвращает применимые темы, которые:

- еще не имеют `tz_approved = true`.

`status:second-line-approved` и `status:second-line-unapproved` работают аналогично, но только для категорий профиля «Вторая линия» и поля `second_line_approved`.

Применимость в поиске определяется тем же режимом, что и кнопка одобрения:

- `tag` — по `tz_approval_tags`;
- `category` — по `tz_approval_categories`.

В режиме `category` темы без ТЗ-тега тоже попадают в результаты, если их категория выбрана.

## API endpoints

Плагин добавляет два authenticated endpoint:

```text
POST /tz-approval/approve
POST /tz-approval/unapprove
```

Оба endpoint принимают `topic_id`.

Пример:

```bash
curl -X POST "https://forum.example.com/tz-approval/approve" \
  -H "Api-Key: <key>" \
  -H "Api-Username: <username>" \
  -d "topic_id=123"
```

Права все равно проверяются через Guardian.

Ответ endpoint содержит старые поля `tz_*` и новые профильные поля:

```json
{
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

## Хранение данных

Плагин использует `TopicCustomField`. Для ТЗ по умолчанию сохраняются старые поля:

- `tz_approved` — boolean;
- `tz_approved_by_id` — integer;
- `tz_approved_at` — ISO8601 timestamp string;
- `tz_approval_post_id` — integer, legacy/служебное поле.

Для «Второй линии» при prefix `second_line` используются:

- `second_line_approved` — boolean;
- `second_line_approved_by_id` — integer;
- `second_line_approved_at` — ISO8601 timestamp string;
- `second_line_approval_post_id` — integer, служебное поле.

В topic view сериализуются:

- `tz_approved`;
- `tz_approved_by_id`;
- `tz_approved_at`;
- `tz_approved_by_username`;
- `can_approve_tz`;
- `can_unapprove_tz`.

Дополнительно сериализуются профильные поля:

- `approval_profile_key`;
- `approval_profile_prefix`;
- `approval_label`;
- `approval_icon`;
- `approved`;
- `approved_by_id`;
- `approved_by_username`;
- `approved_at`;
- `can_approve`;
- `can_unapprove`.

В topic list сериализуется:

- `tz_approved`.

## Обновление

```bash
cd /var/discourse/shared/standalone/plugins/discourse-tz-approval
git pull

cd /var/discourse
./launcher rebuild app
```

Если менялся только backend Ruby-код, иногда хватает `./launcher restart app`, но для изменений JS/SCSS надежнее делать rebuild.

## Разработка

Основные frontend-точки:

- `tz-approval-button.gjs` — кнопка в footer темы;
- `tz-approval-topic-list.gjs` — иконка в списке тем;
- `tz-approval-topic-title.gjs` — иконка в заголовке темы;
- `tz-approval-status.gjs` — плашка внутри первого поста;
- `tz-approval-small-action.gjs` — кастомный вид системных small action сообщений;
- `tz-approval-search.gjs` — элементы расширенного поиска.

Стили лежат в:

```text
assets/stylesheets/tz-approval.scss
```

Backend:

- `plugin.rb` — настройки полей, сериализация, Guardian patch, search filters, routes;
- `app/controllers/tz_approval/approvals_controller.rb` — approve/unapprove actions.

## Совместимость

Плагин рассчитан на современный Discourse 2026.x:

- используется `apiInitializer`;
- используется Glimmer topic list;
- `.raw.hbs` и старые template overrides не используются.
