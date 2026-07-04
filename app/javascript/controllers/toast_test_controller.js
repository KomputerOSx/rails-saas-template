import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="toast-test" — quick manual test button for the toast system.
export default class extends Controller {
  fire() {
    if (typeof window.toast === "function") {
      window.toast("This is a test toast!", { type: "success", description: "Everything's wired up.", position: "bottom-right" })
    }
  }
}
