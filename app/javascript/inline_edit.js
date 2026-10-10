// Editing in place, inside the editor's preview (Website::InlineEdit): the
// server drew each editable value between invisible markers naming its
// field. This turns marked text into editable text, strips the markers from
// everywhere else (attributes, the <head>, scripts), and sends each edit to
// the editor (website_preview_controller), whose form it changes. Plain
// script, no dependencies: it runs inside the theme's page.
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
    .lp-editable:focus { outline: 2px solid rgb(37 99 235); background: rgb(37 99 235 / .06); }`
  document.head.append(style)

  // A link around editable text doesn't follow while it's being edited.
  document.addEventListener("click", event => {
    if (event.target.closest(".lp-editable")) event.preventDefault()
  }, true)

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
  })
})()
