import { Controller } from "@hotwired/stimulus"

const LONGEST_SIDE = 1600 // big enough to fill a laptop screen, small enough to upload quickly
const QUALITY = 0.85

// Shrinks photos on the phone before they're uploaded (a phone photo is 3–5 MB; this makes it a few hundred KB),
// then sends the form. If the browser can't, the originals go up as they are.
export default class extends Controller {
  static targets = ["input", "status"]

  async prepare() {
    const files = [...this.inputTarget.files]
    if (files.length === 0) return
    this.statusTarget.textContent = `Getting ${files.length} photo${files.length === 1 ? "" : "s"} ready…`

    try {
      const shrunk = await Promise.all(files.map((file) => this.shrink(file)))
      const transfer = new DataTransfer()
      shrunk.forEach((file) => transfer.items.add(file))
      this.inputTarget.files = transfer.files
    } catch {
      // Keep the originals; the server still checks them.
    }
    this.statusTarget.textContent = "Uploading…"
    this.element.requestSubmit()
  }

  async shrink(file) {
    const bitmap = await createImageBitmap(file, { imageOrientation: "from-image" })
    const scale = Math.min(1, LONGEST_SIDE / Math.max(bitmap.width, bitmap.height))
    const canvas = document.createElement("canvas")
    canvas.width = Math.round(bitmap.width * scale)
    canvas.height = Math.round(bitmap.height * scale)
    canvas.getContext("2d").drawImage(bitmap, 0, 0, canvas.width, canvas.height)
    bitmap.close()
    const blob = await new Promise((resolve, reject) => canvas.toBlob((b) => (b ? resolve(b) : reject()), "image/jpeg", QUALITY))
    return new File([blob], file.name.replace(/\.\w+$/, "") + ".jpg", { type: "image/jpeg", lastModified: file.lastModified })
  }
}
