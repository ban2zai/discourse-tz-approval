import { apiInitializer } from "discourse/lib/api";
import { eq } from "truth-helpers";
import { i18n } from "discourse-i18n";

export default apiInitializer((api) => {
  api.renderInOutlet(
    "topic-above-post-stream",
    <template>
      {{#if @outletArgs.model.tz_approved}}
        <div
          style="
            display: inline-block;
            background: var(--success-low);
            color: var(--success);
            border-radius: 4px;
            padding: 4px 8px;
            margin-bottom: 12px;
            font-size: 0.9em;
          "
        >
          ✅
          {{#if (eq @outletArgs.model.tz_approved_by_id @outletArgs.model.user_id)}}
            {{i18n "tz_approval.approved_by_author"}}
          {{else if @outletArgs.model.tz_approved_by_username}}
            {{i18n "tz_approval.approved_by" username=@outletArgs.model.tz_approved_by_username}}
          {{else}}
            {{i18n "tz_approval.approved_by_author"}}
          {{/if}}
        </div>
      {{/if}}
    </template>
  );
});
