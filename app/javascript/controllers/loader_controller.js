import { Controller } from "@hotwired/stimulus"

// Covers the form while a check is built. The steps are the real ones ReportBuilder performs, so the
// wait reads as work rather than as a stall; they advance on a timer because the server does not
// stream progress, and the last one stays up if the build runs long.
export default class extends Controller {
  static targets = ["overlay", "step"]

  static STEPS = [
    "Looking up the car…",
    "Checking for open recalls…",
    "Reading inspection records…",
    "Finding what owners report…",
    "Looking for free repairs the maker owes…",
    "Working out what it will cost…"
  ]

  show() {
    this.index = 0
    this.overlayTarget.hidden = false
    this.overlayTarget.setAttribute("aria-hidden", "false")
    this.stepTarget.textContent = this.constructor.STEPS[0]
    this.timer = setInterval(() => this.advance(), 1600)
  }

  // A validation error comes back without navigating, so the overlay has to come down again.
  hide() {
    clearInterval(this.timer)
    this.overlayTarget.hidden = true
    this.overlayTarget.setAttribute("aria-hidden", "true")
  }

  disconnect() { clearInterval(this.timer) }

  advance() {
    const steps = this.constructor.STEPS
    if (this.index >= steps.length - 1) return clearInterval(this.timer)
    this.index += 1
    this.stepTarget.textContent = steps[this.index]
  }
}
