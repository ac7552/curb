import { Controller } from "@hotwired/stimulus"

const GAP = 36            // px between neighbouring cards on the wheel
const RADIUS_PER_CARD = 3.2  // wheel radius as a multiple of card width; bigger is flatter
const VISIBLE_STEPS = 2.4    // cards further round than this fade out
const DOTS_SHOWN = 15
const DOT = 13               // a dot plus its gap, in px
const VIEW_KEY = "curb.checks.view"
const NUDGE_KEY = "curb.checks.nudged"

// Your checks as a wheel: the cards sit on the inside of a ring and you stand in the middle. Drag,
// swipe sideways, use the arrows or the dots to turn it; tap the front card to open its report.
// The light behind the wheel takes the colour of the front card's verdict.
export default class extends Controller {
  static targets = ["stage", "ring", "card", "nav", "now", "dots", "previous", "next", "count", "nudge", "empty", "viewButton"]

  connect() {
    this.kind = "all"
    this.rotation = 0
    this.target = 0
    this.reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    this.onKey = (event) => this.key(event)
    this.onResize = () => this.layout()
    window.addEventListener("keydown", this.onKey)
    window.addEventListener("resize", this.onResize)
    let view = "wheel"
    try { view = localStorage.getItem(VIEW_KEY) || "wheel" } catch {}
    this.applyView(view)
  }

  disconnect() {
    cancelAnimationFrame(this.frame)
    window.removeEventListener("keydown", this.onKey)
    window.removeEventListener("resize", this.onResize)
  }

  get wheel() { return this.element.classList.contains("is-wheel") }
  get shown() { return this.cardTargets.filter((card) => !card.hidden) }
  get active() { return Math.round(this.target / this.step) }

  // ---- View and filter ----

  setView(event) {
    const view = event.currentTarget.dataset.view
    try { localStorage.setItem(VIEW_KEY, view) } catch {}
    this.applyView(view)
  }

  applyView(view) {
    this.element.classList.toggle("is-wheel", view === "wheel")
    this.viewButtonTargets.forEach((button) => button.setAttribute("aria-pressed", String(button.dataset.view === view)))
    this.navTarget.hidden = view !== "wheel"
    this.layout()
  }

  filter(event) {
    this.kind = event.currentTarget.dataset.kind
    this.element.querySelectorAll("[data-action='check-wheel#filter']").forEach((chip) => {
      const on = chip === event.currentTarget
      chip.classList.toggle("is-on", on)
      chip.setAttribute("aria-pressed", String(on))
    })
    this.cardTargets.forEach((card) => (card.hidden = this.kind !== "all" && card.dataset.kind !== this.kind))
    this.rotation = this.target = 0
    this.layout()
  }

  // ---- Geometry ----

  layout() {
    const cards = this.shown
    this.emptyTarget.hidden = cards.length > 0
    if (!this.wheel) {
      // Grid: stop turning, and take the wheel's turn off the ring as well as the cards.
      cancelAnimationFrame(this.frame)
      this.ringTarget.style.removeProperty("transform")
      this.cardTargets.forEach((card) => {
        ["transform", "opacity", "scale"].forEach((property) => card.style.removeProperty(property))
        card.classList.remove("is-front")
        card.removeAttribute("inert")
      })
      this.nudgeTarget.hidden = true
      return
    }
    const width = cards[0]?.offsetWidth || 320
    this.radius = width * RADIUS_PER_CARD
    this.step = ((width + GAP) / this.radius) * (180 / Math.PI)
    // Camera behind the ring's centre, so side cards stay near the front card's size.
    this.stageTarget.style.setProperty("--perspective", `${this.radius * 3}px`)
    cards.forEach((card, i) => {
      card.dataset.index = i
      card.style.transform = `rotateY(${-i * this.step}deg) translateZ(${-this.radius}px)`
    })
    this.target = Math.min(this.target, Math.max(0, cards.length - 1) * this.step)
    this.nudgeTarget.hidden = cards.length < 2 || this.seenNudge()
    this.renderDots()
    this.render(true)
    this.animate()
  }

  render(force = false) {
    if (!this.wheel) return
    const cards = this.shown
    this.ringTarget.style.transform = `translateZ(${this.radius}px) rotateY(${this.rotation}deg)`
    cards.forEach((card, i) => {
      const away = Math.abs(i * this.step - this.rotation) / this.step
      card.style.opacity = away > VISIBLE_STEPS ? "0" : String(1 - Math.min(away / VISIBLE_STEPS, 1) * 0.6)
      card.style.scale = String(1 - Math.min(away, 2.5) * 0.06)
      card.classList.toggle("is-front", away < 0.5)
      if (away > 1.5) card.setAttribute("inert", "")
      else card.removeAttribute("inert")
    })
    const index = this.active
    if (!force && index === this.shownIndex) return
    this.shownIndex = index
    const card = cards[index]
    if (!card) return
    const kind = card.dataset.kind
    this.nowTarget.style.setProperty("--c", `var(--kind-${kind})`)
    this.nowTarget.innerHTML = ""
    const dot = document.createElement("i")
    const label = document.createElement("b")
    label.textContent = card.dataset.label
    const link = card.querySelector("a").cloneNode(false)
    link.className = "wheel__open"
    link.textContent = "Open report →"
    link.removeAttribute("draggable")
    this.nowTarget.append(dot, label, ` · ${card.dataset.cost} · ${card.dataset.date} · `, link)
    this.dotsTarget.querySelectorAll(".dock__dot").forEach((el, i) => {
      el.classList.toggle("is-on", i === index)
      el.setAttribute("aria-selected", String(i === index))
    })
    this.dotsTarget.style.transform = `translateX(${this.dotsOffset(index, cards.length)}px)`
    this.countTarget.textContent = `${index + 1} of ${cards.length}`
    this.previousTarget.disabled = index === 0
    this.nextTarget.disabled = index === cards.length - 1
  }

  // Keeps the active dot near the middle once there are more dots than fit.
  dotsOffset(index, total) {
    if (total <= DOTS_SHOWN) return 0
    const first = Math.min(Math.max(0, index - Math.floor(DOTS_SHOWN / 2)), total - DOTS_SHOWN)
    return -first * DOT
  }

  renderDots() {
    const cards = this.shown
    this.dotsTarget.replaceChildren(...cards.map((card, i) => {
      const dot = document.createElement("button")
      dot.type = "button"
      dot.className = "dock__dot"
      dot.style.setProperty("--c", `var(--kind-${card.dataset.kind})`)
      dot.setAttribute("role", "tab")
      dot.setAttribute("aria-label", card.querySelector(".check-card__car").textContent.trim())
      dot.addEventListener("click", () => this.goTo(i))
      return dot
    }))
    // The dots and their gaps, minus the last gap, plus the wider active dot (+20) and the window's padding (+8):
    // exactly as wide as the dots it shows, so the next one never peeks in half cut off.
    this.dotsTarget.parentElement.style.width = `${Math.min(cards.length, DOTS_SHOWN) * DOT - 5 + 20 + 8}px`
    this.shownIndex = null
  }

  animate() {
    cancelAnimationFrame(this.frame)
    const tick = () => {
      const distance = this.target - this.rotation
      if (Math.abs(distance) < 0.01) {
        this.rotation = this.target
        this.render()
        return
      }
      this.rotation += this.reduceMotion ? distance : distance * 0.14
      this.render()
      this.frame = requestAnimationFrame(tick)
    }
    this.frame = requestAnimationFrame(tick)
  }

  // ---- Turning it ----

  // "Drag to spin" shows until the first turn, once per browser.
  seenNudge() {
    try { return localStorage.getItem(NUDGE_KEY) === "1" } catch { return false }
  }

  hideNudge() {
    if (this.nudgeTarget.hidden) return
    this.nudgeTarget.hidden = true
    try { localStorage.setItem(NUDGE_KEY, "1") } catch {}
  }

  goTo(index) {
    this.hideNudge()
    const last = Math.max(0, this.shown.length - 1)
    this.target = Math.min(last, Math.max(0, index)) * this.step
    this.animate()
  }

  previous() { this.goTo(this.active - 1) }
  next() { this.goTo(this.active + 1) }

  key(event) {
    if (!this.wheel || event.target.closest("input, textarea, select")) return
    if (event.key === "ArrowRight") { event.preventDefault(); this.next() }
    if (event.key === "ArrowLeft") { event.preventDefault(); this.previous() }
  }

  dragStart(event) {
    if (!this.wheel || event.button > 0) return
    this.drag = { x: event.clientX, from: this.target, moved: false, id: event.pointerId }
  }

  dragMove(event) {
    if (!this.drag) return
    const dx = event.clientX - this.drag.x
    if (!this.drag.moved && Math.abs(dx) < 6) return
    if (!this.drag.moved) {
      this.drag.moved = true
      this.stageTarget.setPointerCapture(this.drag.id)
      this.stageTarget.classList.add("is-dragging")
      this.hideNudge()
    }
    const perStep = this.radius * this.step * (Math.PI / 180)
    const last = (this.shown.length - 1) * this.step
    this.target = Math.min(last + this.step * 0.4, Math.max(-this.step * 0.4, this.drag.from - (dx / perStep) * this.step))
    this.animate()
  }

  dragEnd() {
    if (!this.drag) return
    this.dragged = this.drag.moved
    this.drag = null
    this.stageTarget.classList.remove("is-dragging")
    if (this.dragged) this.goTo(this.active)
  }

  // Sideways swipes on a trackpad turn the wheel; up and down still scroll the page.
  scroll(event) {
    if (!this.wheel || Math.abs(event.deltaX) <= Math.abs(event.deltaY)) return
    event.preventDefault()
    const last = (this.shown.length - 1) * this.step
    this.target = Math.min(last, Math.max(0, this.target + event.deltaX * 0.05))
    this.animate()
    clearTimeout(this.settle)
    this.settle = setTimeout(() => this.goTo(this.active), 140)
  }

  // A side card turns the wheel to itself; only the front card opens its report.
  cardClicked(event) {
    if (!this.wheel) return
    const card = event.target.closest("[data-check-wheel-target='card']")
    if (!card) return
    if (this.dragged) {
      this.dragged = false
      return event.preventDefault()
    }
    const index = Number(card.dataset.index)
    if (index !== this.active) {
      event.preventDefault()
      this.goTo(index)
    }
  }
}
