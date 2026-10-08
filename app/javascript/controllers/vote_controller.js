import { Controller } from "@hotwired/stimulus"

// Up- and down-votes. Clicking your current vote again takes it back. The score updates straight away and is put
// right from the server's answer.
export default class extends Controller {
  static targets = ["up", "down", "score"]
  static values = { url: String, type: String, id: Number, value: Number }

  up() { this.cast(this.valueValue === 1 ? 0 : 1) }
  down() { this.cast(this.valueValue === -1 ? 0 : -1) }

  async cast(value) {
    const before = { value: this.valueValue, score: Number(this.scoreTarget.textContent) }
    this.show(value, before.score + value - before.value)

    const response = await fetch(this.urlValue, {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content },
      body: JSON.stringify({ votable_type: this.typeValue, votable_id: this.idValue, value })
    }).catch(() => null)

    if (response?.ok) {
      const { score, value: saved } = await response.json()
      this.show(saved, score)
    } else {
      this.show(before.value, before.score)
    }
  }

  show(value, score) {
    this.valueValue = value
    this.scoreTarget.textContent = score
    this.upTarget.classList.toggle("is-on", value === 1)
    this.downTarget.classList.toggle("is-on", value === -1)
    this.upTarget.setAttribute("aria-pressed", value === 1)
    this.downTarget.setAttribute("aria-pressed", value === -1)
  }
}
