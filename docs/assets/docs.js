// The documentation site's search (over search.json, which bin/docs writes)
// and the small-screen menu. No dependencies.
const input = document.getElementById("search")
const results = document.getElementById("results")
let index = null

async function load() {
  if (!index) index = await (await fetch("search.json")).json()
  return index
}

function snippet(text, term) {
  const at = text.toLowerCase().indexOf(term)
  if (at < 0) return ""
  const start = Math.max(0, at - 50)
  return (start > 0 ? "…" : "") + text.slice(start, at + term.length + 70) + "…"
}

function escape(text) {
  return text.replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c])
}

input?.addEventListener("input", async () => {
  const term = input.value.trim().toLowerCase()
  if (term.length < 2) { results.hidden = true; return }
  const pages = await load()
  const found = []
  for (const page of pages) {
    const heading = page.headings.find(h => h.toLowerCase().includes(term))
    const score = (page.title.toLowerCase().includes(term) ? 3 : 0) + (heading ? 2 : 0) + (page.text.toLowerCase().includes(term) ? 1 : 0)
    if (score) found.push({ page, heading, score })
  }
  found.sort((a, b) => b.score - a.score)
  results.innerHTML = found.slice(0, 8).map(({ page, heading }) => {
    const anchor = heading ? "#" + heading.toLowerCase().replace(/[^\w\s-]/g, "").trim().replace(/\s+/g, "-") : ""
    const label = heading ? `${escape(page.title)} › ${escape(heading)}` : escape(page.title)
    return `<li><a href="${page.url}${anchor}">${label}<small>${escape(snippet(page.text, term))}</small></a></li>`
  }).join("") || `<li><a>No matches</a></li>`
  results.hidden = false
})

input?.addEventListener("keydown", event => { if (event.key === "Escape") { input.value = ""; results.hidden = true } })
document.addEventListener("click", event => { if (!event.target.closest(".search")) results.hidden = true })
document.addEventListener("keydown", event => {
  if (event.key === "/" && document.activeElement !== input) { event.preventDefault(); input.focus() }
})

const menu = document.querySelector(".menu")
menu?.addEventListener("click", () => {
  const nav = document.getElementById("nav")
  nav.classList.toggle("open")
  menu.setAttribute("aria-expanded", nav.classList.contains("open"))
})
