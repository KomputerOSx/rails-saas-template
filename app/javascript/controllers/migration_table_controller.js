import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = [ "row", "checkbox", "selectAll", "bulkButton", "searchInput" ]

    connect() {
        this.toggleBulkButton()
    }

    filter() {
        const query = this.searchInputTarget.value.toLowerCase()

        this.rowTargets.forEach(row => {
            // Grab all text in the row (Name, Email, etc.)
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

        this.toggleBulkButton()
    }

    toggleAll(event) {
        const isChecked = event.target.checked

        this.checkboxTargets.forEach(cb => {
            const row = cb.closest("tr")
            if (row.style.display !== "none") {
                cb.checked = isChecked
            }
        })

        this.toggleBulkButton()
    }

    toggleBulkButton() {
        if (!this.hasBulkButtonTarget) return

        const count = this.checkboxTargets.filter(cb => cb.checked).length
        this.bulkButtonTarget.disabled = count === 0
        this.bulkButtonTarget.textContent = `Grandfather Selected (${count})`
    }

    async bulkGrandfather(event) {
        event.preventDefault()

        const checkedBoxes = this.checkboxTargets.filter(cb => cb.checked)
        if (checkedBoxes.length === 0) return

        this.bulkButtonTarget.disabled = true
        this.bulkButtonTarget.textContent = "Processing..."

        const csrfToken = document.querySelector('meta[name="csrf-token"]').content

        await Promise.all(checkedBoxes.map(cb => {
            return fetch(cb.value, {
                method: 'POST',
                headers: {
                    'X-CSRF-Token': csrfToken,
                    'Accept': 'text/html, application/xhtml+xml'
                }
            })
        }))

        window.location.reload()
    }
}