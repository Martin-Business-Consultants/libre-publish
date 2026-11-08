import { Controller } from "@hotwired/stimulus"

// rune-local-time: keeps "5 minutes ago" (or, short, "5m ago") current while the page stays
// open. Rendered by the time_ago helper.
export default class extends Controller {
  static values = { datetime: String, short: Boolean }

  connect() {
    this.update()
    this.timer = setInterval(() => this.update(), 30_000)
  }

  disconnect() { clearInterval(this.timer) }

  update() {
    const seconds = Math.round((Date.now() - new Date(this.datetimeValue)) / 1000)
    this.element.textContent = this.describe(seconds)
  }

  describe(seconds) {
    if (this.shortValue) return this.describeShort(seconds)
    const future = seconds < 0
    const s = Math.abs(seconds)
    const [ amount, unit ] = s < 45 ? [ null, "just now" ]
      : s < 90 ? [ 1, "minute" ] : s < 3600 ? [ Math.round(s / 60), "minute" ]
      : s < 5400 ? [ 1, "hour" ] : s < 86400 ? [ Math.round(s / 3600), "hour" ]
      : s < 172800 ? [ 1, "day" ] : [ Math.round(s / 86400), "day" ]
    if (amount === null) return unit
    const phrase = `${amount} ${unit}${amount === 1 ? "" : "s"}`
    return future ? `in ${phrase}` : `${phrase} ago`
  }

  describeShort(seconds) {
    const s = Math.max(seconds, 0)
    if (s < 60) return "now"
    if (s < 3600) return `${Math.floor(s / 60)}m ago`
    if (s < 86400) return `${Math.floor(s / 3600)}h ago`
    return `${Math.floor(s / 86400)}d ago`
  }
}
