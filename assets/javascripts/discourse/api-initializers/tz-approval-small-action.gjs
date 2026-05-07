import Component from "@glimmer/component";
import { htmlSafe, trustHTML } from "@ember/template";
import { apiInitializer } from "discourse/lib/api";
import { autoUpdatingRelativeAge } from "discourse/lib/formatter";
import { i18n } from "discourse-i18n";

const TZ_APPROVAL_ACTION_CODES = ["tz_approved", "tz_unapproved"];

function isTzApprovalAction(code) {
  return TZ_APPROVAL_ACTION_CODES.includes(code);
}

export default apiInitializer((api) => {
  api.registerValueTransformer("post-small-action-custom-component", ({ value, context }) => {
    if (!isTzApprovalAction(context.code)) {
      return value;
    }

    return class TzApprovalSmallAction extends Component {
      get title() {
        return i18n(`action_codes.${this.args.code}`);
      }

      get cooked() {
        return trustHTML(this.args.post.cooked || "");
      }

      get relativeTime() {
        return htmlSafe(
          autoUpdatingRelativeAge(this.args.createdAt, {
            format: "medium",
            title: true,
          })
        );
      }

      get wrapperStyle() {
        return htmlSafe(`
          display: grid;
          grid-template-columns: minmax(0, 1fr) auto;
          gap: 12px;
          align-items: start;
          width: 100%;
          padding-right: 4.75rem;
          box-sizing: border-box;
        `);
      }

      <template>
        <div
          class="tz-approval-small-action"
          data-tz-approval-small-action
          data-tz-approval-action-code={{@code}}
          style={{this.wrapperStyle}}
        >
          <div class="tz-approval-small-action__content" style="min-width: 0;">
            <div class="tz-approval-small-action__title" style="color: var(--primary-medium);">
              {{this.title}}
            </div>

            {{#if @post.cooked}}
              <div
                class="tz-approval-small-action__message"
                style="margin-top: 10px; color: var(--primary); font-weight: 600;"
              >
                {{this.cooked}}
              </div>
            {{/if}}
          </div>

          <div
            class="tz-approval-small-action__time"
            data-tz-approval-small-action-time
            style="color: var(--primary-medium); white-space: nowrap; text-align: right;"
          >
            {{this.relativeTime}}
          </div>
        </div>
      </template>
    };
  });

  api.registerValueTransformer("post-small-action-class", ({ value, context }) => {
    if (isTzApprovalAction(context.post.action_code)) {
      value.push("tz-approval-small-action-post");
    }

    return value;
  });
});
