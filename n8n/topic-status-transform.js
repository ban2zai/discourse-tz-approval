const response = $input.first().json;

const asBoolean = (value) =>
  value === true ||
  value === "true" ||
  value === "t" ||
  value === "1" ||
  value === 1;

const asNumberOrNull = (value) => {
  if (value === null || value === undefined || value === "") {
    return null;
  }

  const number = Number(value);
  return Number.isFinite(number) ? number : null;
};

if (!response.success) {
  return [
    {
      json: {
        ok: false,
        found: false,
        error: "data_explorer_error",
        errors: response.errors ?? [],
      },
    },
  ];
}

const columns = response.columns ?? [];
const rows = response.rows ?? [];

if (!rows.length) {
  return [
    {
      json: {
        ok: true,
        found: false,
        topic_id: response.params?.topic_id ?? null,
        approvals: [],
      },
    },
  ];
}

const records = rows.map((row) =>
  Object.fromEntries(columns.map((column, index) => [column, row[index]]))
);

const approvals = records
  .filter((data) => data.profile_key)
  .map((data) => ({
    profile_key: data.profile_key,
    profile_prefix: data.profile_prefix,
    profile_label: data.profile_label,
    priority: asNumberOrNull(data.priority),
    binding_mode: data.binding_mode,
    is_applicable: asBoolean(data.is_applicable),
    approved: asBoolean(data.approved),
    approved_by: {
      id: asNumberOrNull(data.approved_by_id),
      username: data.approved_by ?? null,
      at: data.approved_at ?? null,
    },
  }));

const first = records[0];
const tzApproval = approvals.find((item) => item.profile_prefix === "tz");

return [
  {
    json: {
      ok: true,
      found: true,

      topic_id: asNumberOrNull(first.topic_id),

      is_tz: tzApproval?.is_applicable ?? false,
      tz_approved: tzApproval?.approved ?? false,
      tz_approved_by: {
        id: tzApproval?.approved_by.id ?? null,
        username: tzApproval?.approved_by.username ?? null,
        at: tzApproval?.approved_by.at ?? null,
      },

      approvals,

      can_set_solution: asBoolean(first.can_set_solution),
      has_solution: asBoolean(first.has_solution),
      solution: {
        post_id: asNumberOrNull(first.solution_post_id),
        marked_at: first.solution_marked_at ?? null,
        marked_by: {
          id: asNumberOrNull(first.solution_marked_by_id),
          username: first.solution_marked_by ?? null,
        },
        post_author: {
          id: asNumberOrNull(first.solution_post_author_id),
          username: first.solution_post_author ?? null,
        },
      },
    },
  },
];
