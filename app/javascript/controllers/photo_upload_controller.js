import { Controller } from "@hotwired/stimulus"

// Handles photo upload interactions in the provider panel.
// Manages the file input trigger and preview before upload.
export default class extends Controller {
  static targets = ["input", "preview", "counter"]
  static values = { maxPhotos: Number, currentCount: Number }

  trigger() {
    this.inputTarget.click()
  }

  preview() {
    const file = this.inputTarget.files[0]
    if (!file) return

    // Validate file type
    if (!file.type.startsWith("image/")) {
      alert("Solo se permiten archivos de imagen (JPG, PNG)")
      this.inputTarget.value = ""
      return
    }

    // Validate file size (max 10MB)
    const maxSize = 10 * 1024 * 1024
    if (file.size > maxSize) {
      alert("La imagen no puede superar los 10 MB")
      this.inputTarget.value = ""
      return
    }

    // Submit the form
    this.element.closest("form").requestSubmit()
  }
}
