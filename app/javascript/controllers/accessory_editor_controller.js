import { Controller } from "@hotwired/stimulus"

// Places accessories on the photo of the car that's showing in the spin: drag the picture where it goes, then set
// its size and turn with the sliders. Each change is saved, so the spin shows it next time.
export default class extends Controller {
  static targets = ["row", "panel", "name", "size", "turn", "status"]

  connect() {
    this.photoId = this.element.querySelector(".spin__frame.is-on")?.dataset.photoId
    this.onDrag = this.drag.bind(this)
    this.onDrop = this.drop.bind(this)
  }

  disconnect() {
    this.drop()
  }

  // The spin turned to another photo: finish placing on the last one.
  turned(event) {
    if (this.editing) this.done()
    this.photoId = event.detail.photoId
  }

  async place(event) {
    const row = event.target.closest("[data-accessory-id]")
    if (this.editing) await this.done()

    let overlay = this.overlayFor(row.dataset.accessoryId)
    if (!overlay) {
      const placement = await this.send(row.dataset.placementsUrl, "POST", { photo_id: this.photoId })
      if (!placement) return
      overlay = this.addOverlay(row, placement)
    }
    this.edit(row, overlay)
  }

  edit(row, overlay) {
    this.editing = { row, overlay, url: `${row.dataset.placementsUrl}/${overlay.dataset.placementId}` }
    overlay.classList.add("is-editing")
    overlay.dataset.placementHandle = ""
    overlay.addEventListener("pointerdown", this.grabHandler = (event) => this.grab(event))
    this.nameTarget.textContent = row.dataset.title
    this.sizeTarget.value = parseFloat(overlay.style.width)
    this.turnTarget.value = parseFloat(overlay.style.getPropertyValue("--turn")) || 0
    this.statusTarget.textContent = ""
    this.panelTarget.hidden = false
    this.panelTarget.scrollIntoView({ block: "nearest", behavior: "smooth" })
  }

  grab(event) {
    event.preventDefault()
    event.stopPropagation()
    this.frame = this.editing.overlay.closest(".spin__frame").getBoundingClientRect()
    window.addEventListener("pointermove", this.onDrag)
    window.addEventListener("pointerup", this.onDrop)
  }

  drag(event) {
    const x = Math.min(1, Math.max(0, (event.clientX - this.frame.left) / this.frame.width))
    const y = Math.min(1, Math.max(0, (event.clientY - this.frame.top) / this.frame.height))
    Object.assign(this.editing.overlay.style, { left: `${x * 100}%`, top: `${y * 100}%` })
  }

  drop() {
    window.removeEventListener("pointermove", this.onDrag)
    window.removeEventListener("pointerup", this.onDrop)
  }

  resize() {
    this.editing.overlay.style.width = `${this.sizeTarget.value}%`
  }

  rotate() {
    this.editing.overlay.style.setProperty("--turn", `${this.turnTarget.value}deg`)
  }

  async done() {
    if (!this.editing) return
    const { overlay, url } = this.editing
    const style = overlay.style
    const saved = await this.send(url, "PATCH", { placement: {
      x: parseFloat(style.left) / 100, y: parseFloat(style.top) / 100,
      width: parseFloat(style.width) / 100, rotation: parseFloat(style.getPropertyValue("--turn")) || 0
    } })
    if (!saved) return
    this.stopEditing()
  }

  async unplace() {
    if (!this.editing) return
    const { overlay, url } = this.editing
    if ((await this.send(url, "DELETE")) === null) return
    this.stopEditing()
    overlay.remove()
  }

  stopEditing() {
    const { overlay } = this.editing
    overlay.classList.remove("is-editing")
    delete overlay.dataset.placementHandle
    overlay.removeEventListener("pointerdown", this.grabHandler)
    this.editing = null
    this.panelTarget.hidden = true
  }

  overlayFor(accessoryId) {
    return this.element.querySelector(`.spin__frame[data-photo-id="${this.photoId}"] .spin__overlay[data-accessory-id="${accessoryId}"]`)
  }

  addOverlay(row, placement) {
    const img = Object.assign(document.createElement("img"), { src: row.dataset.imageUrl, alt: row.dataset.title, draggable: false })
    img.className = row.dataset.knockedOut === "true" ? "spin__overlay is-knocked-out" : "spin__overlay"
    img.dataset.accessoryId = row.dataset.accessoryId
    img.dataset.placementId = placement.id
    Object.assign(img.style, { left: `${placement.x * 100}%`, top: `${placement.y * 100}%`, width: `${placement.width * 100}%` })
    img.style.setProperty("--turn", `${placement.rotation}deg`)
    this.element.querySelector(`.spin__frame[data-photo-id="${this.photoId}"]`).append(img)
    return img
  }

  // Sends a change; returns the answer (or {} when there's none), or null after showing what went wrong.
  async send(url, method, body) {
    const response = await fetch(url, {
      method,
      headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content },
      body: body ? JSON.stringify(body) : undefined
    }).catch(() => null)
    if (response?.ok) return response.status === 204 ? {} : response.json()

    const errors = response && (await response.json().catch(() => null))?.errors
    this.statusTarget.textContent = errors?.join(", ") || "Couldn't save that. Try again."
    this.panelTarget.hidden = false
    return null
  }
}
