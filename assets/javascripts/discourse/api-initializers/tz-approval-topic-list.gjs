import { apiInitializer } from "discourse/lib/api";
import dIcon from "discourse-common/helpers/d-icon";

export default apiInitializer((api) => {
  api.renderInOutlet(
    "topic-list-before-status",
    <template>
      {{#if @outletArgs.topic.tz_approved}}
        <span
          title="ТЗ одобрено"
          style="color: var(--success); display: inline-flex; align-items: center; margin-right: 4px;"
        >
          {{dIcon "clipboard-check"}}
        </span>
      {{/if}}
    </template>
  );
});
