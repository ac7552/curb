// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

// A make badge that fails to load becomes the make's initials. Load errors don't bubble, so this
// listens in the capture phase.
document.addEventListener("error", (event) => {
  const img = event.target
  if (!(img instanceof HTMLImageElement) || !img.classList.contains("make-logo")) return
  const mono = document.createElement("span")
  mono.className = "make-logo make-logo--mono"
  mono.setAttribute("aria-hidden", "true")
  mono.textContent = img.dataset.initials || ""
  img.replaceWith(mono)
}, true)
