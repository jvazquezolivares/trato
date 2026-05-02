import { Controller } from "@hotwired/stimulus"

// Manages the 6-digit OTP input boxes on the login verification page.
// Auto-advances focus between digits, handles paste, and collects
// the full code into a hidden field before form submission.
export default class extends Controller {
  static targets = ["digit", "hiddenCode"]

  connect() {
    this.digitTargets.forEach((input, index) => {
      input.addEventListener("input", (event) => this.handleInput(event, index))
      input.addEventListener("keydown", (event) => this.handleKeydown(event, index))
      input.addEventListener("paste", (event) => this.handlePaste(event))
    })

    // Focus the first digit on page load
    this.digitTargets[0]?.focus()
  }

  handleInput(event, index) {
    const value = event.target.value

    // Only allow single digits
    if (!/^\d$/.test(value)) {
      event.target.value = ""
      return
    }

    // Auto-advance to next digit
    if (index < this.digitTargets.length - 1) {
      this.digitTargets[index + 1].focus()
    }

    this.updateHiddenCode()
  }

  handleKeydown(event, index) {
    // Backspace moves to previous digit
    if (event.key === "Backspace" && !event.target.value && index > 0) {
      this.digitTargets[index - 1].focus()
      this.digitTargets[index - 1].value = ""
      this.updateHiddenCode()
    }
  }

  handlePaste(event) {
    event.preventDefault()
    const pasted = (event.clipboardData || window.clipboardData).getData("text").trim()
    const digits = pasted.replace(/\D/g, "").slice(0, 6)

    digits.split("").forEach((digit, i) => {
      if (this.digitTargets[i]) {
        this.digitTargets[i].value = digit
      }
    })

    // Focus the next empty digit or the last one
    const nextEmpty = this.digitTargets.findIndex((input) => !input.value)
    const focusIndex = nextEmpty === -1 ? this.digitTargets.length - 1 : nextEmpty
    this.digitTargets[focusIndex]?.focus()

    this.updateHiddenCode()
  }

  updateHiddenCode() {
    const code = this.digitTargets.map((input) => input.value).join("")
    this.hiddenCodeTarget.value = code
  }
}
