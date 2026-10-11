import { Controller } from "@hotwired/stimulus"

const MAX_SIDE = 2560
const MIN_CROP = 0.05
const QUALITY = 0.9

// The preview's image editor (content_form/image_editor): an image-editor:open
// event (website-preview's "Crop & edit") names the asset and the form field
// it's in. The image is drawn turned and flipped on the canvas, the crop is a
// box over it (dragged, or its corners pulled, held to a shape if one's
// picked), and brightness, contrast and saturation show as filters. "Use this
// image" draws the crop at full size (MAX_SIDE at most), applies the
// adjustments to its pixels, uploads it as a copy of the asset
// (file_manager/assets/image_edits) and answers as the media picker does
// (asset-picker:picked), so the field, its thumbnail and the preview follow.
export default class extends Controller {
  static targets = [ "stage", "canvas", "crop", "loading", "title", "ratio", "slider", "output", "error", "saveButton" ]
  static values = { sourceUrl: String }

  connect() {
    this.move = this.move.bind(this)
    this.release = this.release.bind(this)
  }

  disconnect() {
    this.release()
  }

  async open(event) {
    const { assetId, field } = event.detail
    this.field = field
    this.url = this.sourceUrlValue.replace("ASSET_ID", encodeURIComponent(assetId))
    this.#resetState()
    this.errorTarget.hidden = true
    this.loadingTarget.hidden = false
    this.cropTarget.hidden = true
    this.element.showModal()

    try {
      const response = await fetch(this.url, { headers: { Accept: "application/json" } })
      if (!response.ok) throw new Error("This file can't be edited here.")
      const source = await response.json()
      this.titleTarget.textContent = `Edit ${source.name}`
      this.name = source.name
      this.image = await this.#load(source.url)
      this.loadingTarget.hidden = true
      this.cropTarget.hidden = false
      this.#draw()
    } catch (error) {
      this.#fail(error.message)
    }
  }

  close() {
    this.release()
    this.element.close()
  }

  // A shape for the crop: free, the image's own, or a width:height.
  aspect(event) {
    const value = event.currentTarget.dataset.ratio
    this.ratioTargets.forEach(chip => chip.setAttribute("aria-pressed", chip === event.currentTarget))
    const [ width, height ] = this.#oriented()
    this.ratio = value === "" ? null : value === "original" ? width / height : Number(value)
    this.crop = this.#largestCrop()
    this.#place()
  }

  rotateLeft() { this.#turn(3) }
  rotateRight() { this.#turn(1) }

  flipX() {
    this.flip.x = !this.flip.x
    this.crop.x = 1 - this.crop.x - this.crop.w
    this.#draw()
  }

  flipY() {
    this.flip.y = !this.flip.y
    this.crop.y = 1 - this.crop.y - this.crop.h
    this.#draw()
  }

  adjust(event) {
    const { key } = event.currentTarget.dataset
    this.adjustments[key] = Number(event.currentTarget.value)
    this.outputTargets.find(output => output.dataset.key === key).textContent = event.currentTarget.value
    this.#filter()
  }

  reset() {
    this.#resetState()
    if (this.image) this.#draw()
  }

  // Dragging the crop box, or one of its corners.
  grab(event) {
    event.preventDefault()
    const box = this.canvasTarget.getBoundingClientRect()
    this.drag = { corner: event.target.dataset.corner, x: event.clientX, y: event.clientY, crop: { ...this.crop }, width: box.width, height: box.height }
    window.addEventListener("pointermove", this.move)
    window.addEventListener("pointerup", this.release)
  }

  move(event) {
    if (!this.drag) return
    const { corner, crop: start, width, height } = this.drag
    const dx = (event.clientX - this.drag.x) / width
    const dy = (event.clientY - this.drag.y) / height

    if (!corner) {
      this.crop.x = clamp(start.x + dx, 0, 1 - start.w)
      this.crop.y = clamp(start.y + dy, 0, 1 - start.h)
    } else {
      this.crop = this.#resized(corner, start, dx, dy)
    }
    this.#place()
  }

  release() {
    this.drag = null
    window.removeEventListener("pointermove", this.move)
    window.removeEventListener("pointerup", this.release)
  }

  async save() {
    if (!this.image) return
    this.saveButtonTarget.disabled = true
    this.saveButtonTarget.textContent = "Saving…"
    try {
      const blob = await this.#export()
      const form = new FormData()
      form.append("image", blob, `${slug(this.name)}-edited.${blob.type === "image/webp" ? "webp" : "jpg"}`)
      const response = await fetch(this.url, {
        method: "POST", body: form,
        headers: { Accept: "application/json", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content }
      })
      const copy = await response.json().catch(() => ({}))
      if (!response.ok) throw new Error(copy.error || "The edited image couldn't be saved.")

      window.dispatchEvent(new CustomEvent("asset-picker:picked", { detail: { field: this.field, id: copy.id, name: copy.name, thumb: copy.thumb } }))
      this.close()
    } catch (error) {
      this.#fail(error.message)
    } finally {
      this.saveButtonTarget.disabled = false
      this.saveButtonTarget.textContent = "Use this image"
    }
  }

  #resetState() {
    this.turns = 0
    this.flip = { x: false, y: false }
    this.adjustments = { brightness: 0, contrast: 0, saturation: 0 }
    this.ratio = null
    this.crop = { x: 0, y: 0, w: 1, h: 1 }
    this.sliderTargets.forEach(slider => { slider.value = 0 })
    this.outputTargets.forEach(output => { output.textContent = "0" })
    this.ratioTargets.forEach(chip => chip.setAttribute("aria-pressed", chip.dataset.ratio === ""))
  }

  #load(url) {
    return new Promise((resolve, reject) => {
      const image = new Image()
      image.onload = () => resolve(image)
      image.onerror = () => reject(new Error("The image didn't load."))
      image.src = url
    })
  }

  // The image's size as it's turned.
  #oriented() {
    const { naturalWidth: width, naturalHeight: height } = this.image
    return this.turns % 2 ? [ height, width ] : [ width, height ]
  }

  #turn(quarters) {
    this.turns = (this.turns + quarters) % 4
    if (this.ratio) {
      const [ width, height ] = this.#oriented()
      if (this.ratioTargets.find(chip => chip.getAttribute("aria-pressed") === "true")?.dataset.ratio === "original") this.ratio = width / height
    }
    this.crop = this.#largestCrop()
    this.#draw()
  }

  // The image, turned and flipped, as large as the stage allows.
  #draw() {
    const [ width, height ] = this.#oriented()
    const stage = this.stageTarget.getBoundingClientRect()
    const scale = Math.min((stage.width - 32) / width, (stage.height - 32) / height, 1)
    this.canvasTarget.width = Math.round(width * scale)
    this.canvasTarget.height = Math.round(height * scale)
    this.#paint(this.canvasTarget, scale)
    this.#filter()
    this.#place()
  }

  #paint(canvas, scale) {
    const context = canvas.getContext("2d")
    const { naturalWidth: width, naturalHeight: height } = this.image
    context.save()
    context.translate(canvas.width / 2, canvas.height / 2)
    context.scale(this.flip.x ? -1 : 1, this.flip.y ? -1 : 1)
    context.rotate(this.turns * Math.PI / 2)
    context.drawImage(this.image, -width * scale / 2, -height * scale / 2, width * scale, height * scale)
    context.restore()
  }

  #filter() {
    const { brightness, contrast, saturation } = this.adjustments
    this.canvasTarget.style.filter = `brightness(${1 + brightness / 100}) contrast(${1 + contrast / 100}) saturate(${1 + saturation / 100})`
  }

  // The crop box over the canvas.
  #place() {
    const canvas = this.canvasTarget
    Object.assign(this.cropTarget.style, {
      left: `${canvas.offsetLeft + this.crop.x * canvas.width}px`,
      top: `${canvas.offsetTop + this.crop.y * canvas.height}px`,
      width: `${this.crop.w * canvas.width}px`,
      height: `${this.crop.h * canvas.height}px`
    })
  }

  // The largest crop of the shape picked, in the middle; all of it for free.
  #largestCrop() {
    if (!this.ratio) return { x: 0, y: 0, w: 1, h: 1 }
    const [ width, height ] = this.#oriented()
    const shape = this.ratio * height / width
    const w = shape > 1 ? 1 : shape
    const h = shape > 1 ? 1 / shape : 1
    return { x: (1 - w) / 2, y: (1 - h) / 2, w, h }
  }

  // A corner pulled: the opposite one stays put; held to the shape, if any.
  #resized(corner, start, dx, dy) {
    const anchorX = corner.includes("w") ? start.x + start.w : start.x
    const anchorY = corner.includes("n") ? start.y + start.h : start.y
    const left = corner.includes("w")
    const up = corner.includes("n")
    let w = Math.max(MIN_CROP, left ? start.w - dx : start.w + dx)
    let h = Math.max(MIN_CROP, up ? start.h - dy : start.h + dy)
    const roomX = left ? anchorX : 1 - anchorX
    const roomY = up ? anchorY : 1 - anchorY

    if (this.ratio) {
      const [ width, height ] = this.#oriented()
      const shape = this.ratio * height / width
      if (w / h > shape) h = w / shape
      else w = h * shape
      const fit = Math.min(1, roomX / w, roomY / h)
      w *= fit
      h *= fit
    } else {
      w = Math.min(w, roomX)
      h = Math.min(h, roomY)
    }
    return { x: left ? anchorX - w : anchorX, y: up ? anchorY - h : anchorY, w, h }
  }

  // The crop at full size (MAX_SIDE at most), adjusted, as WebP (or JPEG
  // where the browser can't write WebP; the server makes it lighter).
  async #export() {
    const [ width, height ] = this.#oriented()
    const cropWidth = this.crop.w * width
    const cropHeight = this.crop.h * height
    const scale = Math.min(1, MAX_SIDE / Math.max(cropWidth, cropHeight))

    const whole = document.createElement("canvas")
    whole.width = Math.round(width * scale)
    whole.height = Math.round(height * scale)
    this.#paint(whole, scale)

    const out = document.createElement("canvas")
    out.width = Math.max(1, Math.round(cropWidth * scale))
    out.height = Math.max(1, Math.round(cropHeight * scale))
    const context = out.getContext("2d")
    const type = webpSupported() ? "image/webp" : "image/jpeg"
    if (type === "image/jpeg") {
      context.fillStyle = "#fff"
      context.fillRect(0, 0, out.width, out.height)
    }
    context.drawImage(whole, this.crop.x * whole.width, this.crop.y * whole.height, out.width, out.height, 0, 0, out.width, out.height)
    this.#applyAdjustments(context, out.width, out.height)

    return new Promise((resolve, reject) => out.toBlob(blob => blob ? resolve(blob) : reject(new Error("The browser couldn't write the image.")), type, QUALITY))
  }

  // As the filters showed them: brightness, then contrast, then saturation.
  #applyAdjustments(context, width, height) {
    const { brightness, contrast, saturation } = this.adjustments
    if (!brightness && !contrast && !saturation) return
    const b = 1 + brightness / 100
    const c = 1 + contrast / 100
    const s = 1 + saturation / 100
    const pixels = context.getImageData(0, 0, width, height)
    const data = pixels.data
    for (let i = 0; i < data.length; i += 4) {
      let r = ((data[i] * b) - 127.5) * c + 127.5
      let g = ((data[i + 1] * b) - 127.5) * c + 127.5
      let bl = ((data[i + 2] * b) - 127.5) * c + 127.5
      const gray = 0.2126 * r + 0.7152 * g + 0.0722 * bl
      data[i] = gray + (r - gray) * s
      data[i + 1] = gray + (g - gray) * s
      data[i + 2] = gray + (bl - gray) * s
    }
    context.putImageData(pixels, 0, 0)
  }

  #fail(message) {
    this.loadingTarget.hidden = true
    this.errorTarget.textContent = message
    this.errorTarget.hidden = false
  }
}

function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max)
}

function slug(name) {
  return String(name || "image").toLowerCase().replace(/\.[a-z0-9]+$/, "").replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "image"
}

let webp
function webpSupported() {
  if (webp === undefined) {
    const canvas = document.createElement("canvas")
    canvas.width = canvas.height = 1
    webp = canvas.toDataURL("image/webp").startsWith("data:image/webp")
  }
  return webp
}
