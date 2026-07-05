import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="sidebar"
export default class extends Controller {
  static targets = [
    "desktopSidebar",
    "mobileSidebar",
    "contentTemplate",
    "sharedContent",
    "desktopContent",
    "mobileBackdrop",
    "mobilePanel",
  ];
  static values = {
    storageKey: { type: String, default: "sidebarOpen" },
  };

  connect() {
    // Bind the handler once so we can properly remove it later
    this.boundHandleToggle = this.handleToggle.bind(this);

    // Clone the shared sidebar content into both the desktop expanded panel and the mobile panel
    if (this.hasContentTemplateTarget) {
      if (this.hasDesktopContentTarget && !this.desktopContentTarget.querySelector("nav")) {
        this.desktopContentTarget.appendChild(this.contentTemplateTarget.content.cloneNode(true));
      }

      if (this.hasSharedContentTarget && !this.sharedContentTarget.querySelector("nav")) {
        this.sharedContentTarget.appendChild(this.contentTemplateTarget.content.cloneNode(true));

        // In the mobile clone, the header button should close the mobile overlay (not collapse the desktop rail)
        const mobileNav = this.sharedContentTarget.querySelector("nav");
        const closeButton = mobileNav?.querySelector('[data-action*="sidebar#close"]');
        if (closeButton) {
          closeButton.setAttribute("data-action", "click->sidebar#closeMobile");
          closeButton.setAttribute("aria-label", "Close sidebar");

          const icon = closeButton.querySelector(".material-symbols-outlined");
          if (icon) icon.textContent = "close";
        }
      }
    }

    if (this.hasDesktopSidebarTarget) {
      // Temporarily disable transitions to prevent animation on page load
      this.desktopSidebarTarget.style.transition = "none";

      // Restore the saved state from localStorage, default to open if no saved state
      const savedState = localStorage.getItem(this.storageKeyValue);

      if (savedState !== null) {
        this.desktopSidebarTarget.open = savedState === "true";
      } else {
        // Default to open for first-time visitors
        this.desktopSidebarTarget.open = true;
      }

      // Re-enable transitions after a brief delay
      requestAnimationFrame(() => {
        requestAnimationFrame(() => {
          this.desktopSidebarTarget.style.transition = "";
        });
      });

      // Listen for toggle events to save the state
      this.desktopSidebarTarget.addEventListener("toggle", this.boundHandleToggle);
    }
  }

  disconnect() {
    if (this.hasDesktopSidebarTarget && this.boundHandleToggle) {
      this.desktopSidebarTarget.removeEventListener("toggle", this.boundHandleToggle);
    }
  }

  handleToggle(event) {
    // Save the current state to localStorage
    localStorage.setItem(this.storageKeyValue, this.desktopSidebarTarget.open.toString());
  }

  open() {
    if (this.hasDesktopSidebarTarget) {
      this.desktopSidebarTarget.open = true;
    }
  }

  close() {
    if (this.hasDesktopSidebarTarget) {
      this.desktopSidebarTarget.open = false;
    }
  }

  toggle() {
    if (this.hasDesktopSidebarTarget) {
      this.desktopSidebarTarget.open = !this.desktopSidebarTarget.open;
    }
  }

  openMobile() {
    if (this.hasMobileSidebarTarget) {
      // Set initial hidden states
      if (this.hasMobileBackdropTarget) {
        this.mobileBackdropTarget.style.opacity = "0";
      }
      if (this.hasMobilePanelTarget) {
        this.mobilePanelTarget.style.transform = "translateX(-100%)";
      }

      // Remove hidden class
      this.mobileSidebarTarget.classList.remove("hidden");

      // Trigger transition on next frame
      requestAnimationFrame(() => {
        if (this.hasMobileBackdropTarget) {
          this.mobileBackdropTarget.style.opacity = "1";
        }
        if (this.hasMobilePanelTarget) {
          this.mobilePanelTarget.style.transform = "translateX(0)";
        }
      });
    }
  }

  closeMobile() {
    if (this.hasMobileSidebarTarget) {
      // Trigger closing transition
      if (this.hasMobileBackdropTarget) {
        this.mobileBackdropTarget.style.opacity = "0";
      }
      if (this.hasMobilePanelTarget) {
        this.mobilePanelTarget.style.transform = "translateX(-100%)";
      }

      // Wait for transition to complete before hiding
      setTimeout(() => {
        if (this.hasMobileSidebarTarget) {
          this.mobileSidebarTarget.classList.add("hidden");
        }
      }, 300); // Match the transition duration
    }
  }
}
