import { Controller } from "@hotwired/stimulus"

const STEPS = ["Make", "Year", "Model", "Price and miles"]
const SHOWN_MAKES = 15
const SHOWN_MODELS = 18
const NEWEST_FIRST_FROM = 2010
const OLDEST_YEAR = 1980
const ADVANCE_MS = 200

// The new-check form, one question per screen: tap a make, a year and a model, then type the price
// and the miles. Each tap fills a real form field and moves on; the step trail at the top shows the
// answers so far and takes you back to change one. A VIN or plate fills the car in and skips ahead.
export default class extends Controller {
  static targets = [
    "trail", "step", "country", "lookupMode", "make", "modelYear", "model", "firstUsed", "engine", "fuel",
    "price", "odometer", "priceDisplay", "odometerDisplay", "priceBox", "odometerBox", "typicalMiles", "go", "goLabel",
    "makeSearch", "makeGrid", "moreMakes", "yearGrid", "olderYears",
    "modelHeading", "modelStatus", "modelSearchBox", "modelSearch", "modelGrid", "moreModels", "modelOther",
    "cardLogo", "cardTitle", "cardOdo", "cardAsking",
    "lookupCard", "lookupPrompt", "vinPanel", "platePanel", "vin", "plate", "lookupMessage",
    "symbol", "unit", "distanceWord", "yearlyDistance", "region", "years", "yearsOutput", "addonPanel"
  ]
  static values = { markets: Object, makes: Object, start: Number, lookupUrl: String, modelsUrl: String }

  connect() {
    this.allMakes = false
    this.olderYears = Number(this.modelYearTarget.value) > 0 && Number(this.modelYearTarget.value) < NEWEST_FIRST_FROM
    this.models = []
    this.allModels = false
    this.modelCache = new Map()
    this.countryChanged({ keepRegion: true })
    this.addonChanged()
    this.go(this.startValue, { focus: false })
  }

  get country() { return this.countryTarget.value || "US" }
  get market() { return this.marketsValue[this.country] }
  get answers() {
    return { make: this.makeTarget.value, year: this.modelYearTarget.value, model: this.modelTarget.value,
             price: this.priceTarget.value, odometer: this.odometerTarget.value }
  }

  // ---- Moving between steps ----

  go(step, { focus = true } = {}) {
    this.current = step
    this.element.dataset.step = step
    this.stepTargets.forEach((el) => (el.hidden = Number(el.dataset.step) !== step))
    if (step === 0) this.renderMakes()
    if (step === 1) this.renderYears()
    if (step === 2) this.loadModels()
    if (step === 3) this.renderPriceStep()
    this.renderTrail()
    this.renderCard()
    if (!focus) return
    window.scrollTo({ top: 0, behavior: "smooth" })
    const field = { 0: this.makeSearchTarget, 3: this.priceTarget.value ? this.odometerDisplayTarget : this.priceDisplayTarget }[step]
    if (field && window.matchMedia("(pointer: fine)").matches) requestAnimationFrame(() => field.focus())
  }

  advance(step) { setTimeout(() => this.go(step), ADVANCE_MS) }

  back(event) { this.go(Number(event.currentTarget.dataset.step)) }

  renderTrail() {
    const { make, year, model, price, odometer } = this.answers
    const values = [make, year, model, price && odometer ? `${this.money(price)} · ${this.number(odometer)} ${this.market.unit}` : ""]
    this.trailTarget.replaceChildren(...STEPS.map((label, i) => {
      const done = values[i] && i !== this.current
      const crumb = document.createElement("button")
      crumb.type = "button"
      crumb.className = `crumb${i === this.current ? " is-current" : ""}${done ? " is-done" : ""}`
      crumb.dataset.step = i
      crumb.innerHTML = `<span class="crumb__n" aria-hidden="true">${done ? "✓" : i + 1}</span>`
      crumb.append(done ? values[i] : label)
      if (done) {
        crumb.setAttribute("aria-label", `Change ${label.toLowerCase()}: ${values[i]}`)
        crumb.dataset.action = "report-form#back"
      } else {
        crumb.tabIndex = -1
        if (i === this.current) crumb.setAttribute("aria-current", "step")
      }
      return crumb
    }))
  }

  // ---- Make ----

  makeList() {
    const query = this.makeSearchTarget.value.trim().toLowerCase()
    const makes = this.makesValue[this.country] || []
    return query ? makes.filter((make) => make.name.toLowerCase().includes(query)) : makes
  }

  renderMakes() {
    const query = this.makeSearchTarget.value.trim()
    const makes = this.makeList()
    const shown = query || this.allMakes ? makes : makes.slice(0, SHOWN_MAKES)
    const tiles = shown.map((make, i) => {
      const tile = this.button("make-tile", `${this.logoHTML(make)}<span>${this.escape(make.name)}</span>`)
      tile.dataset.make = make.name
      tile.dataset.action = "report-form#pickMake"
      if (make.name === this.makeTarget.value) tile.classList.add("is-on")
      if (query && i === 0) tile.classList.add("is-first")
      if (!query) tile.style.animationDelay = `${Math.min(i, 20) * 18}ms`
      else tile.style.animation = "none"
      return tile
    })
    if (query && makes.length === 0) {
      const typed = this.button("make-tile make-tile--typed", `<span class="make-logo make-logo--mono" aria-hidden="true">+</span><span>Use “${this.escape(query)}”</span>`)
      typed.dataset.make = query
      typed.dataset.action = "report-form#pickMake"
      tiles.push(typed)
    }
    this.makeGridTarget.replaceChildren(...tiles)
    const hidden = makes.length - shown.length
    this.moreMakesTarget.hidden = hidden <= 0
    this.moreMakesTarget.textContent = `Show all ${makes.length} makes`
  }

  filterMakes() { this.renderMakes() }
  showAllMakes() { this.allMakes = true; this.renderMakes() }

  pickFirstMake(event) {
    event.preventDefault()
    const first = this.makeGridTarget.querySelector("[data-make]")
    if (first) this.setMake(first.dataset.make)
  }

  pickMake(event) { this.setMake(event.currentTarget.dataset.make) }

  setMake(name) {
    if (name !== this.makeTarget.value) {
      this.modelTarget.value = ""
      this.clearDecoded()
    }
    this.makeTarget.value = name
    this.renderMakes()
    this.renderCard()
    this.advance(this.modelYearTarget.value ? 2 : 1)
  }

  // ---- Year ----

  renderYears() {
    const newest = new Date().getFullYear() + 1
    const oldest = this.olderYears ? OLDEST_YEAR : NEWEST_FIRST_FROM
    const chips = []
    for (let year = newest; year >= oldest; year--) {
      const chip = this.button("pick-chip pick-chip--year", String(year))
      chip.dataset.year = year
      chip.dataset.action = "report-form#pickYear"
      if (String(year) === this.modelYearTarget.value) chip.classList.add("is-on")
      chip.style.animationDelay = `${Math.min(newest - year, 18) * 14}ms`
      chips.push(chip)
    }
    this.yearGridTarget.replaceChildren(...chips)
    this.olderYearsTarget.hidden = this.olderYears
  }

  showOlderYears() { this.olderYears = true; this.renderYears() }

  pickYear(event) {
    const year = event.currentTarget.dataset.year
    if (year !== this.modelYearTarget.value) this.firstUsedTarget.value = ""
    this.modelYearTarget.value = year
    this.renderYears()
    this.renderCard()
    this.advance(this.modelTarget.value ? 3 : 2)
  }

  // ---- Model ----

  // The make's models, most common first. US lists come from NHTSA for the chosen year, the same
  // list the server checks against, so every model offered goes through.
  async loadModels() {
    const { make, year } = this.answers
    this.modelHeadingTarget.textContent = make || "model"
    this.modelSearchTarget.value = ""
    this.allModels = false
    const key = [this.country, make, year].join("|")
    if (!this.modelCache.has(key)) {
      this.modelStatusTarget.textContent = `Finding ${year} ${make} models…`
      this.modelGridTarget.replaceChildren(...Array.from({ length: 8 }, () => this.skeleton()))
      try {
        const params = new URLSearchParams({ make, year, country: this.country })
        const response = await fetch(`${this.modelsUrlValue}?${params}`, { headers: { Accept: "application/json" } })
        this.modelCache.set(key, response.ok ? await response.json() : [])
      } catch {
        this.modelCache.set(key, [])
      }
      if (this.current !== 2 || key !== [this.country, this.makeTarget.value, this.modelYearTarget.value].join("|")) return
    }
    this.models = this.modelCache.get(key)
    this.modelStatusTarget.textContent = this.models.length ? "Tap the model." : `We don't have a list for ${make}. Type the model below.`
    this.modelSearchBoxTarget.hidden = this.models.length <= SHOWN_MODELS
    this.renderModels()
  }

  renderModels() {
    const query = this.modelSearchTarget.value.trim().toLowerCase()
    const matches = query ? this.models.filter((name) => name.toLowerCase().includes(query)) : this.models
    const shown = query || this.allModels ? matches : matches.slice(0, SHOWN_MODELS)
    this.modelGridTarget.replaceChildren(...shown.map((name, i) => {
      const chip = this.button("pick-chip", this.escape(name))
      chip.dataset.model = name
      chip.dataset.action = "report-form#pickModel"
      if (name === this.modelTarget.value) chip.classList.add("is-on")
      if (query && i === 0) chip.classList.add("is-first")
      chip.style.animationDelay = query ? "0ms" : `${Math.min(i, 18) * 22}ms`
      return chip
    }))
    this.moreModelsTarget.hidden = shown.length >= matches.length
    this.moreModelsTarget.textContent = `Show all ${matches.length} models`
  }

  filterModels() { this.renderModels() }
  showAllModels() { this.allModels = true; this.renderModels() }

  pickFirstModel(event) {
    event.preventDefault()
    const first = this.modelGridTarget.querySelector("[data-model]")
    if (first) this.setModel(first.dataset.model)
  }

  pickModel(event) { this.setModel(event.currentTarget.dataset.model) }

  useTypedModel(event) {
    event.preventDefault()
    const name = this.modelOtherTarget.value.trim()
    if (name) this.setModel(name)
    else this.modelOtherTarget.focus()
  }

  setModel(name) {
    if (name !== this.modelTarget.value) this.clearDecoded()
    this.modelTarget.value = name
    this.renderModels()
    this.renderCard()
    this.advance(3)
  }

  // A hand-picked car drops whatever an earlier VIN or plate lookup filled in.
  clearDecoded() {
    if (this.lookupModeTarget.value === "model") return
    this.lookupModeTarget.value = "model"
    this.engineTarget.value = ""
    this.fuelTarget.value = ""
    this.firstUsedTarget.value = ""
  }

  // ---- Price and miles ----

  renderPriceStep() {
    const year = Number(this.modelYearTarget.value)
    if (year) {
      const age = Math.max(1, new Date().getFullYear() - year)
      const typical = Math.round((age * this.market.yearly) / 1000) * 1000
      this.typicalMilesTarget.dataset.value = typical
      this.typicalMilesTarget.textContent = `Not sure? Use a typical ${year}: ${this.number(typical)} ${this.market.unit}`
    }
    this.typicalMilesTarget.hidden = !year || Boolean(this.odometerTarget.value)
    this.renderGo()
  }

  renderGo() {
    const { price, odometer } = this.answers
    const ready = Boolean(price && odometer)
    this.goTarget.classList.toggle("is-ready", ready)
    this.goLabelTarget.textContent = ready ? "See the real cost" : !price ? "Enter the asking price" : `Enter the ${this.distanceWord()}`
  }

  // Typed numbers show with commas; the real field gets the plain digits.
  numberTyped(event) {
    const display = event.target
    const digits = display.value.replace(/\D/g, "").slice(0, 7)
    display.value = digits ? this.number(digits) : ""
    const field = display === this.priceDisplayTarget ? this.priceTarget : this.odometerTarget
    field.value = digits
    ;(display === this.priceDisplayTarget ? this.priceBoxTarget : this.odometerBoxTarget).classList.remove("is-missing")
    if (field === this.odometerTarget) this.typicalMilesTarget.hidden = Boolean(digits)
    this.renderGo()
    this.renderCard()
  }

  priceEntered(event) {
    event.preventDefault()
    this.odometerDisplayTarget.focus()
  }

  milesEntered(event) {
    event.preventDefault()
    this.element.requestSubmit(this.goTarget)
  }

  useTypicalMiles() {
    const value = this.typicalMilesTarget.dataset.value
    this.odometerTarget.value = value
    this.odometerDisplayTarget.value = this.number(value)
    this.odometerBoxTarget.classList.remove("is-missing")
    this.typicalMilesTarget.hidden = true
    this.renderGo()
    this.renderCard()
    if (!this.priceTarget.value) this.priceDisplayTarget.focus()
  }

  // Sends the buyer back to whatever is still missing instead of submitting a half-filled form.
  async submit(event) {
    const missingStep = ["make", "year", "model"].findIndex((key) => !this.answers[key])
    if (missingStep !== -1) {
      event.preventDefault()
      return this.go(missingStep)
    }
    for (const [field, box, display] of [[this.priceTarget, this.priceBoxTarget, this.priceDisplayTarget], [this.odometerTarget, this.odometerBoxTarget, this.odometerDisplayTarget]]) {
      if (!field.value) {
        event.preventDefault()
        if (this.current !== 3) this.go(3, { focus: false })
        box.classList.add("is-missing")
        return display.focus()
      }
    }
  }

  // ---- Live card ----

  renderCard() {
    const { make, year, model, price, odometer } = this.answers
    const known = (this.makesValue[this.country] || []).find((entry) => entry.name === make)
    const logo = make ? this.logoHTML(known || { name: make }) : `<span class="make-logo make-logo--mono make-logo--empty" aria-hidden="true">?</span>`
    if (this.cardLogoTarget.dataset.make !== make) {
      this.cardLogoTarget.dataset.make = make
      this.cardLogoTarget.innerHTML = logo
      this.pop(this.cardLogoTarget)
    }
    const title = make
      ? `${year ? `${this.escape(year)} ` : ""}${this.escape(make)} ${model ? this.escape(model) : `<span class="ghost">model</span>`}`
      : `<span class="ghost">Make and model</span>`
    if (this.cardTitleTarget.innerHTML !== title) {
      this.cardTitleTarget.innerHTML = title
      this.pop(this.cardTitleTarget)
    }
    this.cardOdoTarget.classList.toggle("is-empty", !odometer)
    this.cardOdoTarget.querySelector(".odo__digits").textContent = odometer ? this.number(odometer) : "––,–––"
    this.cardOdoTarget.querySelector(".odo__unit").textContent = this.market.unit
    this.cardAskingTarget.classList.toggle("is-empty", !price)
    this.cardAskingTarget.textContent = price ? `${this.money(price)} asking` : "Asking price"
  }

  pop(el) {
    el.classList.remove("is-popping")
    void el.offsetWidth
    el.classList.add("is-popping")
  }

  // ---- Country ----

  countryChanged(options = {}) {
    const market = this.market
    this.symbolTargets.forEach((el) => (el.textContent = market.symbol))
    this.unitTargets.forEach((el) => (el.textContent = market.unit))
    this.distanceWordTargets.forEach((el) => (el.textContent = this.distanceWord().replace(/^./, (c) => c.toUpperCase())))
    this.yearlyDistanceTarget.placeholder = market.yearly.toLocaleString()
    if (market.plate_example) this.plateTarget.placeholder = market.plate_example.replace(/^e\.g\. /, "")
    this.vinPanelTarget.hidden = market.lookup !== "vin"
    this.platePanelTarget.hidden = market.lookup !== "plate"
    this.lookupPromptTarget.textContent = market.lookup === "vin" ? "Have the VIN?" : "Have the plate?"
    this.fillRegions(market.regions, options.keepRegion === true)
    this.modelCache.clear()
    if (this.current === 0) this.renderMakes()
    if (this.current === 2) this.loadModels()
    if (this.current === 3) this.renderPriceStep()
    if (this.current !== undefined) { this.renderTrail(); this.renderCard() }
  }

  fillRegions(regions, keep) {
    const current = this.regionTarget.value
    this.regionTarget.replaceChildren(...regions.map((name) => new Option(name, name)))
    if (keep && regions.includes(current)) this.regionTarget.value = current
  }

  // ---- VIN and plate lookup ----

  lookupOnEnter(event) {
    event.preventDefault()
    this.lookup()
  }

  async lookup() {
    const params = new URLSearchParams()
    const mode = this.market.lookup
    if (mode === "vin") {
      const vin = this.vinTarget.value.trim().toUpperCase()
      if (vin.length !== 17) return this.showMessage("A VIN is 17 letters and numbers.")
      params.set("vin", vin)
    } else {
      const plate = this.plateTarget.value.trim()
      if (!plate) return this.showMessage("Enter the plate first.")
      params.set("plate", plate)
      params.set("country", this.country)
    }

    this.showMessage("Looking it up…", false)
    try {
      const response = await fetch(`${this.lookupUrlValue}?${params}`, { headers: { Accept: "application/json" } })
      const data = await response.json()
      if (!response.ok) throw new Error(data.error || "Lookup failed.")
      this.applyMatch(data, mode)
    } catch (error) {
      this.showMessage(error.message)
    }
  }

  applyMatch(car, mode) {
    this.lookupModeTarget.value = mode
    this.makeTarget.value = car.make || ""
    this.modelTarget.value = car.model || ""
    this.modelYearTarget.value = car.model_year || ""
    this.engineTarget.value = car.engine || ""
    this.fuelTarget.value = car.fuel_type || ""
    this.firstUsedTarget.value = car.first_used_on || ""
    this.showMessage(`Found it: ${[car.model_year, car.make, car.model].filter(Boolean).join(" ")}${car.source ? ` (from ${car.source})` : ""}.`, false)
    const missing = ["make", "year", "model"].findIndex((key) => !this.answers[key])
    this.go(missing === -1 ? 3 : missing)
  }

  showMessage(text, isError = true) {
    this.lookupMessageTarget.textContent = text
    this.lookupMessageTarget.style.color = isError ? "var(--critical)" : "var(--ink-2)"
    this.lookupMessageTarget.hidden = false
  }

  // ---- Assumptions ----

  fewerYears() { this.setYears(Number(this.yearsTarget.value) - 1) }
  moreYears() { this.setYears(Number(this.yearsTarget.value) + 1) }

  setYears(value) {
    const years = Math.min(10, Math.max(1, value || 3))
    this.yearsTarget.value = years
    this.yearsOutputTarget.textContent = `${years} ${years === 1 ? "year" : "years"}`
  }

  addonChanged() {
    const selected = this.element.querySelector("input[name='report[addon_warranty]']:checked")
    this.addonPanelTarget.hidden = !selected || selected.value === "none"
  }

  // ---- Helpers ----

  button(className, html) {
    const el = document.createElement("button")
    el.type = "button"
    el.className = className
    el.innerHTML = html
    return el
  }

  skeleton() {
    const el = document.createElement("span")
    el.className = "pick-chip pick-chip--skeleton"
    el.setAttribute("aria-hidden", "true")
    return el
  }

  logoHTML(make) {
    const initials = this.escape(make.name.match(/\b[\p{L}\p{N}]/gu)?.slice(0, 2).join("").toUpperCase() || "?")
    return make.logo
      ? `<img class="make-logo" src="${make.logo}" alt="" draggable="false" data-initials="${initials}">`
      : `<span class="make-logo make-logo--mono" aria-hidden="true">${initials}</span>`
  }

  distanceWord() { return this.market.unit === "km" ? "kilometers" : "miles" }
  number(value) { return Number(value).toLocaleString("en-US") }
  money(value) { return `${this.market.symbol}${this.number(value)}` }
  escape(text) { return String(text).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]) }
}
