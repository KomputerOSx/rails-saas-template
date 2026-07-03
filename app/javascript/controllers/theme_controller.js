import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["icon"]

  connect() {
    this.apply(this.saved)
  }

  toggle() {
    const next = this.current === "dark" ? "light" : "dark"
    this.apply(next)
    localStorage.setItem("theme", next)
  }

  apply(theme) {
    document.documentElement.setAttribute("data-theme", theme)
    this.iconTargets.forEach(el => {
      el.textContent = theme === "dark" ? "light_mode" : "dark_mode"
    })
  }

  get current() {
    return document.documentElement.getAttribute("data-theme") || "dark"
  }

  get saved() {
    return localStorage.getItem("theme") || "dark"
  }
}
