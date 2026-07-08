import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="stripe-payment-method"
//
// Mounts a Stripe Payment Element (via a SetupIntent) so a card can be added/updated
// entirely inline, without redirecting to a Stripe-hosted page. On save, confirms the
// SetupIntent client-side, then submits the resulting setup_intent id to a normal Rails
// form (formTarget) so the server can attach it to the org's Stripe customer and mark it
// default - keeps all persistence server-side, JS only drives the Stripe.js confirmation.
//
// Shared by both the standalone "Update payment method" button and each plan card's
// Upgrade/Downgrade button (when there's no card on file yet): the latter passes
// plan/planName/planPrice params so, once the card is saved, the server subscribes to that
// plan immediately instead of stopping at "card saved," and the dialog shows what it's about
// to charge before the user commits.
export default class extends Controller {
  static targets = ["elements", "error", "submit", "form", "setupIntentField", "planField", "title", "priceNotice", "nameField"]
  static values = { publicKey: String, setupIntentUrl: String }

  connect() {
    this.started = false
    this.pendingPlan = ""
    this.resumeAfterRedirect()
  }

  // Lazily starts on first open (triggered alongside modal#open) rather than on every
  // page load, so a plain page view never creates a Stripe SetupIntent. Always re-captures
  // which plan (if any) triggered this open, even on repeat opens where the SetupIntent
  // fetch itself is skipped - a later click from a different button should still update it.
  async start(event) {
    this.pendingPlan = event?.params?.plan || ""
    this.updateHeader(event?.params?.planName, event?.params?.planPrice)

    if (this.started) return
    this.started = true

    if (typeof Stripe !== "function") {
      this.failToLoad("Payment form failed to load. Check your connection and try again.")
      return
    }

    try {
      this.stripe = Stripe(this.publicKeyValue)

      const response = await fetch(this.setupIntentUrlValue, {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
          Accept: "application/json"
        }
      })

      const contentType = response.headers.get("content-type") || ""
      if (!response.ok || !contentType.includes("application/json")) {
        const body = await response.text()
        console.error("stripe-payment-method: setup intent request failed", response.status, body)
        this.failToLoad(
          response.status === 401 || response.status === 403
            ? "You're not authorized to update billing for this organization."
            : "Could not start payment setup. Please try again."
        )
        return
      }

      const { client_secret } = await response.json()
      this.elements = this.stripe.elements({ clientSecret: client_secret })
      this.elementsTarget.innerHTML = ""
      // The Payment Element's own cardholder-name field is unreliable (Stripe's "auto" fields
      // heuristic can omit it, and there's no supported "always show" option) - collecting it
      // ourselves and passing it via confirmParams.payment_method_data below guarantees it's
      // always present, regardless of what the Payment Element decides to render.
      this.elements.create("payment", { fields: { billingDetails: { name: "never" } } }).mount(this.elementsTarget)
    } catch (error) {
      console.error("stripe-payment-method: failed to start", error)
      this.failToLoad("Something went wrong loading the payment form. Please try again.")
    }
  }

  updateHeader(planName, planPrice) {
    if (this.hasTitleTarget) {
      this.titleTarget.textContent = planName ? `Subscribe to ${planName}` : "Update payment method"
    }
    if (this.hasPriceNoticeTarget) {
      if (planPrice) {
        this.priceNoticeTarget.textContent = `You'll be charged ${planPrice}/mo, billed today and every month after.`
        this.priceNoticeTarget.classList.remove("hidden")
      } else {
        this.priceNoticeTarget.classList.add("hidden")
      }
    }
    if (this.hasSubmitTarget) this.submitTarget.textContent = this.defaultSubmitLabel()
  }

  defaultSubmitLabel() {
    return this.pendingPlan ? "Upgrade" : "Save card"
  }

  failToLoad(message) {
    this.elementsTarget.innerHTML = ""
    this.showError(message)
  }

  async save() {
    if (!this.elements) return

    const name = this.nameFieldTarget.value.trim()
    if (!name) {
      this.showError("Enter the name on the card.")
      this.nameFieldTarget.focus()
      return
    }

    this.submitTarget.disabled = true
    this.submitTarget.textContent = "Please wait..."
    this.hideError()

    try {
      const returnUrl = new URL(window.location.href)
      if (this.pendingPlan) returnUrl.searchParams.set("intended_plan", this.pendingPlan)

      const { error, setupIntent } = await this.stripe.confirmSetup({
        elements: this.elements,
        redirect: "if_required",
        confirmParams: {
          return_url: returnUrl.toString(),
          payment_method_data: { billing_details: { name } }
        }
      })

      if (error) {
        this.showError(error.message)
        return
      }

      this.setupIntentFieldTarget.value = setupIntent.id
      this.planFieldTarget.value = this.pendingPlan
      this.formTarget.requestSubmit()
    } catch (error) {
      console.error("stripe-payment-method: failed to save", error)
      this.showError("Something went wrong saving your card. Please try again.")
    } finally {
      this.submitTarget.disabled = false
      this.submitTarget.textContent = this.defaultSubmitLabel()
    }
  }

  // Handles cards that require an off-page redirect (e.g. 3D Secure) - Stripe sends the
  // browser back here with setup_intent params in the query string instead of resolving
  // save() in-page, so finalize from there instead. The intended plan (if any) rides along
  // as its own query param since in-memory state doesn't survive the redirect round-trip.
  resumeAfterRedirect() {
    const params = new URLSearchParams(window.location.search)
    const setupIntentId = params.get("setup_intent")
    if (!setupIntentId) return

    const intendedPlan = params.get("intended_plan") || ""
    window.history.replaceState({}, "", window.location.pathname)
    this.setupIntentFieldTarget.value = setupIntentId
    this.planFieldTarget.value = intendedPlan
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
