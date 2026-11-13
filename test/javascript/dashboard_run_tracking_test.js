const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

const partial = fs.readFileSync(path.join(__dirname, "../../app/views/r3x/dashboard/shared/_run_tracking.html.erb"), "utf8")
const script = partial.match(/<script>\s*([\s\S]*?)\s*<\/script>/)[1]

function dashboard(tracking = true) {
  const listeners = {}
  const timers = new Map()
  const requests = []
  const destinations = []
  const message = { textContent: "Updates automatically." }
  const button = { innerHTML: "Run now", disabled: false, dataset: {} }
  const form = { dataset: {}, querySelector: () => button }
  const tracker = { dataset: { r3xRunTrackingUrl: "/request.json", r3xRunStatus: "queued" }, querySelector: () => message }
  let nextTimer = 0
  let reloads = 0
  const document = {
    hidden: false,
    querySelector: () => tracking ? tracker : null,
    querySelectorAll: () => [form],
    addEventListener: (event, handler) => { listeners[event] = handler }
  }

  vm.runInNewContext(script, {
    document,
    AbortController,
    setTimeout(callback, delay) { const id = ++nextTimer; timers.set(id, { callback, delay }); return id },
    clearTimeout(id) { timers.delete(id) },
    fetch(url, options) {
      let resolve, reject
      const promise = new Promise((yes, no) => { resolve = yes; reject = no })
      options.signal.addEventListener("abort", () => reject(new Error("aborted")), { once: true })
      requests.push({ url, resolve, reject })
      return promise
    },
    window: {
      addEventListener: (event, handler) => { listeners[event] = handler },
      location: { replace: (url) => destinations.push(url), reload: () => { reloads++ } }
    }
  })

  return {
    document, button, message, requests, timers, destinations,
    get reloads() { return reloads },
    submit() {
      let prevented = false
      listeners.submit({ target: { closest: () => form }, preventDefault: () => { prevented = true } })
      return prevented
    },
    restore() { listeners.pageshow() },
    tick() {
      const entry = timers.entries().next().value
      assert.ok(entry, "a status refresh or request timeout is scheduled")
      const [id, timer] = entry
      timers.delete(id)
      return timer.callback()
    },
    respond(index, state) { requests[index].resolve({ ok: true, json: async () => state }) }
  }
}

test("Run now blocks a duplicate submit and restores the button when navigating back", () => {
  const app = dashboard(false)
  assert.equal(app.submit(), false)
  assert.equal(app.button.disabled, true)
  assert.equal(app.button.textContent, "Starting…")
  assert.equal(app.submit(), true)
  app.restore()
  assert.equal(app.button.disabled, false)
  assert.equal(app.button.innerHTML, "Run now")
  assert.equal(app.submit(), false)
})

test("the waiting screen follows its exact run and replaces the temporary history entry", async () => {
  const app = dashboard()
  const pending = app.tick()
  assert.equal(app.requests[0].url, "/request.json")
  app.respond(0, { status: "running", run_url: "/workflow-runs/42" })
  await pending
  assert.deepEqual(app.destinations, ["/workflow-runs/42"])
  assert.equal(app.timers.size, 0)
})

test("unchanged waiting status keeps polling without overlapping requests", async () => {
  const app = dashboard()
  const pending = app.tick()
  assert.equal(app.requests.length, 1)
  assert.equal(app.timers.size, 1, "only the in-flight request timeout remains")
  app.respond(0, { status: "queued" })
  await pending
  assert.equal(app.timers.size, 1)
  assert.equal([...app.timers.values()][0].delay, 3000)
})

test("admission errors and run status changes reload the server-rendered result", async () => {
  for (const status of ["failed", "blocked", "running", "sleeping", "finished"]) {
    const app = dashboard()
    const pending = app.tick()
    app.respond(0, { status })
    await pending
    assert.equal(app.reloads, 1)
    assert.equal(app.timers.size, 0)
  }
})

test("a hidden tab waits without fetching", async () => {
  const app = dashboard()
  app.document.hidden = true
  await app.tick()
  assert.equal(app.requests.length, 0)
  assert.equal(app.timers.size, 1)
})

test("network errors remain visible and recover on the next status check", async () => {
  const app = dashboard()
  const pending = app.tick()
  app.requests[0].reject(new Error("offline"))
  await pending
  assert.match(app.message.textContent, /Could not update status/)
  const retry = app.tick()
  app.respond(1, { status: "queued" })
  await retry
  assert.equal(app.message.textContent, "Updates automatically.")
})

test("a stalled status check times out and retries", async () => {
  const app = dashboard()
  const pending = app.tick()
  app.tick()
  await pending
  assert.match(app.message.textContent, /Could not update status/)
  assert.equal(app.timers.size, 1)
})

test("pages without a live run or waiting request do not poll", () => {
  const app = dashboard(false)
  assert.equal(app.timers.size, 0)
})
