import { Controller } from "@hotwired/stimulus"

// Suggests the make's models (for the year, when there is one) in the model field.
export default class extends Controller {
  static targets = ["make", "year", "models"]
  static values = { url: String }

  connect() {
    if (this.makeTarget.value) this.load()
  }

  async load() {
    const make = this.makeTarget.value.trim()
    if (!make) return
    const params = new URLSearchParams({ make, year: this.yearTarget.value, country: "US" })
    try {
      const response = await fetch(`${this.urlValue}?${params}`, { headers: { Accept: "application/json" } })
      if (!response.ok) return
      const models = await response.json()
      this.modelsTarget.replaceChildren(...models.map((name) => Object.assign(document.createElement("option"), { value: name })))
    } catch {
      // Suggestions are a convenience; typing still works.
    }
  }
}
