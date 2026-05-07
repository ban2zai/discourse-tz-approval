import Component from "@glimmer/component";
import { htmlSafe, trustHTML } from "@ember/template";
import { modifier } from "ember-modifier";
import { apiInitializer } from "discourse/lib/api";
import { helperContext } from "discourse/lib/helpers";
import { autoUpdatingRelativeAge } from "discourse/lib/formatter";
import { i18n } from "discourse-i18n";

const TZ_APPROVAL_ACTION_CODES = ["tz_approved", "tz_unapproved"];
const DEFAULT_ICON = "file-signature";
const ICON_REGEXP = /^[a-z0-9-]+$/;

function isTzApprovalAction(code) {
  return TZ_APPROVAL_ACTION_CODES.includes(code);
}

function safeIcon(icon) {
  return ICON_REGEXP.test(icon || "") ? icon : DEFAULT_ICON;
}

function approvalIcon() {
  return safeIcon(helperContext().siteSettings.tz_approval_icon);
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

      installLayout = modifier((element) => {
        const article = element.closest("article.small-action");
        const desc = article?.querySelector(".small-action-desc");
        const contents = article?.querySelector(".small-action-contents");
        const buttons = article?.querySelector(".small-action-buttons");
        const avatar = Array.from(contents?.children || []).find((child) =>
          child.matches?.('a[data-user-card="system"]')
        );

        article?.classList.add("tz-approval-small-action-layout");

        if (desc) {
          desc.style.display = "grid";
          desc.style.gridTemplateColumns = "minmax(0, 1fr) auto";
          desc.style.columnGap = "12px";
          desc.style.alignItems = "start";
          desc.style.flex = "1 1 auto";
          desc.style.width = "100%";
          desc.style.minWidth = "0";
        }

        if (contents) {
          contents.style.display = "block";
          contents.style.gridColumn = "1";
          contents.style.gridRow = "1";
          contents.style.width = "100%";
          contents.style.minWidth = "0";
        }

        if (buttons) {
          buttons.style.gridColumn = "2";
          buttons.style.gridRow = "1";
          buttons.style.justifySelf = "end";
          buttons.style.alignSelf = "start";
        }

        if (avatar) {
          avatar.hidden = true;
        }

        return () => {
          article?.classList.remove("tz-approval-small-action-layout");
          [desc, contents, buttons].forEach((node) => node?.removeAttribute("style"));

          if (avatar) {
            avatar.hidden = false;
          }
        };
      });

      get wrapperStyle() {
        return htmlSafe(`
          display: grid;
          grid-template-columns: minmax(0, 1fr) auto;
          gap: 12px;
          align-items: start;
          width: 100%;
          box-sizing: border-box;
        `);
      }

      <template>
        <div
          class="tz-approval-small-action"
          data-tz-approval-small-action
          data-tz-approval-action-code={{@code}}
          style={{this.wrapperStyle}}
          {{this.installLayout}}
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

  api.registerValueTransformer("post-small-action-icon", ({ value, context }) => {
    if (!isTzApprovalAction(context.code)) {
      return value;
    }

    return approvalIcon();
  });
});
