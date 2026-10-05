import { Controller } from "@hotwired/stimulus"

// Copies the share link, or opens the native share sheet on phones.
export default class extends Controller {
  static values = { url: String, title: String }
  static targets = ["label"]

  async share() {
    if (navigator.share && matchMedia("(pointer: coarse)").matches) {
      try { await navigator.share({ title: this.titleValue, url: this.urlValue }); return } catch { /* fall back to copy */ }
    }
    await navigator.clipboard.writeText(this.urlValue)
    const original = this.labelTarget.textContent
    this.labelTarget.textContent = "Link copied"
    setTimeout(() => (this.labelTarget.textContent = original), 2000)
  }
}
