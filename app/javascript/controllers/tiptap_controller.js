import { Controller } from "@hotwired/stimulus"
import { Editor } from '@tiptap/core'
import StarterKit from '@tiptap/starter-kit'

export default class extends Controller {
  static targets = [ "input", "editorContainer" ]

  connect() {
    this.editor = new Editor({
      element: this.editorContainerTarget,
      extensions: [
        StarterKit,
      ],
      // Load initial content from the hidden field (useful for editing drafts)
      content: this.inputTarget.value,
      editorProps: {
        attributes: {
          class: 'prose prose-sm sm:prose lg:prose-lg xl:prose-2xl focus:outline-none min-h-[300px] p-4',
        },
      },
      onUpdate: ({ editor }) => {
        // Sync the Tiptap HTML into the hidden Rails form field
        this.inputTarget.value = editor.getHTML()
      }
    })
  }

  disconnect() {
    if (this.editor) {
      this.editor.destroy()
    }
  }
}