import Component from "@glimmer/component";
import { modifier } from "ember-modifier";
import { apiInitializer } from "discourse/lib/api";
import { i18n } from "discourse-i18n";

const FOOTER_SELECTOR = "#topic-footer-buttons";
const MAIN_SELECTOR = ":scope > .topic-footer-main-buttons";
const APPROVAL_BUTTON_SELECTOR = "#topic-footer-button-tz-approval";
const AUTHOR_LOCK_BUTTON_SELECTOR =
  "#topic-footer-button-tz-approval-author-lock";
const ROW_CLASS = "tz-approval-footer-actions-row";
const LAYOUT_ATTRIBUTE = "data-tz-approval-layout";

export default apiInitializer((api) => {
  api.renderInOutlet(
    "after-topic-footer-buttons",
    class TzApprovalFooterLayout extends Component {
      arrangeButtons = modifier((anchor) => {
        const footer = anchor.closest(FOOTER_SELECTOR);

        if (!footer) {
          return;
        }

        const originalPositions = new Map();
        let animationFrame = null;

        const rememberPosition = (button) => {
          if (!originalPositions.has(button)) {
            originalPositions.set(button, {
              parent: button.parentNode,
              nextSibling: button.nextSibling,
            });
          }
        };

        const arrange = () => {
          animationFrame = null;

          const main = footer.querySelector(MAIN_SELECTOR);
          const buttons = [
            footer.querySelector(APPROVAL_BUTTON_SELECTOR),
            footer.querySelector(AUTHOR_LOCK_BUTTON_SELECTOR),
          ].filter(Boolean);

          let row = footer.querySelector(`:scope > .${ROW_CLASS}`);

          if (!main || buttons.length === 0) {
            row?.remove();
            footer.removeAttribute(LAYOUT_ATTRIBUTE);
            return;
          }

          footer.setAttribute(LAYOUT_ATTRIBUTE, "");

          if (!row) {
            row = document.createElement("div");
            row.className = ROW_CLASS;
            row.setAttribute("role", "group");
            row.setAttribute("aria-label", i18n("tz_approval.footer_actions"));
            main.after(row);
          } else if (row.previousElementSibling !== main) {
            main.after(row);
          }

          buttons.forEach((button) => {
            rememberPosition(button);

            if (button.parentElement !== row) {
              row.append(button);
            }
          });

          const [approvalButton, authorLockButton] = buttons;

          if (
            approvalButton &&
            authorLockButton &&
            approvalButton.nextElementSibling !== authorLockButton
          ) {
            row.insertBefore(approvalButton, authorLockButton);
          }
        };

        const scheduleArrange = () => {
          if (animationFrame === null) {
            animationFrame = requestAnimationFrame(arrange);
          }
        };

        const observer = new MutationObserver(scheduleArrange);
        observer.observe(footer, { childList: true, subtree: true });
        arrange();

        return () => {
          observer.disconnect();

          if (animationFrame !== null) {
            cancelAnimationFrame(animationFrame);
          }

          originalPositions.forEach(({ parent, nextSibling }, button) => {
            if (!parent?.isConnected || !button.isConnected) {
              return;
            }

            if (nextSibling?.parentNode === parent) {
              parent.insertBefore(button, nextSibling);
            } else {
              parent.append(button);
            }
          });

          footer.querySelector(`:scope > .${ROW_CLASS}`)?.remove();
          footer.removeAttribute(LAYOUT_ATTRIBUTE);
        };
      });

      <template>
        <span
          class="tz-approval-footer-layout-anchor"
          aria-hidden="true"
          hidden
          {{this.arrangeButtons}}
        ></span>
      </template>
    }
  );
});
