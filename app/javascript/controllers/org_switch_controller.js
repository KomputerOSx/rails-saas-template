import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select"]

  connect() {
    this.resize()
  }

  change() {
    this.resize()
    this.element.requestSubmit()
  }

  resize() {
    const label = this.selectTarget.options[this.selectTarget.selectedIndex]?.text || ""
    this.selectTarget.style.width = `${label.length + 5}ch`
  }
}
