import { Controller } from "@hotwired/stimulus"

// Client-side filter for the organization table in the feature-access dialog - matches
// against each row's precomputed data-org-filter-search-value (name+slug+id, lowercased)
// and toggles row visibility. Hiding a row only affects CSS display, not its checkbox
// input, so filtered-out rows still submit normally if already checked.
export default class extends Controller {
  static targets = ["row"]

  filter(event) {
    const term = event.target.value.trim().toLowerCase()

    this.rowTargets.forEach((row) => {
      row.classList.toggle("hidden", !row.dataset.orgFilterSearchValue.includes(term))
    })
  }
}
