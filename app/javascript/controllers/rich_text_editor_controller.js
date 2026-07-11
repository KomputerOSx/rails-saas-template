import { Controller } from "@hotwired/stimulus"
import { Editor } from "@tiptap/core"
import StarterKit from "@tiptap/starter-kit"
import Underline from "@tiptap/extension-underline"
import Link from "@tiptap/extension-link"
import TextStyle from "@tiptap/extension-text-style"
import Color from "@tiptap/extension-color"
import Image from "@tiptap/extension-image"

// Link's default schema drops any attribute it doesn't declare, so a bare `style` set via
// insertButton() below would vanish on the next getHTML() - extend it to keep one.
const CampaignLink = Link.extend({
  addAttributes() {
    return {
      ...this.parent(),
      style: {
        default: null,
        parseHTML: element => element.getAttribute("style"),
        renderHTML: attributes => attributes.style ? { style: attributes.style } : {}
      }
    }
  }
})

// Image's default schema has no width attribute. Uses the legacy HTML attribute, not a CSS
// style, since Outlook desktop often ignores CSS sizing on <img> but respects the attribute.
const ResizableImage = Image.extend({
  addAttributes() {
    return {
      ...this.parent(),
      width: {
        default: null,
        parseHTML: element => element.getAttribute("width"),
        renderHTML: attributes => attributes.width ? { width: attributes.width } : {}
      }
    }
  }
})

const BUTTON_COLORS = {
  green: "#009e3c",
  blue: "#0066cc",
  red: "#dc2626",
  purple: "#7c3aed",
  black: "#111111"
}

const buttonStyle = (color) =>
  `display:inline-block;padding:10px 20px;background-color:${color};color:#ffffff;border-radius:6px;text-decoration:none;font-weight:600;`

const IMAGE_WIDTHS = { small: "200", medium: "400", full: "600" }

// Mirrors editor.getHTML() into a hidden field on every change, so the form posts the body like
// any other plain field. Enabled marks/nodes must stay in sync with EmailCampaign::ALLOWED_TAGS.
export default class extends Controller {
  static targets = [ "editor", "hiddenField", "fileInput", "buttonColor", "buttonDialog", "buttonLabelInput", "buttonUrlInput", "widthButton", "maxWidthField", "canvas", "bgColorField", "linkDialog", "linkUrlInput" ]
  static values = { maxWidth: Number }

  connect() {
    this.editor = new Editor({
      element: this.editorTarget,
      extensions: [
        StarterKit.configure({
          codeBlock: false,
          code: false,
          horizontalRule: false,
          strike: false,
          heading: { levels: [ 1, 2, 3 ] }
        }),
        Underline,
        CampaignLink.configure({ openOnClick: false }),
        TextStyle,
        Color,
        ResizableImage
      ],
      content: this.hiddenFieldTarget.value || "",
      onUpdate: () => this.syncHiddenField()
    })

    // Dead-zone fallback for clicks landing on the wrapper's own padding, not covered by the
    // flex-1 CSS fix. Guarded to the wrapper itself so it never fights clicks inside content.
    this.editorTarget.addEventListener("click", (event) => {
      if (event.target === this.editorTarget) this.editor.commands.focus()
    })

    this.applyEmailWidth(this.maxWidthValue)
  }

  disconnect() {
    this.editor?.destroy()
  }

  syncHiddenField() {
    this.hiddenFieldTarget.value = this.editor.getHTML()
  }

  toggleBold() {
    this.editor.chain().focus().toggleBold().run()
  }

  toggleItalic() {
    this.editor.chain().focus().toggleItalic().run()
  }

  toggleUnderline() {
    this.editor.chain().focus().toggleUnderline().run()
  }

  toggleH1() {
    this.editor.chain().focus().toggleHeading({ level: 1 }).run()
  }

  toggleH2() {
    this.editor.chain().focus().toggleHeading({ level: 2 }).run()
  }

  toggleH3() {
    this.editor.chain().focus().toggleHeading({ level: 3 }).run()
  }

  toggleBulletList() {
    this.editor.chain().focus().toggleBulletList().run()
  }

  toggleOrderedList() {
    this.editor.chain().focus().toggleOrderedList().run()
  }

  toggleBlockquote() {
    this.editor.chain().focus().toggleBlockquote().run()
  }

  openLinkDialog() {
    this.linkUrlInputTarget.value = this.editor.getAttributes("link").href || ""
    this.linkDialogTarget.showModal()
  }

  insertLink() {
    const url = this.linkUrlInputTarget.value.trim()
    if (!url) return

    this.editor.chain().focus().setLink({ href: url }).run()
    this.linkDialogTarget.close()
  }

  unsetLink() {
    this.editor.chain().focus().unsetLink().run()
  }

  setColor(event) {
    this.editor.chain().focus().setColor(event.target.value).run()
  }

  unsetColor() {
    this.editor.chain().focus().unsetColor().run()
  }

  insertButton() {
    const label = this.buttonLabelInputTarget.value.trim()
    const url = this.buttonUrlInputTarget.value.trim()
    if (!label || !url) return

    const color = BUTTON_COLORS[this.buttonColorTarget.value] || BUTTON_COLORS.green

    this.editor.chain().focus().insertContent({
      type: "text",
      text: label,
      marks: [ { type: "link", attrs: { href: url, style: buttonStyle(color) } } ]
    }).run()

    this.buttonLabelInputTarget.value = ""
    this.buttonUrlInputTarget.value = ""
    this.buttonDialogTarget.close()
  }

  triggerImageUpload() {
    this.fileInputTarget.click()
  }

  async uploadImage(event) {
    const file = event.target.files[0]
    event.target.value = ""
    if (!file) return

    const formData = new FormData()
    formData.append("file", file)

    const response = await fetch("/admin/email_campaign_images", {
      method: "POST",
      headers: { "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content },
      body: formData
    })

    const body = await response.json()

    if (!response.ok) {
      window.alert(body.error || "Image upload failed.")
      return
    }

    const { url } = body
    this.editor.chain().focus().setImage({ src: url }).run()
  }

  // Applies to whichever image node is currently selected - a no-op if none is.
  setImageSizeSmall() {
    this.editor.chain().focus().updateAttributes("image", { width: IMAGE_WIDTHS.small }).run()
  }

  setImageSizeMedium() {
    this.editor.chain().focus().updateAttributes("image", { width: IMAGE_WIDTHS.medium }).run()
  }

  setImageSizeFull() {
    this.editor.chain().focus().updateAttributes("image", { width: IMAGE_WIDTHS.full }).run()
  }

  unsetImageSize() {
    this.editor.chain().focus().updateAttributes("image", { width: null }).run()
  }

  setEmailWidth(event) {
    this.applyEmailWidth(Number(event.currentTarget.dataset.width))
  }

  setBgColor(event) {
    this.canvasTarget.style.backgroundColor = event.target.value
    this.bgColorFieldTarget.value = event.target.value
  }

  applyEmailWidth(width) {
    this.editorTarget.style.maxWidth = `${width}px`
    this.editorTarget.style.marginLeft = "auto"
    this.editorTarget.style.marginRight = "auto"
    this.maxWidthFieldTarget.value = width

    this.widthButtonTargets.forEach((button) => {
      const active = Number(button.dataset.width) === width
      button.classList.toggle("btn-primary", active)
      button.classList.toggle("btn-ghost", !active)
    })
  }
}
