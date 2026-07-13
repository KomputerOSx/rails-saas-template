import { Controller } from "@hotwired/stimulus"

// Polls /org/custom_domain/status while DNS is pending; stops when ready.
export default class extends Controller {
  static values = {
    url: String,
    interval: { type: Number, default: 15000 },
  }

  static targets = ["badge", "label", "message"]

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
      this.#render(data)
      if (data.status === "ready") clearInterval(this._timer)
    } catch {
      // Keep the last UI state on transient network errors.
    }
  }

  #render({ status, message }) {
    const ready = status === "ready"

    if (this.hasBadgeTarget) {
      this.badgeTarget.className = ready
        ? "badge badge-sm border-0 bg-success/15 text-success"
        : "badge badge-sm border-0 bg-pink-500/15 text-pink-600 dark:text-pink-400"
      this.badgeTarget.textContent = ready ? "Ready" : "Pending"
    }

    if (this.hasLabelTarget) {
      this.labelTarget.textContent = ready ? "Ready" : "Pending"
    }

    if (this.hasMessageTarget && message) {
      this.messageTarget.textContent = message
    }
  }
}
