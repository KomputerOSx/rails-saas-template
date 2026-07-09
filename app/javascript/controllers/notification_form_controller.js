import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "sendToAll", "tableContainer" ]

  connect() {
    this.toggleTable()
  }

  toggleTable() {
    if (this.sendToAllTarget.checked) {
      this.tableContainerTarget.style.display = "none"

      // Optional: uncheck all table checkboxes when hidden so they don't submit
      const checkboxes = this.tableContainerTarget.querySelectorAll("input[type='checkbox']")
      checkboxes.forEach(cb => cb.checked = false)
    } else {
      this.tableContainerTarget.style.display = ""
    }
  }
}