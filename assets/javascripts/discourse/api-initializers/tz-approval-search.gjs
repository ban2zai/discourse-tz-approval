import { apiInitializer } from "discourse/lib/api";
import { i18n } from "discourse-i18n";

export default apiInitializer((api) => {
  api.addAdvancedSearchOptions({
    statusOptions: [
      {
        name: i18n("search.advanced.statuses.tz_approved"),
        value: "tz-approved",
      },
      {
        name: i18n("search.advanced.statuses.tz_unapproved"),
        value: "tz-unapproved",
      },
      {
        name: i18n("search.advanced.statuses.second_line_approved"),
        value: "second-line-approved",
      },
      {
        name: i18n("search.advanced.statuses.second_line_unapproved"),
        value: "second-line-unapproved",
      },
    ],
  });

  api.addSearchSuggestion("status:tz-approved");
  api.addSearchSuggestion("status:tz-unapproved");
  api.addSearchSuggestion("status:second-line-approved");
  api.addSearchSuggestion("status:second-line-unapproved");
});
