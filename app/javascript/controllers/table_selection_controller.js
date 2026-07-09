import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "row", "checkbox", "selectAll", "searchInput" ]

  filter() {
    const query = this.searchInputTarget.value.toLowerCase()

    this.rowTargets.forEach(row => {
      const text = row.textContent.toLowerCase()
      if (text.includes(query)) {
        row.style.display = ""
      } else {
        row.style.display = "none"
        // Uncheck it if it gets hidden by the search
        const cb = row.querySelector("input[type='checkbox']")
        if (cb) cb.checked = false
      }
    })
    this.updateSelectAllState()
  }

  toggleAll(event) {
    const isChecked = event.target.checked
    this.checkboxTargets.forEach(cb => {
      const row = cb.closest("tr")
      if (row.style.display !== "none") {
        cb.checked = isChecked
      }
    })
  }

  updateSelectAllState() {
    if (!this.hasSelectAllTarget) return
    const visibleCheckboxes = this.checkboxTargets.filter(cb => cb.closest("tr").style.display !== "none")
    const allChecked = visibleCheckboxes.length > 0 && visibleCheckboxes.every(cb => cb.checked)
    this.selectAllTarget.checked = allChecked
  }
}