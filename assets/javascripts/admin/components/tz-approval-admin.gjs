import Component from "@glimmer/component";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { tracked } from "@glimmer/tracking";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";
import { eq } from "truth-helpers";

const ICON_OPTIONS = [
  "file-signature",
  "clipboard-check",
  "clipboard-list",
  "circle-check",
  "square-check",
  "stamp",
  "user-plus",
];

const DEFAULT_PROFILE = {
  key: "",
  prefix: "",
  label: "",
  enabled: true,
  priority: 100,
  binding_mode: "category",
  icon: "file-signature",
  category_ids: [],
  allowed_group_ids: [],
  tags: [],
  approve_text: "",
  unapprove_text: "",
  approved_text: "",
  unapproved_text: "",
  approved_by_author_text: "",
  approved_action_text: "",
  unapproved_action_text: "",
  approved_description: "",
  unapproved_description: "",
};

function cloneProfile(profile = DEFAULT_PROFILE) {
  return {
    ...DEFAULT_PROFILE,
    ...profile,
    category_ids: [...(profile.category_ids || [])].map((id) => Number(id)),
    allowed_group_ids: [...(profile.allowed_group_ids || [])].map((id) => Number(id)),
    tags: [...(profile.tags || [])],
  };
}

export default class TzApprovalAdmin extends Component {
  @service dialog;

  @tracked categories = [];
  @tracked categorySearch = "";
  @tracked dirty = false;
  @tracked draft = cloneProfile();
  @tracked groupSearch = "";
  @tracked groups = [];
  @tracked loadError = null;
  @tracked loading = true;
  @tracked profiles = [];
  @tracked saveError = null;
  @tracked saveMessage = null;
  @tracked saving = false;
  @tracked selectedProfileId = null;
  @tracked tagSearch = "";
  @tracked tags = [];

  constructor() {
    super(...arguments);
    this.load();
  }

  get selectedProfile() {
    return this.profiles.find((profile) => profile.id === this.selectedProfileId);
  }

  get isExistingProfile() {
    return !!this.draft.id;
  }

  get canDelete() {
    return this.isExistingProfile && !this.draft.system && !this.saving;
  }

  get deleteDisabled() {
    return !this.canDelete;
  }

  get saveDisabled() {
    return this.saving || !this.dirty;
  }

  get iconOptions() {
    return ICON_OPTIONS;
  }

  get categoryOptions() {
    return this.categories.map((category) => ({
      ...category,
      selected: this.draft.category_ids.includes(category.id),
    }));
  }

  get groupOptions() {
    return this.groups.map((group) => ({
      ...group,
      selected: this.draft.allowed_group_ids.includes(group.id),
    }));
  }

  get tagOptions() {
    const names = new Set([...(this.tags || []), ...(this.draft.tags || [])]);

    return [...names].sort().map((name) => ({
      id: name,
      name,
      selected: this.draft.tags.includes(name),
    }));
  }

  get visibleCategoryOptions() {
    return this.filterOptions(this.categoryOptions, this.categorySearch);
  }

  get visibleGroupOptions() {
    return this.filterOptions(this.groupOptions, this.groupSearch);
  }

  get visibleTagOptions() {
    return this.filterOptions(this.tagOptions, this.tagSearch);
  }

  get selectedCategoryOptions() {
    return this.categoryOptions.filter((category) => category.selected);
  }

  get selectedGroupOptions() {
    return this.groupOptions.filter((group) => group.selected);
  }

  get selectedTagOptions() {
    return this.tagOptions.filter((tag) => tag.selected);
  }

  get categorySummary() {
    return this.selectionSummary(this.selectedCategoryOptions);
  }

  get groupSummary() {
    return this.selectionSummary(this.selectedGroupOptions);
  }

  get tagSummary() {
    return this.selectionSummary(this.selectedTagOptions);
  }

  get bindingModeLabel() {
    return i18n(`tz_approval.admin.binding_modes.${this.draft.binding_mode}`);
  }

  filterOptions(options, search) {
    const query = search.trim().toLowerCase();
    return query
      ? options.filter((option) => option.name.toLowerCase().includes(query))
      : options;
  }

  selectionSummary(options) {
    if (!options.length) {
      return i18n("tz_approval.admin.none_selected");
    }

    if (options.length === 1) {
      return options[0].name;
    }

    return i18n("tz_approval.admin.selected_count", { count: options.length });
  }

  applyPayload(data) {
    this.profiles = data.profiles || [];
    this.categories = data.categories || [];
    this.groups = data.groups || [];
    this.tags = data.tags || [];

    const selected =
      this.profiles.find((profile) => profile.id === this.selectedProfileId) ||
      this.profiles[0];

    if (selected) {
      this.selectProfile(selected);
    } else {
      this.newProfile();
    }
  }

  async load() {
    this.loading = true;
    this.loadError = null;

    try {
      this.applyPayload(await ajax("/admin/plugins/tz-approval/profiles"));
    } catch {
      this.loadError = i18n("tz_approval.admin.load_error");
    } finally {
      this.loading = false;
    }
  }

  markDirty() {
    this.dirty = true;
    this.saveError = null;
    this.saveMessage = null;
  }

  resetFilters() {
    this.categorySearch = "";
    this.groupSearch = "";
    this.tagSearch = "";
  }

  @action
  selectProfile(profile) {
    this.selectedProfileId = profile.id;
    this.draft = cloneProfile(profile);
    this.dirty = false;
    this.saveError = null;
    this.saveMessage = null;
    this.resetFilters();
  }

  @action
  newProfile() {
    this.selectedProfileId = null;
    this.draft = cloneProfile();
    this.dirty = true;
    this.saveError = null;
    this.saveMessage = null;
    this.resetFilters();
  }

  @action
  updateField(field, event) {
    const value =
      event.target.type === "checkbox" ? event.target.checked : event.target.value;
    this.draft = { ...this.draft, [field]: value };
    this.markDirty();
  }

  @action
  updateNumberField(field, event) {
    this.draft = { ...this.draft, [field]: Number(event.target.value || 0) };
    this.markDirty();
  }

  @action
  updateSearch(field, event) {
    this[field] = event.target.value;
  }

  @action
  toggleArrayField(field, id, event) {
    const value = Number(id);
    const current = new Set(this.draft[field] || []);

    if (event.target.checked) {
      current.add(value);
    } else {
      current.delete(value);
    }

    this.draft = { ...this.draft, [field]: [...current] };
    this.markDirty();
  }

  @action
  toggleTag(tagName, event) {
    const current = new Set(this.draft.tags || []);

    if (event.target.checked) {
      current.add(tagName);
    } else {
      current.delete(tagName);
    }

    this.draft = { ...this.draft, tags: [...current].sort() };
    this.markDirty();
  }

  @action
  async saveProfile(event) {
    event?.preventDefault();
    this.saving = true;
    this.saveError = null;
    this.saveMessage = null;

    try {
      const url = this.isExistingProfile
        ? `/admin/plugins/tz-approval/profiles/${this.draft.id}`
        : "/admin/plugins/tz-approval/profiles";
      const type = this.isExistingProfile ? "PUT" : "POST";
      const data = await ajax(url, { type, data: { profile: this.draft } });

      const saved = data.profile;
      const existingIndex = this.profiles.findIndex((profile) => profile.id === saved.id);

      if (existingIndex >= 0) {
        this.profiles = this.profiles.map((profile) =>
          profile.id === saved.id ? saved : profile
        );
      } else {
        this.profiles = [...this.profiles, saved].sort((a, b) => {
          if (a.priority === b.priority) {
            return a.id - b.id;
          }

          return a.priority - b.priority;
        });
      }

      this.selectProfile(saved);
      this.saveMessage = i18n("tz_approval.admin.save_success");
    } catch (e) {
      this.saveError =
        e?.jqXHR?.responseJSON?.errors?.join(", ") ||
        i18n("tz_approval.admin.save_error");
    } finally {
      this.saving = false;
    }
  }

  @action
  deleteProfile() {
    if (!this.canDelete) {
      return;
    }

    this.dialog.deleteConfirm({
      message: i18n("tz_approval.admin.delete_confirm"),
      didConfirm: () => this.performDeleteProfile(),
    });
  }

  async performDeleteProfile() {
    this.saving = true;
    this.saveError = null;
    this.saveMessage = null;

    try {
      await ajax(`/admin/plugins/tz-approval/profiles/${this.draft.id}`, {
        type: "DELETE",
      });

      this.profiles = this.profiles.filter((profile) => profile.id !== this.draft.id);
      this.selectProfile(this.profiles[0] || cloneProfile());
      this.saveMessage = i18n("tz_approval.admin.delete_success");
    } catch (e) {
      this.saveError =
        e?.jqXHR?.responseJSON?.errors?.join(", ") ||
        i18n("tz_approval.admin.delete_error");
    } finally {
      this.saving = false;
    }
  }

  <template>
    <section class="tz-approval-admin">
      <div class="tz-approval-admin__header">
        <div>
          <h2>{{i18n "tz_approval.admin.title"}}</h2>
          <p>{{i18n "tz_approval.admin.description"}}</p>
        </div>

        <button type="button" class="btn btn-primary" {{on "click" this.newProfile}}>
          {{i18n "tz_approval.admin.new_profile"}}
        </button>
      </div>

      {{#if this.loading}}
        <p class="tz-approval-admin__loading">{{i18n "tz_approval.admin.loading"}}</p>
      {{else if this.loadError}}
        <div class="alert alert-error">{{this.loadError}}</div>
      {{else}}
        <div class="alert alert-info">{{i18n "tz_approval.admin.restart_notice"}}</div>

        <div class="tz-approval-admin__layout">
          <aside class="tz-approval-admin__list">
            <div class="tz-approval-admin__list-title">
              {{i18n "tz_approval.admin.profile_list"}}
            </div>

            {{#each this.profiles as |profile|}}
              <button
                type="button"
                class="tz-approval-admin__profile-row"
                data-selected={{if (eq profile.id this.selectedProfileId) "true" "false"}}
                {{on "click" (fn this.selectProfile profile)}}
              >
                <span class="tz-approval-admin__profile-name">{{profile.label}}</span>
                <span class="tz-approval-admin__profile-meta">
                  {{profile.prefix}}
                  -
                  {{profile.priority}}
                </span>
              </button>
            {{/each}}
          </aside>

          <form class="tz-approval-admin__form" {{on "submit" this.saveProfile}}>
            <section class="tz-approval-admin__section">
              <div class="tz-approval-admin__section-head">
                <h3>{{i18n "tz_approval.admin.sections.main"}}</h3>
                <label class="tz-approval-admin__switch">
                  <input
                    type="checkbox"
                    checked={{this.draft.enabled}}
                    disabled={{this.draft.system}}
                    {{on "change" (fn this.updateField "enabled")}}
                  />
                  <span>{{i18n "tz_approval.admin.fields.enabled"}}</span>
                </label>
              </div>

              <div class="tz-approval-admin__grid">
                <label>
                  <span>{{i18n "tz_approval.admin.fields.label"}}</span>
                  <input
                    value={{this.draft.label}}
                    placeholder={{i18n "tz_approval.admin.placeholders.label"}}
                    {{on "input" (fn this.updateField "label")}}
                  />
                </label>

                <label>
                  <span>{{i18n "tz_approval.admin.fields.priority"}}</span>
                  <input
                    type="number"
                    value={{this.draft.priority}}
                    {{on "input" (fn this.updateNumberField "priority")}}
                  />
                </label>

                <label>
                  <span>{{i18n "tz_approval.admin.fields.key"}}</span>
                  <input
                    value={{this.draft.key}}
                    disabled={{this.isExistingProfile}}
                    placeholder={{i18n "tz_approval.admin.placeholders.key"}}
                    {{on "input" (fn this.updateField "key")}}
                  />
                </label>

                <label>
                  <span>{{i18n "tz_approval.admin.fields.prefix"}}</span>
                  <input
                    value={{this.draft.prefix}}
                    disabled={{this.isExistingProfile}}
                    placeholder={{i18n "tz_approval.admin.placeholders.prefix"}}
                    {{on "input" (fn this.updateField "prefix")}}
                  />
                </label>

                <label>
                  <span>{{i18n "tz_approval.admin.fields.binding_mode"}}</span>
                  <select
                    value={{this.draft.binding_mode}}
                    {{on "change" (fn this.updateField "binding_mode")}}
                  >
                    <option value="category" selected={{eq this.draft.binding_mode "category"}}>
                      {{i18n "tz_approval.admin.binding_modes.category"}}
                    </option>
                    <option value="tag" selected={{eq this.draft.binding_mode "tag"}}>
                      {{i18n "tz_approval.admin.binding_modes.tag"}}
                    </option>
                  </select>
                </label>

                <label>
                  <span>{{i18n "tz_approval.admin.fields.icon"}}</span>
                  <select value={{this.draft.icon}} {{on "change" (fn this.updateField "icon")}}>
                    {{#each this.iconOptions as |icon|}}
                      <option value={{icon}} selected={{eq this.draft.icon icon}}>
                        {{icon}}
                      </option>
                    {{/each}}
                  </select>
                </label>
              </div>
            </section>

            <section class="tz-approval-admin__section">
              <div class="tz-approval-admin__section-head">
                <h3>{{i18n "tz_approval.admin.sections.binding"}}</h3>
                <span class="tz-approval-admin__mode">{{this.bindingModeLabel}}</span>
              </div>

              <div class="tz-approval-admin__selectors">
                <details class="tz-approval-admin__dropdown">
                  <summary>
                    <span>{{i18n "tz_approval.admin.fields.categories"}}</span>
                    <strong>{{this.categorySummary}}</strong>
                  </summary>
                  <div class="tz-approval-admin__dropdown-panel">
                    <input
                      class="tz-approval-admin__search"
                      value={{this.categorySearch}}
                      placeholder={{i18n "tz_approval.admin.search_categories"}}
                      {{on "input" (fn this.updateSearch "categorySearch")}}
                    />

                    <div class="tz-approval-admin__option-list">
                      {{#each this.visibleCategoryOptions as |category|}}
                        <label class="tz-approval-admin__option">
                          <input
                            type="checkbox"
                            checked={{category.selected}}
                            {{on "change" (fn this.toggleArrayField "category_ids" category.id)}}
                          />
                          <span>{{category.name}}</span>
                        </label>
                      {{else}}
                        <p>{{i18n "tz_approval.admin.empty_options"}}</p>
                      {{/each}}
                    </div>
                  </div>
                </details>

                <details class="tz-approval-admin__dropdown">
                  <summary>
                    <span>{{i18n "tz_approval.admin.fields.tags"}}</span>
                    <strong>{{this.tagSummary}}</strong>
                  </summary>
                  <div class="tz-approval-admin__dropdown-panel">
                    <input
                      class="tz-approval-admin__search"
                      value={{this.tagSearch}}
                      placeholder={{i18n "tz_approval.admin.search_tags"}}
                      {{on "input" (fn this.updateSearch "tagSearch")}}
                    />

                    <div class="tz-approval-admin__option-list">
                      {{#each this.visibleTagOptions as |tag|}}
                        <label class="tz-approval-admin__option">
                          <input
                            type="checkbox"
                            checked={{tag.selected}}
                            {{on "change" (fn this.toggleTag tag.name)}}
                          />
                          <span>{{tag.name}}</span>
                        </label>
                      {{else}}
                        <p>{{i18n "tz_approval.admin.empty_options"}}</p>
                      {{/each}}
                    </div>
                  </div>
                </details>

                <details class="tz-approval-admin__dropdown">
                  <summary>
                    <span>{{i18n "tz_approval.admin.fields.groups"}}</span>
                    <strong>{{this.groupSummary}}</strong>
                  </summary>
                  <div class="tz-approval-admin__dropdown-panel">
                    <input
                      class="tz-approval-admin__search"
                      value={{this.groupSearch}}
                      placeholder={{i18n "tz_approval.admin.search_groups"}}
                      {{on "input" (fn this.updateSearch "groupSearch")}}
                    />

                    <div class="tz-approval-admin__option-list">
                      {{#each this.visibleGroupOptions as |group|}}
                        <label class="tz-approval-admin__option">
                          <input
                            type="checkbox"
                            checked={{group.selected}}
                            {{on "change" (fn this.toggleArrayField "allowed_group_ids" group.id)}}
                          />
                          <span>{{group.name}}</span>
                        </label>
                      {{else}}
                        <p>{{i18n "tz_approval.admin.empty_options"}}</p>
                      {{/each}}
                    </div>
                  </div>
                </details>
              </div>
            </section>

            <section class="tz-approval-admin__section">
              <div class="tz-approval-admin__section-head">
                <h3>{{i18n "tz_approval.admin.texts"}}</h3>
              </div>

              <div class="tz-approval-admin__texts">
                <label>
                  <span>{{i18n "tz_approval.admin.fields.approve_text"}}</span>
                  <input
                    value={{this.draft.approve_text}}
                    placeholder={{i18n "tz_approval.admin.placeholders.approve_text"}}
                    {{on "input" (fn this.updateField "approve_text")}}
                  />
                </label>

                <label>
                  <span>{{i18n "tz_approval.admin.fields.unapprove_text"}}</span>
                  <input
                    value={{this.draft.unapprove_text}}
                    placeholder={{i18n "tz_approval.admin.placeholders.unapprove_text"}}
                    {{on "input" (fn this.updateField "unapprove_text")}}
                  />
                </label>

                <label>
                  <span>{{i18n "tz_approval.admin.fields.approved_text"}}</span>
                  <input
                    value={{this.draft.approved_text}}
                    placeholder={{i18n "tz_approval.admin.placeholders.approved_text"}}
                    {{on "input" (fn this.updateField "approved_text")}}
                  />
                </label>

                <label>
                  <span>{{i18n "tz_approval.admin.fields.unapproved_text"}}</span>
                  <input
                    value={{this.draft.unapproved_text}}
                    placeholder={{i18n "tz_approval.admin.placeholders.unapproved_text"}}
                    {{on "input" (fn this.updateField "unapproved_text")}}
                  />
                </label>

                <label>
                  <span>{{i18n "tz_approval.admin.fields.approved_by_author_text"}}</span>
                  <input
                    value={{this.draft.approved_by_author_text}}
                    placeholder={{i18n "tz_approval.admin.placeholders.approved_by_author_text"}}
                    {{on "input" (fn this.updateField "approved_by_author_text")}}
                  />
                </label>

                <label>
                  <span>{{i18n "tz_approval.admin.fields.approved_action_text"}}</span>
                  <input
                    value={{this.draft.approved_action_text}}
                    placeholder={{i18n "tz_approval.admin.placeholders.approved_action_text"}}
                    {{on "input" (fn this.updateField "approved_action_text")}}
                  />
                </label>

                <label>
                  <span>{{i18n "tz_approval.admin.fields.unapproved_action_text"}}</span>
                  <input
                    value={{this.draft.unapproved_action_text}}
                    placeholder={{i18n "tz_approval.admin.placeholders.unapproved_action_text"}}
                    {{on "input" (fn this.updateField "unapproved_action_text")}}
                  />
                </label>

                <label>
                  <span>{{i18n "tz_approval.admin.fields.approved_description"}}</span>
                  <input
                    value={{this.draft.approved_description}}
                    placeholder={{i18n "tz_approval.admin.placeholders.approved_description"}}
                    {{on "input" (fn this.updateField "approved_description")}}
                  />
                </label>

                <label>
                  <span>{{i18n "tz_approval.admin.fields.unapproved_description"}}</span>
                  <input
                    value={{this.draft.unapproved_description}}
                    placeholder={{i18n "tz_approval.admin.placeholders.unapproved_description"}}
                    {{on "input" (fn this.updateField "unapproved_description")}}
                  />
                </label>
              </div>
            </section>

            <div class="tz-approval-admin__actions">
              <button type="submit" class="btn btn-primary" disabled={{this.saveDisabled}}>
                {{#if this.saving}}
                  {{i18n "tz_approval.admin.saving"}}
                {{else}}
                  {{i18n "tz_approval.admin.save"}}
                {{/if}}
              </button>

              <button
                type="button"
                class="btn btn-danger"
                disabled={{this.deleteDisabled}}
                {{on "click" this.deleteProfile}}
              >
                {{i18n "tz_approval.admin.delete"}}
              </button>

              {{#if this.saveMessage}}
                <span class="tz-approval-admin__message">{{this.saveMessage}}</span>
              {{/if}}
            </div>

            {{#if this.saveError}}
              <div class="alert alert-error">{{this.saveError}}</div>
            {{/if}}
          </form>
        </div>
      {{/if}}
    </section>
  </template>
}
