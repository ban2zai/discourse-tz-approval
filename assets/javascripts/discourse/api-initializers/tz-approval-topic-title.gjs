import Component from "@glimmer/component";
import { service } from "@ember/service";
import { modifier } from "ember-modifier";
import { apiInitializer } from "discourse/lib/api";
import dIcon from "discourse-common/helpers/d-icon";
import { i18n } from "discourse-i18n";

const DEFAULT_ICON = "file-signature";
const ICON_REGEXP = /^[a-z0-9-]+$/;
const movedTitleIcons = new Map();

function safeIcon(icon) {
  return ICON_REGEXP.test(icon || "") ? icon : DEFAULT_ICON;
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

        const move = () => {
          const currentElement = movedTitleIcons.get(targetKey);

          if (currentElement && currentElement !== element && currentElement.isConnected) {
            element.remove();
            return;
          }

          movedTitleIcons.set(targetKey, element);

          const statuses = document.querySelector(targetSelector);

          if (statuses && element.parentElement !== statuses) {
            statuses.appendChild(element);
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

          if (movedTitleIcons.get(targetKey) === element) {
            movedTitleIcons.delete(targetKey);
          }

          element.remove();
        };
      });

      <template>
        <span
          class="tz-approval-topic-status tz-approval-topic-title-status --tz-approved"
          data-tz-approval-topic-title-status="main"
          title={{i18n "tz_approval.approved"}}
          aria-label={{i18n "tz_approval.approved"}}
          {{this.moveIntoTopicStatuses "#topic-title h1 .topic-statuses" "main"}}
        >
          {{dIcon this.approvalIcon}}
        </span>

        <span
          class="tz-approval-topic-status tz-approval-topic-title-status --tz-approved"
          data-tz-approval-topic-title-status="header"
          title={{i18n "tz_approval.approved"}}
          aria-label={{i18n "tz_approval.approved"}}
          {{this.moveIntoTopicStatuses "h1.header-title .topic-statuses" "header"}}
        >
          {{dIcon this.approvalIcon}}
        </span>
      </template>
    }
  );
});
