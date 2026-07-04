-- [params]
-- int :topic_id

WITH settings AS (
  SELECT
    COALESCE(
      (SELECT LOWER(value) IN ('true', 't', '1', 'yes', 'y')
       FROM site_settings
       WHERE name = 'tz_approval_enabled'),
      TRUE
    ) AS tz_enabled
),
topic_row AS (
  SELECT t.*
  FROM topics t
  WHERE t.id = :topic_id
),
profiles AS (
  SELECT
    id,
    key,
    prefix,
    label,
    priority,
    binding_mode,
    category_ids,
    tags
  FROM tz_approval_profiles
  WHERE enabled = TRUE
  ORDER BY priority, id
),
profile_status AS (
  SELECT
    t.id AS topic_id,

    p.key AS profile_key,
    p.prefix AS profile_prefix,
    p.label AS profile_label,
    p.priority,
    p.binding_mode,

    CASE
      WHEN NOT s.tz_enabled THEN FALSE
      WHEN p.binding_mode = 'category' THEN EXISTS (
        SELECT 1
        FROM jsonb_array_elements_text(p.category_ids::jsonb) AS category_id(value)
        WHERE category_id.value = t.category_id::text
      )
      WHEN p.binding_mode = 'tag' THEN EXISTS (
        SELECT 1
        FROM topic_tags tt
        JOIN tags tag ON tag.id = tt.tag_id
        WHERE tt.topic_id = t.id
          AND tag.name IN (
            SELECT tag_name.value
            FROM jsonb_array_elements_text(p.tags::jsonb) AS tag_name(value)
          )
      )
      ELSE FALSE
    END AS is_applicable,

    COALESCE(LOWER(approval_status.value) IN ('true', 't', '1', 'yes', 'y'), FALSE) AS approved,
    approved_user.id AS approved_by_id,
    approved_user.username AS approved_by,
    approval_date.value AS approved_at,

    (
      COALESCE(LOWER(ccf.value) IN ('true', 't', '1', 'yes', 'y'), FALSE)
      AND (
        sol.answer_post_id IS NOT NULL
        OR EXISTS (
          SELECT 1
          FROM posts p2
          WHERE p2.topic_id = t.id
            AND p2.post_number > 1
            AND p2.deleted_at IS NULL
          LIMIT 1
        )
      )
    ) AS can_set_solution,

    sol.answer_post_id IS NOT NULL AS has_solution,
    sol.answer_post_id AS solution_post_id,
    sol.created_at AS solution_marked_at,
    solution_marker.id AS solution_marked_by_id,
    solution_marker.username AS solution_marked_by,
    solution_author.id AS solution_post_author_id,
    solution_author.username AS solution_post_author

  FROM topic_row t
  CROSS JOIN settings s
  CROSS JOIN profiles p

  LEFT JOIN topic_custom_fields approval_status
    ON approval_status.topic_id = t.id
   AND approval_status.name = p.prefix || '_approved'

  LEFT JOIN topic_custom_fields approval_by
    ON approval_by.topic_id = t.id
   AND approval_by.name = p.prefix || '_approved_by_id'

  LEFT JOIN users approved_user
    ON approved_user.id =
      CASE
        WHEN approval_by.value ~ '^[0-9]+$' THEN approval_by.value::integer
        ELSE NULL
      END

  LEFT JOIN topic_custom_fields approval_date
    ON approval_date.topic_id = t.id
   AND approval_date.name = p.prefix || '_approved_at'

  LEFT JOIN category_custom_fields ccf
    ON ccf.category_id = t.category_id
   AND ccf.name = 'enable_accepted_answers'

  LEFT JOIN discourse_solved_solved_topics sol
    ON sol.topic_id = t.id

  LEFT JOIN users solution_marker
    ON solution_marker.id = sol.accepter_user_id

  LEFT JOIN posts solution_post
    ON solution_post.id = sol.answer_post_id

  LEFT JOIN users solution_author
    ON solution_author.id = solution_post.user_id
)
SELECT
  topic_id,
  profile_key,
  profile_prefix,
  profile_label,
  priority,
  binding_mode,
  is_applicable,
  approved,
  approved_by_id,
  approved_by,
  approved_at,
  can_set_solution,
  has_solution,
  solution_post_id,
  solution_marked_at,
  solution_marked_by_id,
  solution_marked_by,
  solution_post_author_id,
  solution_post_author
FROM profile_status
ORDER BY priority, profile_key
