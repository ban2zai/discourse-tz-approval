import { apiInitializer } from "discourse/lib/api";
import { i18n } from "discourse-i18n";

export default apiInitializer((api) => {
  api.addAdvancedSearchOptions({
    statusOptions: [
      {
        name: i18n("search.advanced.statuses.tz_approved"),
        value: "tz-approved",
      },
    ],
  });

  api.addSearchSuggestion("status:tz-approved");
});
