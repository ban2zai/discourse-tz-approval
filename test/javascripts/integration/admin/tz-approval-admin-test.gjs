import { click, render, select, settled } from "@ember/test-helpers";
import { module, test } from "qunit";
import TzApprovalAdmin from "discourse/plugins/discourse-tz-approval/admin/components/tz-approval-admin";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";

const PROFILE = {
  id: 1,
  key: "second_line",
  prefix: "second_line",
  label: "Вторая линия",
  enabled: true,
  priority: 100,
  binding_mode: "category",
  require_task_guid: true,
  icon: "clipboard-check",
  category_ids: [],
  allowed_group_ids: [],
  tags: [],
  system: false,
};

module("Integration | Admin | tz-approval-admin", function (hooks) {
  setupRenderingTest(hooks);

  test("submits the GUID flag and resets it in tag mode", async function (assert) {
    let submittedProfile;

    this.server.get("/admin/plugins/tz-approval/profiles", () => ({
      profiles: [PROFILE],
      categories: [],
      groups: [],
      tags: [],
    }));

    class TestableTzApprovalAdmin extends TzApprovalAdmin {
      request(url, options) {
        if (!options) {
          return super.request(url);
        }

        submittedProfile = { ...options.data.profile };
        return Promise.resolve({ profile: submittedProfile });
      }
    }

    await render(<template><TestableTzApprovalAdmin /></template>);
    await settled();

    assert.dom("[data-require-task-guid]").isChecked();
    assert.dom("[data-require-task-guid]").isNotDisabled();

    await click("[data-require-task-guid]");
    await click("[data-require-task-guid]");
    await click(".tz-approval-admin__actions .btn-primary");

    assert.true(
      submittedProfile.require_task_guid,
      "includes the enabled flag in the profile payload"
    );

    await select("[data-binding-mode]", "tag");

    assert.dom("[data-require-task-guid]").isNotChecked();
    assert.dom("[data-require-task-guid]").isDisabled();

    await click(".tz-approval-admin__actions .btn-primary");

    assert.false(
      submittedProfile.require_task_guid,
      "submits false after switching to tag mode"
    );
  });
});
