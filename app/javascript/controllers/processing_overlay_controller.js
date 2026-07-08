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
// The overlay itself is a <dialog> (not a plain positioned div) shown via showModal() - a
// regular z-indexed element can never cover the card-entry dialog, since any <dialog> shown
// with showModal() renders in the browser's "top layer," which sits above *all* normal content
// regardless of z-index. Top-layer dialogs stack in the order they're opened, so opening this
// one while the card dialog is already open correctly places it on top instead of behind.
//
// Listens on the capture phase at the controller's root so it catches every submit underneath
// it, including the hidden form the Stripe Elements dialog submits programmatically.
export default class extends Controller {
  static targets = ["overlay"]

  connect() {
    this.showBound = this.show.bind(this)
    this.hideBound = this.hide.bind(this)
    this.preventCancelBound = (event) => event.preventDefault()

    this.element.addEventListener("submit", this.showBound, true)
    document.addEventListener("turbo:load", this.hideBound)
    document.addEventListener("turbo:submit-end", this.hideBound)
    // Blocks dismissing via the Escape key - this is a blocking "please wait", not a
    // dismissable dialog.
    this.overlayTarget.addEventListener("cancel", this.preventCancelBound)
  }

  disconnect() {
    this.element.removeEventListener("submit", this.showBound, true)
    document.removeEventListener("turbo:load", this.hideBound)
    document.removeEventListener("turbo:submit-end", this.hideBound)
    this.overlayTarget.removeEventListener("cancel", this.preventCancelBound)
  }

  // A <form method="dialog"> (the card dialog's ✕ button and its backdrop-close button) fires
  // a genuine "submit" event too, even though nothing goes over the network - that's just how
  // the browser closes the nearest <dialog>. Since no turbo:submit-end/turbo:load ever follows
  // one of those, showing the overlay for it would leave "Processing..." stuck open forever.
  show(event) {
    if (event.target.matches('form[method="dialog"]')) return
    if (!this.overlayTarget.open) this.overlayTarget.showModal()
  }

  hide() {
    if (this.overlayTarget.open) this.overlayTarget.close()
  }
}
