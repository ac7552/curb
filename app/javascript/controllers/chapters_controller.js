import { Controller } from "@hotwired/stimulus"

// The report's tabs: one section shown at a time instead of one long page. Without JavaScript every
// section shows, one after another. A "Next" button names its section with aria-controls.
export default class extends Controller {
  static targets = ["tab", "panel"]

  connect() {
    this.element.classList.add("rpt--tabs")
    const wanted = window.location.hash.slice(1)
    if (this.panelTargets.some((panel) => panel.id === wanted)) this.select(wanted, false)
  }

  show(event) {
    this.select(event.currentTarget.getAttribute("aria-controls"), true)
  }

  select(id, scroll) {
    this.tabTargets.forEach((tab) => tab.setAttribute("aria-selected", tab.getAttribute("aria-controls") === id))
    this.panelTargets.forEach((panel) => panel.classList.toggle("is-on", panel.id === id))
    history.replaceState(null, "", `#${id}`)
    // Bring the new section's start into view when the reader has scrolled past it.
    const panel = this.panelTargets.find((p) => p.id === id)
    const bar = this.element.querySelector(".rpt-tabs")
    if (scroll && panel && bar && panel.getBoundingClientRect().top < bar.getBoundingClientRect().bottom) {
      window.scrollTo({ top: window.scrollY + panel.getBoundingClientRect().top - bar.getBoundingClientRect().bottom, behavior: "smooth" })
    }
  }
}
