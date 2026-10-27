// The counter window in Mobile Safari on an iPhone simulator through Appium (C213); .github/workflows/ios-sim.yml runs it.
// It taps the Name field, types on the soft keyboard, holds on the text and reads what the program printed ("name TEXT"),
// printing a line per check and saving a screenshot per step in /tmp/shots. It prints and carries on when a step fails, so
// one run says what each step did; the exit status is the number of failed checks.
import { remote } from 'webdriverio'

const url = 'http://localhost:8765/tests/wasm/browser/ui_counter.html?module=/tests/wasm/browser/ui_counter.wasm&events=1'
let failures = 0
const check = (ok, what, detail = '') => { if (!ok) failures++; console.log(`${ok ? 'ok  ' : 'FAIL'} ${what}${detail ? ` -- ${detail}` : ''}`) }
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

const browser = await remote({
  hostname: '127.0.0.1', port: 4723, logLevel: 'error',
  capabilities: {
    platformName: 'iOS', browserName: 'Safari',
    'appium:automationName': 'XCUITest', 'appium:udid': process.env.UDID, 'appium:platformVersion': process.env.IOS_VERSION,
    'appium:deviceName': 'iPhone', 'appium:connectHardwareKeyboard': false, 'appium:newCommandTimeout': 300,
    'appium:safariAllowPopups': true, 'appium:showXcodeLog': true, 'appium:wdaLaunchTimeout': 240000,
  },
})
let step = 0
const shot = async (name) => { try { await browser.saveScreenshot(`/tmp/shots/${String(++step).padStart(2, '0')}-${name}.png`) } catch (error) { console.log(`no screenshot ${name}: ${error.message}`) } }
const stdout = () => browser.execute(() => window.neperResult?.stdout ?? '')
const until = async (test, ms = 20000) => { const end = Date.now() + ms; while (Date.now() < end) { if (await test()) return true; await sleep(250) } return false }
const touch = (actions) => browser.performActions([{ type: 'pointer', id: 'finger', parameters: { pointerType: 'touch' }, actions }])
const web = async () => {
  const ids = (await browser.getContexts()).map((c) => c.id ?? c)
  await browser.switchContext(ids.find((id) => String(id).startsWith('WEBVIEW')))
}

try {
  await browser.url(url)
  check(await until(async () => /layout 4 /.test(await stdout())), 'the window runs and prints its layout')
  console.log('isolated:', await browser.execute(() => crossOriginIsolated), 'secure:', await browser.execute(() => isSecureContext), 'ua:', await browser.execute(() => navigator.userAgent))
  await shot('loaded')
  const layout = /layout 4 (\d+) (\d+) (\d+) (\d+)/.exec(await stdout())
  const field = await browser.execute((l) => {
    const r = document.getElementById('screen').getBoundingClientRect()
    const k = r.width / 480
    return { x: Math.round(r.left + (+l[1] + +l[3] / 2) * k), y: Math.round(r.top + (+l[2] + +l[4] / 2) * k) }
  }, layout)
  console.log('field at', JSON.stringify(field))

  await touch([{ type: 'pointerMove', duration: 0, x: field.x, y: field.y }, { type: 'pointerDown', button: 0 }, { type: 'pause', duration: 80 }, { type: 'pointerUp', button: 0 }])
  await sleep(1500)
  await shot('field-tapped')
  await browser.switchContext('NATIVE_APP')
  const keyboard = await browser.$('-ios predicate string:type == "XCUIElementTypeKeyboard"')
  check(await keyboard.isExisting(), 'the soft keyboard opens when the field is tapped')

  for (const letter of 'hello') {
    const key = await browser.$(`-ios predicate string:type == "XCUIElementTypeKey" AND name == "${letter}"`)
    if (!(await key.isExisting())) { check(false, `key ${letter} is on the keyboard`); continue }
    await key.click()
  }
  await shot('typed-hello')
  await web()
  check(await until(async () => /name hello\n/.test(await stdout()), 8000), 'typing hello reaches the program', (await stdout()).slice(-60).replace(/\n/g, '|'))

  await browser.switchContext('NATIVE_APP')
  const back = await browser.$('-ios predicate string:type == "XCUIElementTypeKey" AND name == "delete"')
  if (await back.isExisting()) { await back.click(); await back.click() }
  await web()
  check(await until(async () => /name hel\n/.test(await stdout()), 8000), 'two Backspaces leave hel', (await stdout()).slice(-60).replace(/\n/g, '|'))

  await touch([{ type: 'pointerMove', duration: 0, x: field.x - 20, y: field.y }, { type: 'pointerDown', button: 0 }, { type: 'pause', duration: 900 }, { type: 'pointerUp', button: 0 }])
  await sleep(1000)
  await shot('after-hold')
  const toolbar = await browser.execute(() => [...document.querySelectorAll('button')].map((b) => b.textContent))
  check(toolbar.includes('Copy') && toolbar.includes('Select all'), 'a hold on the text shows the Cut/Copy/Paste/Select all toolbar', JSON.stringify(toolbar))
  console.log('page events:', (await browser.execute(() => document.querySelector('pre:last-of-type')?.textContent ?? '')).replace(/\n/g, ' | '))
} catch (error) {
  failures++
  console.log('FAIL the run stopped:', error.message)
  await shot('error')
}
await browser.deleteSession().catch(() => {})
process.exit(failures)
