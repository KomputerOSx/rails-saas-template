import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "label"]

  select(event) {
    const { id, name } = event.params
    this.inputTarget.value = id
    this.labelTarget.textContent = name
    document.activeElement?.blur()
    this.element.requestSubmit()
  }
}
