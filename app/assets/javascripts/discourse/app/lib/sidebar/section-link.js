import { tracked } from "@glimmer/tracking";

export default class SectionLink {
  @tracked linkDragCss;

  constructor({ external, full_reload, icon, id, name, value }, section) {
    this.external = external;
    this.fullReload = full_reload;
    this.prefixValue = icon;
    this.id = id;
    this.name = name;
    this.text = name;
    this.value = value;
    this.section = section;
    this.withAnchor = value.match(/#\w+$/gi);
  }

  get shouldDisplay() {
    return true;
  }

  get externalOrFullReload() {
    return this.external || this.fullReload || this.withAnchor;
  }
}
