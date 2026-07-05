import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="sidebar"
//
// The desktop sidebar renders one single markup for both states; collapsing
// only toggles [data-collapsed] on the <aside>, which the Tailwind
// group-data-[collapsed]/sidebar variants react to. State is persisted to
// localStorage ("true" = open, kept compatible with the previous implementation).
export default class extends Controller {
  static targets = ["desktopSidebar", "mobileSidebar", "mobileBackdrop", "mobilePanel", "toggleIcon"];
  static values = {
    storageKey: { type: String, default: "sidebarOpen" },
  };

  connect() {
    if (!this.hasDesktopSidebarTarget) return;

    // Temporarily disable transitions so the restored state doesn't animate on page load
    this.desktopSidebarTarget.style.transition = "none";

    const savedState = localStorage.getItem(this.storageKeyValue);
    this._applyCollapsed(savedState === "false");

    // Re-enable transitions after the restored state has painted
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        this.desktopSidebarTarget.style.transition = "";
      });
    });
  }

  open() {
    this._setOpen(true);
  }

  close() {
    this._setOpen(false);
  }

  toggle() {
    this._setOpen(this.desktopSidebarTarget.hasAttribute("data-collapsed"));
  }

  _setOpen(open) {
    if (!this.hasDesktopSidebarTarget) return;

    this._applyCollapsed(!open);
    localStorage.setItem(this.storageKeyValue, open.toString());
  }

  _applyCollapsed(collapsed) {
    const sidebar = this.desktopSidebarTarget;
    sidebar.toggleAttribute("data-collapsed", collapsed);

    // Swap the glyph in JS: the Material Symbols stylesheet is unlayered, so it
    // overrides Tailwind's layered `hidden` utility and a two-span CSS swap fails
    if (this.hasToggleIconTarget) {
      this.toggleIconTarget.textContent = collapsed ? "right_panel_close" : "left_panel_close";
    }

    // Icon-only rows need tooltips, but only while collapsed. Adding/removing
    // data-controller lets Stimulus connect/disconnect the tooltip controller,
    // so tooltips never appear while the labels are visible.
    sidebar.querySelectorAll("[data-tooltip-content]").forEach((item) => {
      if (collapsed) {
        item.setAttribute("data-controller", "tooltip");
      } else {
        item.removeAttribute("data-controller");
      }
    });
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
