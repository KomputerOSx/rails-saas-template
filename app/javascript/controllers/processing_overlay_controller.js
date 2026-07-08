import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="processing-overlay"
//
// Shows a full-page dimmed overlay with a spinner from the moment ANY billing form starts
// submitting (subscribe/upgrade/downgrade/cancel/currency switch/remove card/save card) until
// the resulting page has fully settled - covering the whole round trip (the server makes a
// synchronous Stripe API call, then redirects, then the browser renders the fresh page), not
// just a single button's own disabled state. Works alongside loading-button, which only
// affects the one button clicked; this blocks interaction with the *entire* page so a
// different button can't be clicked mid-flight either.
//
// Listens on the capture phase at the controller's root so it catches every submit underneath
// it, including the hidden form the Stripe Elements dialog submits programmatically.
export default class extends Controller {
  static targets = ["overlay"]

  connect() {
    this.showBound = this.show.bind(this)
    this.hideBound = this.hide.bind(this)
    this.element.addEventListener("submit", this.showBound, true)
    document.addEventListener("turbo:load", this.hideBound)
    document.addEventListener("turbo:submit-end", this.hideBound)
  }

  disconnect() {
    this.element.removeEventListener("submit", this.showBound, true)
    document.removeEventListener("turbo:load", this.hideBound)
    document.removeEventListener("turbo:submit-end", this.hideBound)
  }

  show() {
    this.overlayTarget.classList.remove("hidden")
  }

  hide() {
    this.overlayTarget.classList.add("hidden")
  }
}
