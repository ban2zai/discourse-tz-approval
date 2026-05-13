import Component from "@glimmer/component";
import { service } from "@ember/service";
import { modifier } from "ember-modifier";
import { apiInitializer } from "discourse/lib/api";
import dIcon from "discourse-common/helpers/d-icon";
import { i18n } from "discourse-i18n";

const DEFAULT_ICON = "file-signature";
const ICON_REGEXP = /^[a-z0-9-]+$/;

function safeIcon(icon) {
  return ICON_REGEXP.test(icon || "") ? icon : DEFAULT_ICON;
}

function removeClone(clone) {
  if (clone?.parentNode) {
    clone.parentNode.removeChild(clone);
  }
}

function syncClone(source, clone) {
  clone.className = source.className;
  clone.title = source.title;
  clone.removeAttribute("hidden");
  clone.removeAttribute("aria-hidden");
  clone.style.removeProperty("display");

  if (clone.innerHTML !== source.innerHTML) {
    clone.innerHTML = source.innerHTML;
  }

  const ariaLabel = source.getAttribute("aria-label");

  if (ariaLabel) {
    clone.setAttribute("aria-label", ariaLabel);
  } else {
    clone.removeAttribute("aria-label");
  }
}

export default apiInitializer((api) => {
  api.renderInOutlet(
    "topic-list-before-status",
    class TzApprovalTopicListIcon extends Component {
      @service siteSettings;

      get approvalIcon() {
        return safeIcon(this.siteSettings.tz_approval_icon);
      }

      moveIntoTopicStatuses = modifier((element) => {
        let clone = null;
        let frame = null;

        element.style.display = "none";
        element.setAttribute("aria-hidden", "true");

        const move = () => {
          const statuses = element.closest(".link-top-line")?.querySelector(".topic-statuses");

          if (!statuses) {
            return;
          }

          if (!clone) {
            clone = element.cloneNode(true);
            clone.dataset.tzApprovalTopicStatusClone = "";
          }

          syncClone(element, clone);

          if (clone.parentElement !== statuses) {
            const existingClone = statuses.querySelector(
              "[data-tz-approval-topic-status-clone]"
            );

            if (existingClone && existingClone !== clone) {
              removeClone(existingClone);
            }

            statuses.appendChild(clone);
          }
        };

        const scheduleMove = () => {
          cancelAnimationFrame(frame);
          frame = requestAnimationFrame(move);
        };

        move();
        scheduleMove();

        const observerTarget = element.closest(".link-top-line") || document.body;
        const observer = new MutationObserver(scheduleMove);
        observer.observe(observerTarget, { childList: true, subtree: true });

        return () => {
          cancelAnimationFrame(frame);
          observer.disconnect();
          removeClone(clone);
        };
      });

      <template>
        {{#if @outletArgs.topic.tz_approved}}
          <span
            class="tz-approval-topic-status --tz-approved"
            data-tz-approval-topic-status
            title={{i18n "tz_approval.approved"}}
            aria-label={{i18n "tz_approval.approved"}}
            hidden
            {{this.moveIntoTopicStatuses}}
          >
            {{dIcon this.approvalIcon}}
          </span>
        {{/if}}
      </template>
    }
  );

  api.registerValueTransformer("topic-list-item-class", ({ value, context }) => {
    if (context.topic.tz_approved) {
      value.push("status-tz-approved");
    }

    return value;
  });
});
