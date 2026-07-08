import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="loading-button"
//
// Disables its button and swaps the label to a busy state for the duration of a form
// submission - these billing actions (subscribe/upgrade/downgrade/cancel/remove card) hit
// Stripe and only fully settle once a webhook lands a moment later, so without this a second
// click before the page reloads/redirects can fire the same action twice (e.g. double-swap a
// plan, double-cancel).
//
// Attach directly to the button `button_to` renders (data: passed to button_to lands on the
// <button>, not the <form>) - listens on the *form's* native "submit" event rather than the
// button's own click, so it still activates correctly when a confirm-modal defers the actual
// submission (intercepts the click, calls form.requestSubmit() later only if confirmed).
//
// Also unlocks on turbo:submit-end - a response that only patches the flash message (e.g. an
// action rejected server-side, like removing a card while still subscribed) leaves this same
// button in the DOM rather than replacing it, so without this it would stay disabled showing
// "Please wait..." forever. Harmless for responses that DO replace the button (it's already
// gone from the DOM by the time this fires) since it's a no-op unless still disabled.
//
// Belt-and-braces timeout: if turbo:submit-end somehow never fires for this particular
// submission (e.g. a request that errors out in a way Turbo doesn't cleanly resolve), the
// button would otherwise stay stuck forever with no way to retry - self-unlock after a
// generous ceiling instead of trusting the event to always show up.
const STUCK_TIMEOUT_MS = 15000

export default class extends Controller {
  static values = { text: { type: String, default: "Please wait..." } }

  connect() {
    this.form = this.element.closest("form")
    this.unlockBound = this.unlock.bind(this)
    this.form?.addEventListener("submit", this.lock.bind(this))
    document.addEventListener("turbo:submit-end", this.unlockBound)
  }

  disconnect() {
    document.removeEventListener("turbo:submit-end", this.unlockBound)
    clearTimeout(this.stuckTimeout)
  }

  lock() {
    if (this.element.disabled) return
    this.element.disabled = true
    this.element.dataset.originalText = this.element.textContent
    this.element.textContent = this.textValue
    clearTimeout(this.stuckTimeout)
    this.stuckTimeout = setTimeout(this.unlockBound, STUCK_TIMEOUT_MS)
  }

  unlock() {
    clearTimeout(this.stuckTimeout)
    if (!this.element.disabled) return
    this.element.disabled = false
    if (this.element.dataset.originalText) this.element.textContent = this.element.dataset.originalText
  }
}
