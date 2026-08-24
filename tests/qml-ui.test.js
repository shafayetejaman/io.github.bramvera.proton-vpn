const assert = require("node:assert/strict")
const crypto = require("node:crypto")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")

const root = path.resolve(__dirname, "..")
const panel = fs.readFileSync(path.join(root, "Panel.qml"), "utf8")
const service = fs.readFileSync(path.join(root, "Service.qml"), "utf8")
const icon = fs.readFileSync(path.join(root, "ProtonVpnIcon.qml"), "utf8")

test("background polling does not pulse the VPN indicator", () => {
  const indicatorBusy = service.match(/readonly property bool indicatorBusy:\s*([^\n]+)/)

  assert.ok(indicatorBusy, "Service.qml must expose the indicator-specific busy state")
  assert.match(indicatorBusy[1], /actionProcess\.running/)
  assert.doesNotMatch(
    indicatorBusy[1],
    /whichProcess|statusProcess|configActionProcess|dnsCompatibilityBusy/,
    "passive detection, polling, configuration, and DNS work must not animate the connection indicator"
  )

  const iconBindings = [...panel.matchAll(/busy:\s*vpn\.indicatorBusy/g)]
  assert.equal(iconBindings.length, 2, "both VPN indicators must use the stable indicator busy state")
})

test("interactive sign-in suspends automatic polling until manual refresh", () => {
  const automaticRefresh = service.match(/function automaticRefresh\(\) \{([\s\S]*?)\n  \}/)
  const signInExit = service.match(/if \(mode === "signin"\) \{([\s\S]*?)\n      \}/)
  const signIn = service.slice(service.indexOf("function signIn(username)"), service.indexOf("function refreshStatus()"))

  assert.ok(automaticRefresh, "Service.qml must separate automatic polling from explicit refreshes")
  assert.match(service, /readonly property bool signInPending:\s*_onboardingMode === "signin"/)
  assert.match(automaticRefresh[1], /root\.signInPending/)
  assert.match(automaticRefresh[1], /return false/)
  assert.match(service, /onTriggered: root\.automaticRefresh\(\)/)

  const panelOpen = panel.match(/onOpenedChanged: if \(opened\) \{([\s\S]*?)\n  \}/)
  assert.ok(panelOpen, "Panel.qml must define its open-time refresh behavior")
  assert.match(panelOpen[1], /vpn\.automaticRefresh\(\)/)
  assert.doesNotMatch(panelOpen[1], /vpn\.refresh\(\)/)

  const refreshLocations = service.match(/function refreshLocations\(\) \{([\s\S]*?)\n  \}/)
  assert.ok(refreshLocations, "Service.qml must define location refresh behavior")
  assert.match(refreshLocations[1], /root\.signInPending/)

  assert.match(signIn, /onboardingPollTimer\.stop\(\)/)
  assert.ok(
    signIn.indexOf('_onboardingMode = "signin"') < signIn.indexOf("onboardingProcess.running = true"),
    "sign-in mode must block polling before the terminal launcher starts"
  )

  assert.ok(signInExit, "terminal launch completion must handle interactive sign-in separately")
  assert.match(signInExit[1], /2FA/)
  assert.match(signInExit[1], /return/)
  assert.doesNotMatch(signInExit[1], /beginOnboardingPolling|refresh/)

  assert.match(
    panel,
    /text: vpn\.refreshing \? "Checking…" : "Refresh sign-in status"[\s\S]*?onClicked: vpn\.refreshStatus\(\)/,
    "the user must retain an explicit post-2FA status check"
  )
})

test("uses the official gradient and the white Simple Icons silhouette", () => {
  const asset = fs.readFileSync(path.join(root, "assets", "VPN-logomark-noborder.svg"))
  const disconnectedAsset = fs.readFileSync(path.join(root, "assets", "proton-vpn-simple-white.svg"), "utf8")

  assert.equal(
    crypto.createHash("sha256").update(asset).digest("hex"),
    "1c71b5712fe9beb1605871431d5d967d75aac3e300cd7664ee97c3f4e7170277"
  )
  assert.match(icon, /\? "assets\/VPN-logomark-noborder\.svg"/)
  assert.match(icon, /: "assets\/proton-vpn-simple-white\.svg"/)
  assert.match(icon, /opacity: root\.busy \? 0\.68 : 1\.0/)
  assert.match(icon, /visible: root\.warning/)
  assert.doesNotMatch(icon, /PathSvg|Simple Icons/)
  assert.match(disconnectedAsset, /fill="#FFFFFF"/)
  assert.doesNotMatch(disconnectedAsset, /#000000/)
})
