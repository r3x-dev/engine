// Run with: node --test test/javascript/dashboard_polling_test.js
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

const layout = fs.readFileSync(path.join(__dirname, "../../app/views/layouts/r3x/dashboard.html.erb"), "utf8")
const script = layout.match(/<script>\s*([\s\S]*?)\s*<\/script>/)[1]

function deferred() {
  let resolve, reject
  const promise = new Promise((onResolve, onReject) => { resolve = onResolve; reject = onReject })
  return { promise, resolve, reject }
}

function dashboard(status = "sleeping", refreshable = true) {
  const timers = new Map()
  const requests = []
  let nextTimer = 0
  let listener
  let selected = "30s"
  let reloads = 0
  let currentPanel = makePanel(status, refreshable)

  function makePanel(status, refreshable) {
    const elements = { select: {}, indicator: { dataset: {} }, status: {}, lastUpdated: {} }
    return {
      dataset: { r3xLogRefresh: String(refreshable), r3xRunStatus: status, r3xLogRefreshUrl: "/logs" },
      elements,
      querySelector(selector) {
        if (selector.includes("refresh-select")) return refreshable ? elements.select : null
        if (selector.includes("live-indicator")) return elements.indicator
        if (selector.includes("refresh-status")) return elements.status
        if (selector.includes("last-updated")) return elements.lastUpdated
        return null
      },
      set outerHTML(html) {
        const next = JSON.parse(html)
        currentPanel = makePanel(next.status, next.refreshable)
      }
    }
  }

  const document = {
    hidden: false,
    getElementById: () => currentPanel,
    addEventListener: (_, callback) => { listener = callback }
  }
  const localStorage = {
    getItem: () => selected,
    setItem: (_, value) => { selected = value }
  }
  vm.runInNewContext(script, {
    document,
    localStorage,
    AbortController,
    setTimeout(callback, delay) { const id = ++nextTimer; timers.set(id, { callback, delay }); return id },
    clearTimeout(id) { timers.delete(id) },
    fetch(_, options) {
      const request = deferred()
      request.signal = options.signal
      options.signal?.addEventListener("abort", () => request.reject(new Error("aborted")), { once: true })
      requests.push(request)
      return request.promise
    },
    window: { location: { reload() { reloads++ } } }
  })

  return {
    document,
    requests,
    timers,
    get panel() { return currentPanel },
    get reloads() { return reloads },
    change(value) { listener({ target: { closest: () => ({ value }) } }) },
    tick() {
      const [id, timer] = timers.entries().next().value
      timers.delete(id)
      return timer.callback()
    },
    respond(index, status = "sleeping", refreshable = true) {
      requests[index].resolve({ ok: true, text: async () => JSON.stringify({ status, refreshable }) })
    }
  }
}

for (const status of ["sleeping", "scheduled", "blocked"]) {
  test(`${status} schedules and continues polling`, async () => {
    const app = dashboard(status)
    assert.equal(app.timers.size, 1)
    const pending = app.tick()
    app.respond(0, status)
    await pending
    assert.equal(app.requests.length, 1)
    assert.equal(app.timers.size, 1)
  })
}

for (const status of ["finished", "failed"]) {
  test(`${status} does not start polling`, () => {
    const app = dashboard(status, false)
    assert.equal(app.timers.size, 0)
    assert.equal(app.requests.length, 0)
  })
}

test("a hidden page waits without making a request", async () => {
  const app = dashboard()
  app.document.hidden = true
  await app.tick()
  assert.equal(app.requests.length, 0)
  assert.equal(app.timers.size, 1)
})

test("interval changes while a request is pending do not start another request", async () => {
  const app = dashboard()
  const pending = app.tick()
  app.change("5s")
  app.change("1m")
  assert.equal(app.requests.length, 1)

  app.respond(0)
  await pending
  assert.equal(app.timers.size, 1)
  assert.equal([...app.timers.values()][0].delay, 60000)
})

test("turning polling off lets the pending request finish without restarting", async () => {
  const app = dashboard()
  const pending = app.tick()
  app.change("off")
  app.respond(0)
  await pending
  assert.equal(app.requests.length, 1)
  assert.equal(app.timers.size, 0)
  assert.equal(app.panel.elements.status.textContent, "Paused")
})

test("turning polling back on while a request is pending resumes after it finishes", async () => {
  const app = dashboard()
  const pending = app.tick()
  app.change("off")
  app.change("5s")
  assert.equal(app.requests.length, 1)
  app.respond(0)
  await pending
  assert.equal(app.timers.size, 1)
  assert.equal([...app.timers.values()][0].delay, 5000)
})

test("failed requests retry, but an error after switching off stays paused", async () => {
  const retry = dashboard()
  const pendingRetry = retry.tick()
  retry.requests[0].reject(new Error("network error"))
  await pendingRetry
  assert.equal(retry.panel.elements.status.textContent, "Retrying")
  assert.equal(retry.timers.size, 1)
  const retryRequest = retry.tick()
  assert.equal(retry.requests.length, 2)
  retry.respond(1)
  await retryRequest
  assert.equal(retry.timers.size, 1)

  const paused = dashboard()
  const pendingPause = paused.tick()
  paused.change("off")
  paused.requests[0].reject(new Error("network error"))
  await pendingPause
  assert.equal(paused.panel.elements.status.textContent, "Paused")
  assert.equal(paused.timers.size, 0)
})

test("a stalled request times out and polling resumes", async () => {
  const app = dashboard()
  const pending = app.tick()
  assert.equal(app.timers.size, 1, "the request has a timeout")
  app.tick()
  await pending
  assert.equal(app.panel.elements.status.textContent, "Retrying")
  assert.equal(app.timers.size, 1)
  const retry = app.tick()
  assert.equal(app.requests.length, 2)
  app.respond(1)
  await retry
  assert.equal(app.timers.size, 1)
})

test("a stalled request does not restart polling after switching off", async () => {
  const app = dashboard()
  const pending = app.tick()
  app.change("off")
  assert.equal(app.timers.size, 1, "the request has a timeout")
  app.tick()
  await pending
  assert.equal(app.panel.elements.status.textContent, "Paused")
  assert.equal(app.timers.size, 0)
})

test("the timeout also covers a stalled response body", async () => {
  const app = dashboard()
  const pending = app.tick()
  const body = deferred()
  app.requests[0].signal?.addEventListener("abort", () => body.reject(new Error("aborted")), { once: true })
  app.requests[0].resolve({ ok: true, text: () => body.promise })
  await Promise.resolve()
  app.tick()
  await pending
  assert.equal(app.panel.elements.status.textContent, "Retrying")
  assert.equal(app.timers.size, 1)
})

test("a status change reloads the page instead of starting another timer", async () => {
  const app = dashboard()
  const pending = app.tick()
  app.respond(0, "running")
  await pending
  assert.equal(app.reloads, 1)
  assert.equal(app.timers.size, 0)
})
