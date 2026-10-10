import { Controller } from "@hotwired/stimulus"

// An image field you drop a file on (or click to choose one): the file input
// covers the zone, so dropping and clicking are the browser's own. Shows the
// chosen image before it's saved; Remove clears both the new file and the
// current one (the hidden id).
export default class extends Controller {
  static targets = [ "file", "id", "preview", "remove" ]

  over(event) {
    event.preventDefault()
    this.element.classList.add("image-dropzone--over")
  }

  leave() {
    this.element.classList.remove("image-dropzone--over")
  }

  dropped() {
    this.leave()
  }

  chosen() {
    const file = this.fileTarget.files[0]
    if (!file) return

    const image = document.createElement("img")
    image.src = URL.createObjectURL(file)
    image.alt = ""
    this.previewTarget.replaceChildren(image)
    this.element.classList.add("image-dropzone--filled")
    this.removeTarget.hidden = false
  }

  remove() {
    this.fileTarget.value = ""
    this.idTarget.value = ""
    this.previewTarget.replaceChildren()
    this.element.classList.remove("image-dropzone--filled")
    this.removeTarget.hidden = true
  }
}
