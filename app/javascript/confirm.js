import * as Turbo from "@hotwired/turbo-rails"

function confirmModal(message, _element, submitter) {
  return new Promise((resolve) => {
    const modal      = document.getElementById("confirm-modal")
    const msgEl      = document.getElementById("confirm-modal-message")
    const confirmBtn = document.getElementById("confirm-modal-confirm")
    const cancelBtn  = document.getElementById("confirm-modal-cancel")

    msgEl.textContent = message

    // Match confirm button style to the triggering element's intent
    const destructive = [submitter, _element].some(
      (el) => el?.classList.contains("btn-error") || el?.classList.contains("text-error")
    )
    confirmBtn.className = `btn btn-sm ${destructive ? "btn-error" : "btn-primary"}`

    modal.showModal()

    let settled = false
    const done = (result) => {
      if (settled) return
      settled = true
      modal.close()
      resolve(result)
    }

    confirmBtn.addEventListener("click", () => done(true),  { once: true })
    cancelBtn.addEventListener( "click", () => done(false), { once: true })
    modal.addEventListener(     "close", () => done(false), { once: true })
  })
}

Turbo.config.confirmMethod = confirmModal
