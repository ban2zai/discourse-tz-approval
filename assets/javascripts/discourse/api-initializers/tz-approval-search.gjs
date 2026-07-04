import { apiInitializer } from "discourse/lib/api";
import { helperContext } from "discourse/lib/helpers";
import { i18n } from "discourse-i18n";

export default apiInitializer((api) => {
  const profiles = helperContext().site?.tz_approval_profiles || [
    {
      status_slug: "tz",
      approved_text: i18n("search.advanced.statuses.tz_approved"),
      unapproved_text: i18n("search.advanced.statuses.tz_unapproved"),
    },
  ];

  api.addAdvancedSearchOptions({
    statusOptions: profiles.flatMap((profile) => [
      {
        name: profile.approved_text,
        value: `${profile.status_slug}-approved`,
      },
      {
        name: profile.unapproved_text,
        value: `${profile.status_slug}-unapproved`,
      },
    ]),
  });

  profiles.forEach((profile) => {
    api.addSearchSuggestion(`status:${profile.status_slug}-approved`);
    api.addSearchSuggestion(`status:${profile.status_slug}-unapproved`);
  });
});
