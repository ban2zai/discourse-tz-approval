import Component from "@glimmer/component";
import { htmlSafe, trustHTML } from "@ember/template";
import { modifier } from "ember-modifier";
import { apiInitializer } from "discourse/lib/api";
import { helperContext } from "discourse/lib/helpers";
import { autoUpdatingRelativeAge } from "discourse/lib/formatter";
import dIcon from "discourse-common/helpers/d-icon";
import { i18n } from "discourse-i18n";

const TZ_APPROVAL_ACTION_CODES = ["tz_approved", "tz_unapproved"];
const DEFAULT_ICON = "file-signature";
const ICON_REGEXP = /^[a-z0-9-]+$/;

function safeColor(color, fallback) {
  return /^#[0-9a-fA-F]{3,8}$/.test(color || "") ? color : fallback;
}

function isTzApprovalAction(code) {
  return TZ_APPROVAL_ACTION_CODES.includes(code);
}

function safeIcon(icon) {
  return ICON_REGEXP.test(icon || "") ? icon : DEFAULT_ICON;
}

function approvalIcon() {
  return safeIcon(helperContext().siteSettings.tz_approval_icon);
}

function approvalColor() {
  const siteSettings = helperContext().siteSettings;
  const lightColor = safeColor(siteSettings.tz_approval_light_color, "#d9a441");
  const darkColor = safeColor(siteSettings.tz_approval_dark_color, "#d9a441");

  return `light-dark(${lightColor}, ${darkColor})`;
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
        let frame = null;

        const applyLayout = () => {
          const topicAvatar = article?.querySelector(":scope > .topic-avatar");
          const desc = article?.querySelector(".small-action-desc");
          const contents = article?.querySelector(".small-action-contents");
          const buttons = article?.querySelector(".small-action-buttons");
          const systemAvatar = Array.from(contents?.children || []).find((child) =>
            child.matches?.('a[data-user-card="system"]')
          );

          article?.classList.add("tz-approval-small-action-layout");

          if (topicAvatar) {
            topicAvatar.hidden = true;
            topicAvatar.style.display = "none";
          }

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

          if (systemAvatar) {
            systemAvatar.hidden = true;
            systemAvatar.style.display = "none";
          }

          element
            .querySelectorAll(".tz-approval-small-action__message p")
            .forEach((paragraph) => {
              paragraph.style.margin = "0";
            });
        };

        const scheduleApplyLayout = () => {
          cancelAnimationFrame(frame);
          frame = requestAnimationFrame(applyLayout);
        };

        applyLayout();
        scheduleApplyLayout();

        const observer = new MutationObserver(scheduleApplyLayout);

        if (article) {
          observer.observe(article, { childList: true, subtree: true });
        }

        return () => {
          cancelAnimationFrame(frame);
          observer.disconnect();
          article?.classList.remove("tz-approval-small-action-layout");

          const topicAvatar = article?.querySelector(":scope > .topic-avatar");
          const desc = article?.querySelector(".small-action-desc");
          const contents = article?.querySelector(".small-action-contents");
          const buttons = article?.querySelector(".small-action-buttons");
          const systemAvatar = Array.from(contents?.children || []).find((child) =>
            child.matches?.('a[data-user-card="system"]')
          );

          [topicAvatar, desc, contents, buttons, systemAvatar].forEach((node) => {
            node?.removeAttribute("style");
          });

          if (topicAvatar) {
            topicAvatar.hidden = false;
          }

          if (systemAvatar) {
            systemAvatar.hidden = false;
          }
        };
      });

      get wrapperStyle() {
        const color = approvalColor();

        return htmlSafe(`
          display: grid;
          grid-template-columns: 28px minmax(0, 1fr) auto;
          grid-template-rows: auto auto;
          column-gap: 10px;
          row-gap: 8px;
          align-items: start;
          width: 100%;
          box-sizing: border-box;
          --tz-approval-small-action-color: ${color};
        `);
      }

      get iconStyle() {
        return htmlSafe(`
          display: inline-flex;
          align-items: center;
          justify-content: center;
          width: 24px;
          height: 24px;
          border-radius: 5px;
          background: #fff;
          color: var(--tz-approval-small-action-color);
          box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--tz-approval-small-action-color) 20%, transparent);
        `);
      }

      get approvalIcon() {
        return approvalIcon();
      }

      <template>
        <div
          class="tz-approval-small-action"
          data-tz-approval-small-action
          data-tz-approval-action-code={{@code}}
          style={{this.wrapperStyle}}
          {{this.installLayout}}
        >
          <span
            class="tz-approval-small-action__icon"
            data-tz-approval-small-action-icon
            style={{this.iconStyle}}
          >
            {{dIcon this.approvalIcon}}
          </span>

          <div
            class="tz-approval-small-action__title"
            style="min-width: 0; color: var(--primary-medium); line-height: 1.35;"
          >
            {{this.title}}
          </div>

          <div
            class="tz-approval-small-action__time"
            data-tz-approval-small-action-time
            style="color: var(--primary-medium); white-space: nowrap; text-align: right;"
          >
            {{this.relativeTime}}
          </div>

          {{#if @post.cooked}}
            <div
              class="tz-approval-small-action__message"
              style="
                grid-column: 2 / 4;
                min-width: 0;
                color: var(--primary);
                font-weight: 600;
                line-height: 1.45;
              "
            >
              {{this.cooked}}
            </div>
          {{/if}}
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
