import { Controller } from "@hotwired/stimulus"

// Copies a string to the clipboard and briefly flips the button label to "Copied".
export default class extends Controller {
  static values = {
    text: String,
    successLabel: { type: String, default: "Copied" },
  }

  async copy(event) {
    event.preventDefault()

    const text = this.textValue
    if (!text) return

    try {
      await navigator.clipboard.writeText(text)
    } catch {
      this.#fallbackCopy(text)
    }

    this.#flashSuccess()
  }

  #fallbackCopy(text) {
    const input = document.createElement("textarea")
    input.value = text
    input.setAttribute("readonly", "")
    input.style.position = "absolute"
    input.style.left = "-9999px"
    document.body.appendChild(input)
    input.select()
    document.execCommand("copy")
    input.remove()
  }

  #flashSuccess() {
    const original = this.element.textContent
    this.element.textContent = this.successLabelValue
    this.element.disabled = true

    clearTimeout(this._resetTimer)
    this._resetTimer = setTimeout(() => {
      this.element.textContent = original
      this.element.disabled = false
    }, 1500)
  }

  disconnect() {
    clearTimeout(this._resetTimer)
  }
}
