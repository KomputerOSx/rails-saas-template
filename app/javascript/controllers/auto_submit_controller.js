import { Controller } from "@hotwired/stimulus"

// Submits the enclosing form when a radio (or other input) inside it changes,
// optionally repointing the form at a different URL first - lets one radio
// group span several distinct endpoints (e.g. promote/demote) without a
// visible submit button.
//
// Usage:
//   data-controller="auto-submit"
//   data-action="change->auto-submit#submit"
//   data-auto-submit-url-param="/path/for/this/option"   (optional)
export default class extends Controller {
  submit(event) {
    const { url } = event.params
    if (url) this.element.action = url
    this.element.requestSubmit()
  }
}
