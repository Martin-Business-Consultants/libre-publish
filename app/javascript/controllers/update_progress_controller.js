import { Controller } from "@hotwired/stimulus"

const POLL = 2000
const TICK = 250

// The update progress modal (layouts/shared/update_progress): open while a
// CMS update or a plugin or theme change runs, polling how far each is
// (UpdateProgress) until all are done. A bar eases towards what the poll
// says and creeps on a little past it, so a long step doesn't look stuck;
// while the CMS restarts the poll fails, and the modal waits it out. Done,
// a Settings page reloads to show what's new and any other closes; one that
// failed says why and waits to be closed. Esc doesn't close it while it runs.
export default class extends Controller {
  static targets = [ "heading", "items", "note", "actions", "spinner", "template" ]
  static values = { url: String, running: Boolean }

  connect() {
    this.watching = new Map()
    if (this.runningValue) this.start()
  }

  disconnect() {
    this.#stop()
  }

  start() {
    if (!this.element.open) this.element.showModal()
    this.finished = false
    this.poll()
    this.ticker = setInterval(() => this.#tick(), TICK)
  }

  async poll() {
    const url = new URL(this.urlValue, window.location.href)
    url.searchParams.set("watching", [ ...this.watching.keys() ].join(","))
    try {
      const response = await fetch(url, { headers: { Accept: "application/json" }, cache: "no-store" })
      if (!response.ok) throw new Error(response.statusText)
      const { items } = await response.json()
      this.noteTarget.textContent = "The CMS restarts to load what’s new. This page carries on when it’s back."
      this.#show(items)
    } catch {
      this.noteTarget.textContent = "The CMS is restarting. Waiting for it to come back…"
    }
    if (!this.finished) this.timer = setTimeout(() => this.poll(), POLL)
  }

  cancel(event) {
    if (!this.finished) event.preventDefault()
  }

  close() {
    this.#stop()
    this.element.close()
  }

  #show(items) {
    if (!items.length && !this.watching.size) return this.close()

    for (const item of items) {
      const entry = this.watching.get(item.id) || this.#add(item)
      Object.assign(entry, { item, target: item.percent })
      entry.title.textContent = item.title
      entry.step.textContent = item.message || item.step
    }
    if ([ ...this.watching.values() ].some(({ item }) => item.status === "running")) return

    this.finished = true
    const failed = [ ...this.watching.values() ].some(({ item }) => item.status === "failed")
    this.element.classList.add("update-progress--finished")
    this.element.classList.toggle("update-progress--failed", failed)
    this.headingTarget.textContent = failed ? "The update didn’t finish" : "Done"
    for (const entry of this.watching.values()) entry.shown = 100
    this.#tick()
    if (failed) {
      this.noteTarget.textContent = "Nothing else changed. Settings › Updates and Plugins have the details."
      this.actionsTarget.hidden = false
    } else if (window.location.pathname.includes("/settings")) {
      this.noteTarget.textContent = "Reloading…"
      setTimeout(() => window.location.reload(), 1200)
    } else {
      setTimeout(() => this.close(), 1200)
    }
  }

  #add(item) {
    const row = this.templateTarget.content.firstElementChild.cloneNode(true)
    this.itemsTarget.append(row)
    const field = name => row.querySelector(`[data-field=${name}]`)
    const entry = { item, shown: 0, target: item.percent, title: field("title"), step: field("step"),
                    percent: field("percent"), fill: field("fill"), bar: row.querySelector("[role=progressbar]") }
    this.watching.set(item.id, entry)
    return entry
  }

  // Each bar a step towards where it should be: the poll's percent, or a
  // little past it while it runs, short of 100 until it's done.
  #tick() {
    for (const entry of this.watching.values()) {
      const running = entry.item.status === "running"
      const goal = running ? Math.min(entry.target + 12, 97) : 100
      const speed = entry.shown < entry.target || !running ? 0.25 : 0.01
      entry.shown = Math.min(goal, entry.shown + Math.max((goal - entry.shown) * speed, 0))
      const percent = Math.floor(entry.shown)
      entry.fill.style.inlineSize = `${percent}%`
      entry.percent.textContent = `${percent}%`
      entry.bar.setAttribute("aria-valuenow", percent)
    }
  }

  #stop() {
    clearTimeout(this.timer)
    clearInterval(this.ticker)
  }
}
