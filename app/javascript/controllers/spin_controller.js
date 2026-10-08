import { Controller } from "@hotwired/stimulus"

const PIXELS_PER_FRAME = 14 // how far a drag moves before the car turns to the next photo

// Turns a car by showing one photo of a walk-around at a time: drag sideways, or use the arrow keys.
export default class extends Controller {
  static targets = ["frame", "count", "hint"]
  static values = { frames: Number }

  connect() {
    this.index = 0
    this.onMove = this.move.bind(this)
    this.onRelease = this.release.bind(this)
  }

  disconnect() {
    this.release()
  }

  grab(event) {
    if (this.frameTargets.length < 2 || event.target.closest("[data-placement-handle]")) return
    this.startX = event.clientX
    this.startIndex = this.index
    this.element.setPointerCapture?.(event.pointerId)
    this.element.classList.add("is-dragging")
    window.addEventListener("pointermove", this.onMove)
    window.addEventListener("pointerup", this.onRelease)
  }

  move(event) {
    const steps = Math.round((this.startX - event.clientX) / PIXELS_PER_FRAME)
    this.show(this.startIndex + steps)
    if (this.hasHintTarget) this.hintTarget.hidden = true
  }

  release() {
    this.element.classList.remove("is-dragging")
    window.removeEventListener("pointermove", this.onMove)
    window.removeEventListener("pointerup", this.onRelease)
  }

  key(event) {
    if (event.key === "ArrowLeft") this.show(this.index - 1)
    else if (event.key === "ArrowRight") this.show(this.index + 1)
    else return
    event.preventDefault()
  }

  // The photo on screen, for the accessory editor.
  get currentFrame() {
    return this.frameTargets[this.index]
  }

  show(index) {
    const count = this.frameTargets.length
    this.index = ((index % count) + count) % count
    this.frameTargets.forEach((frame, i) => frame.classList.toggle("is-on", i === this.index))
    if (this.hasCountTarget) this.countTarget.textContent = this.index + 1
    this.dispatch("turned", { detail: { photoId: this.currentFrame.dataset.photoId } })
  }
}
