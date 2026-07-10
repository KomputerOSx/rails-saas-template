import { Controller } from "@hotwired/stimulus"
import { Editor } from "@tiptap/core"
import StarterKit from "@tiptap/starter-kit"
import Underline from "@tiptap/extension-underline"
import Link from "@tiptap/extension-link"

// Mounts a TipTap editor and mirrors its HTML into a hidden form field on every change, so the
// enclosing form posts the body like any other plain field - no fetch/JSON involved. StarterKit
// is trimmed to exactly the tag set EmailCampaign's server-side sanitizer allow-lists (see
// EmailCampaign::ALLOWED_TAGS) so nothing a user can type gets silently stripped on save.
export default class extends Controller {
  static targets = [ "editor", "hiddenField" ]

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
        Link.configure({ openOnClick: false })
      ],
      content: this.hiddenFieldTarget.value || "",
      onUpdate: () => this.syncHiddenField()
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
}
