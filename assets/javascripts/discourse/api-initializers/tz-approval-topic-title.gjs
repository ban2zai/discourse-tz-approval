import Component from "@glimmer/component";
import { service } from "@ember/service";
import { modifier } from "ember-modifier";
import { apiInitializer } from "discourse/lib/api";
import dIcon from "discourse-common/helpers/d-icon";
import { i18n } from "discourse-i18n";

const DEFAULT_ICON = "file-signature";
const ICON_REGEXP = /^[a-z0-9-]+$/;
const insertedTitleIconClones = new Map();

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
    "topic-title",
    class TzApprovalTopicTitleIcon extends Component {
      @service siteSettings;

      static shouldRender(args) {
        return args.model?.tz_approved;
      }

      get approvalIcon() {
        return safeIcon(this.siteSettings.tz_approval_icon);
      }

      moveIntoTopicStatuses = modifier((element, [targetSelector, targetKey]) => {
        let frame = null;
        let clone = null;

        element.style.display = "none";
        element.setAttribute("aria-hidden", "true");

        const move = () => {
          const statuses = document.querySelector(targetSelector);

          if (!statuses) {
            return;
          }

          const currentClone = insertedTitleIconClones.get(targetKey);

          if (currentClone && currentClone !== clone) {
            removeClone(currentClone);
          }

          if (!clone) {
            clone = element.cloneNode(true);
          }

          syncClone(element, clone);
          insertedTitleIconClones.set(targetKey, clone);

          if (clone.parentElement !== statuses) {
            statuses.appendChild(clone);
          }
        };

        const scheduleMove = () => {
          cancelAnimationFrame(frame);
          frame = requestAnimationFrame(move);
        };

        move();
        scheduleMove();

        const observer = new MutationObserver(scheduleMove);
        observer.observe(document.body, { childList: true, subtree: true });

        return () => {
          cancelAnimationFrame(frame);
          observer.disconnect();

          if (insertedTitleIconClones.get(targetKey) === clone) {
            insertedTitleIconClones.delete(targetKey);
          }

          removeClone(clone);
        };
      });

      <template>
        <span
          class="tz-approval-topic-status tz-approval-topic-title-status --tz-approved"
          data-tz-approval-topic-title-status="main"
          title={{i18n "tz_approval.approved"}}
          aria-label={{i18n "tz_approval.approved"}}
          hidden
          {{this.moveIntoTopicStatuses "#topic-title h1 .topic-statuses" "main"}}
        >
          {{dIcon this.approvalIcon}}
        </span>

        <span
          class="tz-approval-topic-status tz-approval-topic-title-status --tz-approved"
          data-tz-approval-topic-title-status="header"
          title={{i18n "tz_approval.approved"}}
          aria-label={{i18n "tz_approval.approved"}}
          hidden
          {{this.moveIntoTopicStatuses "h1.header-title .topic-statuses" "header"}}
        >
          {{dIcon this.approvalIcon}}
        </span>
      </template>
    }
  );
});
