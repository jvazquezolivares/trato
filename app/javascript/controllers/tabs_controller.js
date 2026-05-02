import { Controller } from "@hotwired/stimulus"

// Manages tab switching in the provider panel using Turbo Frames.
// Highlights the active tab and loads content via Turbo Frame navigation.
export default class extends Controller {
  static targets = ["tab", "content"]
  static values = { activeTab: String }

  connect() {
    this.highlightActiveTab()
  }

  switch(event) {
    event.preventDefault()
    const tabName = event.currentTarget.dataset.tabName

    this.activeTabValue = tabName
    this.highlightActiveTab()

    // Update URL without page reload for bookmarkability
    const url = new URL(window.location)
    url.searchParams.set("tab", tabName)
    history.replaceState({}, "", url)
  }

  highlightActiveTab() {
    this.tabTargets.forEach((tab) => {
      const isActive = tab.dataset.tabName === this.activeTabValue

      if (isActive) {
        tab.classList.add("text-[#0F766E]", "font-bold", "border-b-2", "border-[#0F766E]")
        tab.classList.remove("text-[#64748B]", "font-medium")
      } else {
        tab.classList.remove("text-[#0F766E]", "font-bold", "border-b-2", "border-[#0F766E]")
        tab.classList.add("text-[#64748B]", "font-medium")
      }
    })
  }
}
