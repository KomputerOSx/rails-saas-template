import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["emailInput", "submitButton", "sendButton", "codeSentMessage"]
  static values  = { sendUrl: String, expectedEmail: String }

  sendCode(event) {
    event.preventDefault()

    const btn = this.sendButtonTarget
    btn.disabled = true
    btn.textContent = "Sending…"

    fetch(this.sendUrlValue, {
      method: "POST",
      headers: {
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
        "Accept": "application/json"
      }
    })
      .then(r => {
        if (r.ok) {
          btn.textContent = "Resend code"
          this.codeSentMessageTarget.classList.remove("hidden")
        } else {
          btn.textContent = "Send code to my email"
        }
        btn.disabled = false
      })
      .catch(() => {
        btn.textContent = "Send code to my email"
        btn.disabled = false
      })
  }

  validate() {
    const emailOk = this.emailInputTarget.value.trim().toLowerCase() === this.expectedEmailValue.toLowerCase()
    const codeOk  = this._codeValue().length === 6
    this.submitButtonTarget.disabled = !(emailOk && codeOk)
  }

  _codeValue() {
    return Array.from(this.element.querySelectorAll('[name="code[]"]'))
      .map(i => i.value)
      .join("")
  }
}
