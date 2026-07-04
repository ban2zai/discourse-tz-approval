# n8n topic-status workflow

Этот каталог хранит актуальный контракт для workflow `topic-status/:topic_id`.

## Data Explorer Query

Содержимое `topic-status-data-explorer.sql` нужно вставить в Data Explorer query, которую вызывает HTTP Request node.

Важно:

- параметр остается `params[topic_id]`;
- финальный SQL не должен заканчиваться точкой с запятой;
- запрос возвращает одну строку на каждый enabled approval-профиль;
- отсутствие `<prefix>_approved` в `topic_custom_fields` означает `approved: false`.

## Code node

Содержимое `topic-status-transform.js` нужно вставить в n8n Code node вместо старого JS.

Code node возвращает:

- `approvals[]` со всеми enabled-профилями;
- legacy top-level поля `is_tz`, `tz_approved`, `tz_approved_by` из профиля с `profile_prefix = "tz"`;
- solved-блок из первой строки Data Explorer response.

## Source of truth

- профили: `tz_approval_profiles`;
- статусы: `topic_custom_fields`;
- имена полей статуса: `<prefix>_approved`, `<prefix>_approved_by_id`, `<prefix>_approved_at`.
