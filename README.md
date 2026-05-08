# discourse-tz-approval

Плагин Discourse для механизма «одобрения ТЗ» в темах. Работает только для тем, которые проходят условия плагина: включена настройка, есть нужный тег и, если задан фильтр категорий, тема находится в разрешенной категории.

Целевой стек: Discourse 2026.x, Glimmer topic list, без `.raw.hbs`/старых handlebars-overrides.

## Что делает плагин

- Добавляет кнопку в подвал темы: **«Одобрить ТЗ»** или **«Снять одобрение»**.
- Показывает статус одобрения:
  - иконкой в списке тем рядом со статусами темы;
  - иконкой в заголовке темы;
  - плашкой внутри первого поста;
  - системным small action сообщением в потоке ответов.
- Пишет состояние в `TopicCustomField`, без отдельной таблицы и миграций.
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
| `tz_approval_tags` | list | `тех-задание` | Список тегов, при наличии которых тема считается темой с ТЗ. Достаточно одного совпавшего тега. |
| `tz_approval_allowed_groups` | group_list | пусто | Группы, которым разрешено одобрять и снимать одобрение ТЗ. Staff имеет доступ всегда. |
| `tz_approval_categories` | category_list | пусто | Категории, в которых работает механизм. Пусто означает «все категории». Подкатегории не наследуются автоматически. |
| `tz_author_approval_delay` | integer | `600` | Задержка в секундах, после которой автор темы может сам одобрить свое ТЗ. |
| `tz_approval_icon` | icon | `file-signature` | Иконка статуса ТЗ. Нужно использовать имя зарегистрированной FontAwesome/Discourse SVG-иконки. |
| `tz_approval_light_color` | string | `#d9a441` | Цвет для светлой темы, зарезервирован под визуальную настройку. |
| `tz_approval_dark_color` | string | `#d9a441` | Цвет для темной темы, зарезервирован под визуальную настройку. |

Текущий базовый цвет интерфейса задан CSS-переменной:

```scss
--tz-approval-color: light-dark(#d9a441, #d9a441);
```

Если нужно быстро поменять цвет без правки логики, переопредели `--tz-approval-color` в теме или stylesheet плагина.

## Права и тайминги

Плагин применим к теме только если:

1. `tz_approval_enabled = true`;
2. у темы есть хотя бы один тег из `tz_approval_tags`;
3. категория темы разрешена в `tz_approval_categories` или список категорий пустой.

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

Если используется `@username`, Discourse готовит mention как кликабельный профиль/user card. Время сообщения отображается штатной логикой Discourse для small action posts.

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
```

`status:tz-approved` возвращает темы, которые:

- проходят условия тегов и категорий плагина;
- имеют `tz_approved = true`.

`status:tz-unapproved` возвращает темы, которые:

- проходят условия тегов и категорий плагина;
- еще не имеют `tz_approved = true`.

Темы без нужного ТЗ-тега в `tz-unapproved` не попадают.

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

## Хранение данных

Плагин использует `TopicCustomField`:

- `tz_approved` — boolean;
- `tz_approved_by_id` — integer;
- `tz_approved_at` — ISO8601 timestamp string;
- `tz_approval_post_id` — integer, legacy/служебное поле.

В topic view сериализуются:

- `tz_approved`;
- `tz_approved_by_id`;
- `tz_approved_at`;
- `tz_approved_by_username`;
- `can_approve_tz`;
- `can_unapprove_tz`.

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
