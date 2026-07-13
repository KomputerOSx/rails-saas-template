import { Controller } from "@hotwired/stimulus"

// Polls /org/custom_domain/status while DNS is pending; stops when ready.
export default class extends Controller {
  static values = {
    url: String,
    interval: { type: Number, default: 15000 },
  }

  static targets = ["badge"]

  connect() {
    this.check()
    this._timer = setInterval(() => this.check(), this.intervalValue)
  }

  disconnect() {
    clearInterval(this._timer)
  }

  async check() {
    if (!this.urlValue) return

    try {
      const response = await fetch(this.urlValue, {
        headers: { Accept: "application/json" },
        credentials: "same-origin",
      })
      if (!response.ok) return

      const data = await response.json()
      this.#render(data.status)
      if (data.status === "ready") clearInterval(this._timer)
    } catch {
      // Keep the last UI state on transient network errors.
    }
  }

  #render(status) {
    if (!this.hasBadgeTarget) return

    const ready = status === "ready"
    this.badgeTarget.className = ready
      ? "badge badge-success badge-sm"
      : "badge badge-warning badge-sm"
    this.badgeTarget.textContent = ready ? "Ready" : "Pending"
  }
}
