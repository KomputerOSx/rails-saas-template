import { Controller } from "@hotwired/stimulus"

// Copies a string to the clipboard and briefly swaps the icon to a checkmark.
export default class extends Controller {
  static values = {
    text: String,
  }

  static targets = ["icon"]

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
    if (!this.hasIconTarget) return

    const icon = this.iconTarget
    const original = icon.textContent
    icon.textContent = "check"
    this.element.disabled = true

    clearTimeout(this._resetTimer)
    this._resetTimer = setTimeout(() => {
      icon.textContent = original
      this.element.disabled = false
    }, 1500)
  }

  disconnect() {
    clearTimeout(this._resetTimer)
  }
}
