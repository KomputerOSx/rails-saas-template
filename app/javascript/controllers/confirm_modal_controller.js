import { Controller } from "@hotwired/stimulus"

// Attach to a button_to <button> to intercept the click, show the shared
// confirm modal, and only submit the parent form if the user confirms.
//
// Usage:
//   data-controller="confirm-modal"
//   data-action="click->confirm-modal#confirm"
//   data-confirm-modal-message-value="Are you sure?"
export default class extends Controller {
  static values = { message: String }

  confirm(event) {
    event.preventDefault()

    const modal      = document.getElementById("confirm-modal")
    const msgEl      = document.getElementById("confirm-modal-message")
    const confirmBtn = document.getElementById("confirm-modal-confirm")
    const cancelBtn  = document.getElementById("confirm-modal-cancel")

    msgEl.textContent = this.messageValue

    const destructive = this.element.classList.contains("text-error") ||
                        this.element.classList.contains("btn-error")
    confirmBtn.className = `btn btn-sm ${destructive ? "btn-error" : "btn-primary"}`

    modal.showModal()

    const form = this.element.form

    let settled = false
    const done = (confirmed) => {
      if (settled) return
      settled = true
      modal.close()
      if (confirmed && form) form.requestSubmit()
    }

    confirmBtn.addEventListener("click", () => done(true),  { once: true })
    cancelBtn.addEventListener( "click", () => done(false), { once: true })
    modal.addEventListener(     "close", () => done(false), { once: true })
  }
}
