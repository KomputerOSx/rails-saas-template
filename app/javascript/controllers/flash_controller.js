import { Controller } from "@hotwired/stimulus"

// Bridges a server-rendered flash message into a toast() call. Implemented as a Stimulus
// controller (not an inline <script>) because Turbo Drive's page morphing does not reliably
// re-execute inline scripts across visits, and may reuse this element across renders rather
// than replacing it. `xxxValueChanged` fires both on the initial connect AND whenever Turbo
// morphs the value attributes on a reused node, so it's the single source of truth here
// (avoid also firing from connect() — that would double-toast on a fresh connect).
export default class extends Controller {
  static values = {
    message: String,
    type: { type: String, default: "default" },
    description: { type: String, default: "" },
  }

  messageValueChanged(message) {
    if (typeof window.toast === "function" && message) {
      window.toast(message, {
        type: this.typeValue,
        description: this.descriptionValue,
        position: "bottom-right",
      })
    }
  }
}
