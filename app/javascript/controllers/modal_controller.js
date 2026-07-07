import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="modal"
export default class extends Controller {
  static targets = ["dialog"]

  open() {
    this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
  }

  // For forms submitted from inside this modal whose Turbo Stream response updates
  // the dialog's content in place (rather than replacing the dialog element itself,
  // which would destroy anything - like a reparented toast host - living inside it).
  // Closing here, instead of via a fresh unopened dialog replacing the old one, keeps
  // the <dialog> node stable across the whole interaction.
  closeOnSuccess(event) {
    if (event.detail.success) this.close()
  }
}
