import { Controller } from "@hotwired/stimulus"

// Copies text to clipboard and shows a brief confirmation.
// Usage: <button data-controller="clipboard" data-clipboard-text-value="text to copy">Copiar</button>
export default class extends Controller {
  static values = { text: String }
  static targets = ["button"]

  copy() {
    navigator.clipboard.writeText(this.textValue).then(() => {
      this.showConfirmation()
    })
  }

  showConfirmation() {
    const button = this.hasButtonTarget ? this.buttonTarget : this.element
    const originalText = button.textContent
    button.textContent = "¡Copiado!"
    button.classList.add("bg-green-100", "text-green-700")

    setTimeout(() => {
      button.textContent = originalText
      button.classList.remove("bg-green-100", "text-green-700")
    }, 2000)
  }
}
