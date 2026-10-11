// Editing in place, inside the editor's preview (Website::InlineEdit): the
// server drew each editable value between invisible markers naming its
// field. This turns marked text into editable text, strips the markers from
// everywhere else (attributes, the <head>, scripts), and sends each edit to
// the editor (website_preview_controller), whose form it changes. An image
// a block's field holds (data-lp-image) gets Replace and Edit on a click,
// which the editor carries out. Plain script, no dependencies: it runs inside
// the theme's page.
(() => {
  const START = "⁣"
  const DIGITS = ["​", "‌", "‍", "⁠"]
  const MARKED = /⁣([​‌‍⁠]+)⁣([\s\S]*?)⁤/g
  const LEFTOVER = /⁣[​‌‍⁠]*⁣?|⁤/g
  const source = document.getElementById("lp-inline-edit")
  if (!source) return
  const fields = JSON.parse(source.textContent).fields

  const decode = digits => parseInt([...digits].map(c => DIGITS.indexOf(c)).join(""), 4)
  const strip = text => text.replace(MARKED, "$2").replace(LEFTOVER, "")

  document.title = strip(document.title)
  for (const element of document.querySelectorAll("*")) {
    for (const attribute of [...element.attributes]) {
      if (attribute.value.includes(START)) element.setAttribute(attribute.name, strip(attribute.value))
    }
  }

  const walker = document.createTreeWalker(document.documentElement, NodeFilter.SHOW_TEXT)
  const nodes = []
  while (walker.nextNode()) nodes.push(walker.currentNode)

  for (const node of nodes) {
    const text = node.nodeValue
    if (!text.includes(START) && !text.includes("⁤")) continue
    if (node.parentElement?.closest("head, script, style, textarea, title, option")) {
      node.nodeValue = strip(text)
      continue
    }
    const fragment = document.createDocumentFragment()
    let last = 0
    for (const match of text.matchAll(MARKED)) {
      fragment.append(text.slice(last, match.index).replace(LEFTOVER, ""))
      const span = document.createElement("span")
      span.textContent = match[2]
      span.className = "lp-editable"
      span.dataset.lpField = fields[decode(match[1])]
      span.contentEditable = "plaintext-only"
      span.spellcheck = true
      fragment.append(span)
      last = match.index + match[0].length
    }
    fragment.append(text.slice(last).replace(LEFTOVER, ""))
    node.replaceWith(fragment)
  }

  const style = document.createElement("style")
  style.textContent = `
    .lp-editable { outline: 1px dashed transparent; outline-offset: 2px; border-radius: 2px; cursor: text; transition: outline-color .15s; }
    .lp-editable:hover { outline-color: rgb(37 99 235 / .5); }
    .lp-editable:focus { outline: 2px solid rgb(37 99 235); background: rgb(37 99 235 / .06); }
    .lp-save { position: fixed; right: 1.25rem; top: 1.25rem; z-index: 2147483647; display: flex; align-items: center; gap: .6rem;
      padding: .7rem 1.1rem; border: 0; border-radius: 999px; background: rgb(37 99 235); color: #fff; cursor: pointer;
      font: 600 15px/1 ui-sans-serif, system-ui, -apple-system, sans-serif; box-shadow: 0 8px 24px rgb(0 0 0 / .25);
      transform: translateY(-200%); transition: transform .2s ease; }
    .lp-save.lp-save--shown { transform: none; }
    .lp-save:hover { background: rgb(29 78 216); }
    .lp-save small { font-weight: 500; opacity: .85; }
    img[data-lp-image] { cursor: pointer; outline: 2px dashed transparent; outline-offset: -2px; transition: outline-color .15s; }
    img[data-lp-image]:hover, img[data-lp-image].lp-image--picked { outline-color: rgb(37 99 235); }
    .lp-image-tools { position: absolute; z-index: 2147483646; display: flex; gap: .35rem; padding: .35rem; border-radius: 999px;
      background: rgb(17 24 39 / .9); box-shadow: 0 6px 18px rgb(0 0 0 / .3); }
    .lp-image-tools[hidden] { display: none; }
    .lp-image-tools button { border: 0; border-radius: 999px; padding: .45rem .85rem; background: transparent; color: #fff; cursor: pointer;
      font: 600 13px/1 ui-sans-serif, system-ui, -apple-system, sans-serif; }
    .lp-image-tools button:hover { background: rgb(255 255 255 / .15); }`
  document.head.append(style)

  // Surfaces with the first edit: how many changes wait, and saving them.
  const save = document.createElement("button")
  save.type = "button"
  save.className = "lp-save"
  save.innerHTML = "Save <small></small>"
  save.addEventListener("click", () => {
    save.disabled = true
    save.firstChild.textContent = "Saving… "
    window.parent.postMessage({ type: "lp-inline-save" }, window.location.origin)
  })
  document.body.append(save)
  const edited = new Set()
  const showEdited = () => {
    if (!edited.size) return
    save.querySelector("small").textContent = edited.size === 1 ? "1 change" : `${edited.size} changes`
    save.classList.add("lp-save--shown")
  }

  // An image: a click puts Replace and Edit over it, which the editor does
  // (the media picker; the image editor), then draws the preview again.
  const tools = document.createElement("div")
  tools.className = "lp-image-tools"
  tools.hidden = true
  tools.innerHTML = '<button type="button" data-action="replace">Replace</button><button type="button" data-action="edit">Crop &amp; edit</button>'
  document.body.append(tools)
  let picked = null
  const place = () => {
    if (!picked) return
    const box = picked.getBoundingClientRect()
    tools.style.left = `${Math.max(8, box.left + window.scrollX + 8)}px`
    tools.style.top = `${Math.max(8, box.top + window.scrollY + 8)}px`
  }
  const pick = image => {
    picked?.classList.remove("lp-image--picked")
    picked = image
    tools.hidden = !image
    if (image) { image.classList.add("lp-image--picked"); place() }
  }
  // The image under a click, though a theme may lay something over it (a
  // shade over a hero photo); not when the click is on editable text, or on
  // a link or button drawn over the image.
  const imageAt = event => {
    const target = event.target
    if (target.closest?.(".lp-editable")) return null
    const direct = target.closest?.("img[data-lp-image]")
    if (direct) return direct
    if (target.closest?.("a[href], button, input, select, textarea, label")) return null
    return document.elementsFromPoint(event.clientX, event.clientY).find(element => element.matches("img[data-lp-image]")) || null
  }
  window.addEventListener("scroll", place, { passive: true })
  window.addEventListener("resize", place)
  document.addEventListener("click", event => {
    if (event.target.closest(".lp-image-tools")) {
      const button = event.target.closest("button")
      if (button && picked) window.parent.postMessage({ type: "lp-image", action: button.dataset.action, field: picked.dataset.lpImage }, window.location.origin)
      return
    }
    const image = imageAt(event)
    if (image) {
      // An image inside a link doesn't follow it while it's being edited.
      event.preventDefault()
      event.stopPropagation()
    }
    pick(image)
  }, true)

  // Drawn again after a save: say it went through, briefly.
  if (new URLSearchParams(window.location.search).has("saved")) {
    save.disabled = true
    save.firstChild.textContent = "Saved ✓ "
    save.classList.add("lp-save--shown")
    setTimeout(() => save.classList.remove("lp-save--shown"), 2000)
  }

  window.addEventListener("message", event => {
    if (event.origin !== window.location.origin) return
    // Changes the editor holds that this page, drawn afresh, didn't see made.
    if (event.data?.type === "lp-inline-pending") {
      for (const field of event.data.fields || []) edited.add(field)
      return showEdited()
    }
    if (event.data?.type !== "lp-inline-save-failed") return
    save.disabled = false
    save.firstChild.textContent = "Not saved: see the Edit tab "
  })

  // A link around editable text doesn't follow while it's being edited.
  document.addEventListener("click", event => {
    if (event.target.closest(".lp-editable")) event.preventDefault()
  }, true)

  // ⌘S / Ctrl+S saves, from anywhere in the preview.
  document.addEventListener("keydown", event => {
    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "s") {
      event.preventDefault()
      window.parent.postMessage({ type: "lp-inline-save" }, window.location.origin)
    }
  })

  document.addEventListener("keydown", event => {
    const span = event.target.closest?.(".lp-editable")
    if (span && event.key === "Enter" && !span.dataset.lpField.endsWith("_multiline")) {
      event.preventDefault()
      span.blur()
    }
  })

  document.addEventListener("input", event => {
    const span = event.target.closest?.(".lp-editable")
    if (!span) return
    const value = span.textContent
    // The same field drawn twice (a title in the heading and the breadcrumbs) stays in step.
    for (const other of document.querySelectorAll(".lp-editable")) {
      if (other !== span && other.dataset.lpField === span.dataset.lpField) other.textContent = value
    }
    window.parent.postMessage({ type: "lp-inline-edit", field: span.dataset.lpField, value }, window.location.origin)
    edited.add(span.dataset.lpField)
    showEdited()
  })
})()
