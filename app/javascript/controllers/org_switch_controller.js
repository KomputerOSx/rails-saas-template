import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "input"]

  select(event) {
    const { id, name } = event.params
    this.inputTarget.value = id
    this.buttonTarget.firstChild.textContent = name
    document.activeElement?.blur()
    this.element.requestSubmit()
  }
}
