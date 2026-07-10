import { Controller } from "@hotwired/stimulus"
import { Editor } from "@tiptap/core"
import StarterKit from "@tiptap/starter-kit"
import Underline from "@tiptap/extension-underline"
import Link from "@tiptap/extension-link"
import TextStyle from "@tiptap/extension-text-style"
import Color from "@tiptap/extension-color"
import Image from "@tiptap/extension-image"

// Link's default schema only declares href/target/rel/class, so a bare `style` attribute would
// be silently dropped on every getHTML() serialization - extend it once so insertButton() below
// can carry a fixed inline style. Plain links (setLink()) never set `style`, so they're unaffected.
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

const BUTTON_STYLE = "display:inline-block;padding:10px 20px;background-color:#009e3c;color:#ffffff;border-radius:6px;text-decoration:none;font-weight:600;"

// Mounts a TipTap editor and mirrors its HTML into a hidden form field on every change, so the
// enclosing form posts the body like any other plain field - no fetch/JSON involved. StarterKit
// is trimmed to exactly the tag set EmailCampaign's server-side sanitizer allow-lists (see
// EmailCampaign::ALLOWED_TAGS) so nothing a user can type gets silently stripped on save.
export default class extends Controller {
  static targets = [ "editor", "hiddenField", "fileInput" ]

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
        Image
      ],
      content: this.hiddenFieldTarget.value || "",
      onUpdate: () => this.syncHiddenField()
    })

    // Dead-zone fallback: the CSS fix (.tiptap-editor-area .ProseMirror { flex: 1 }) covers most
    // of the wrapper, but a click landing exactly on the wrapper's own padding still misses the
    // contenteditable child. Only fire when the click target is the wrapper itself, so this never
    // interferes with normal clicks/drags inside actual content.
    this.editorTarget.addEventListener("click", (event) => {
      if (event.target === this.editorTarget) this.editor.commands.focus()
    })
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

  setLink() {
    const url = window.prompt("Link URL")
    if (url === null) return

    if (url === "") {
      this.editor.chain().focus().unsetLink().run()
    } else {
      this.editor.chain().focus().setLink({ href: url }).run()
    }
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
    const label = window.prompt("Button label")
    if (!label) return

    const url = window.prompt("Button URL")
    if (!url) return

    this.editor.chain().focus().insertContent({
      type: "text",
      text: label,
      marks: [ { type: "link", attrs: { href: url, style: BUTTON_STYLE } } ]
    }).run()
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

    if (!response.ok) {
      window.alert("Image upload failed.")
      return
    }

    const { url } = await response.json()
    this.editor.chain().focus().setImage({ src: url }).run()
  }
}
