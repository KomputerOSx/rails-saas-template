import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="stripe-payment-method"
//
// Mounts a Stripe Payment Element (via a SetupIntent) so a card can be added/updated
// entirely inline, without redirecting to a Stripe-hosted page. On save, confirms the
// SetupIntent client-side, then submits the resulting setup_intent id to a normal Rails
// form (formTarget) so the server can attach it to the org's Stripe customer and mark it
// default - keeps all persistence server-side, JS only drives the Stripe.js confirmation.
export default class extends Controller {
  static targets = ["elements", "error", "submit", "form", "setupIntentField"]
  static values = { publicKey: String, setupIntentUrl: String }

  connect() {
    this.started = false
    this.resumeAfterRedirect()
  }

  // Lazily starts on first open (triggered alongside modal#open) rather than on every
  // page load, so a plain page view never creates a Stripe SetupIntent.
  async start() {
    if (this.started) return
    this.started = true

    if (typeof Stripe !== "function") {
      this.elementsTarget.innerHTML = ""
      this.showError("Payment form failed to load. Check your connection and try again.")
      return
    }

    this.stripe = Stripe(this.publicKeyValue)

    const response = await fetch(this.setupIntentUrlValue, {
      method: "POST",
      headers: {
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
        Accept: "application/json"
      }
    })

    if (!response.ok) {
      this.showError("Could not start payment setup. Please try again.")
      return
    }

    const { client_secret } = await response.json()
    this.elements = this.stripe.elements({ clientSecret: client_secret })
    this.elementsTarget.innerHTML = ""
    this.elements.create("payment").mount(this.elementsTarget)
  }

  async save() {
    if (!this.elements) return

    this.submitTarget.disabled = true
    this.submitTarget.textContent = "Saving..."
    this.hideError()

    const { error, setupIntent } = await this.stripe.confirmSetup({
      elements: this.elements,
      redirect: "if_required",
      confirmParams: { return_url: window.location.href }
    })

    if (error) {
      this.showError(error.message)
      this.submitTarget.disabled = false
      this.submitTarget.textContent = "Save card"
      return
    }

    this.setupIntentFieldTarget.value = setupIntent.id
    this.formTarget.requestSubmit()
  }

  // Handles cards that require an off-page redirect (e.g. 3D Secure) - Stripe sends the
  // browser back here with setup_intent params in the query string instead of resolving
  // save() in-page, so finalize from there instead.
  resumeAfterRedirect() {
    const params = new URLSearchParams(window.location.search)
    const setupIntentId = params.get("setup_intent")
    if (!setupIntentId) return

    window.history.replaceState({}, "", window.location.pathname)
    this.setupIntentFieldTarget.value = setupIntentId
    this.formTarget.requestSubmit()
  }

  showError(message) {
    this.errorTarget.textContent = message
    this.errorTarget.classList.remove("hidden")
  }

  hideError() {
    this.errorTarget.classList.add("hidden")
  }
}
