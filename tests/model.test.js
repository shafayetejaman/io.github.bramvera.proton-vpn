const assert = require("node:assert/strict")
const test = require("node:test")
const model = require("../Model.js")

test("parses a connected status", () => {
  const result = model.parseStatus(`Status: Connected
Server: NL#12 in Amsterdam, Netherlands
Load: 42%
Protocol: WireGuard`)

  assert.deepEqual(result, {
    ok: true,
    connected: true,
    statusText: "Connected",
    server: "NL#12",
    location: "Amsterdam, Netherlands",
    load: "42%",
    protocol: "WireGuard"
  })
})

test("parses a disconnected status", () => {
  assert.deepEqual(model.parseStatus("Status: Disconnected\n"), {
    ok: true,
    connected: false,
    statusText: "Disconnected",
    server: "",
    location: "",
    load: "",
    protocol: ""
  })
})

test("classifies authentication failures", () => {
  assert.deepEqual(model.classifyFailure("Authentication required. Please sign in."), {
    needsLogin: true,
    message: "Sign in from a terminal first"
  })
})

test("builds the supported Omarchy CLI installer command", () => {
  assert.deepEqual(model.installCliPlan("omarchy"), {
    ok: true,
    error: "",
    command: [
      "omarchy", "install", "app",
      "Proton VPN CLI", "proton-vpn-cli"
    ]
  })
})

test("opens interactive Proton sign-in in an Omarchy terminal", () => {
  assert.deepEqual(model.signinPlan("omarchy", "protonvpn", "user@proton.me"), {
    ok: true,
    error: "",
    command: [
      "omarchy", "launch", "terminal", "--",
      "protonvpn", "signin", "user@proton.me"
    ]
  })

  assert.equal(model.signinPlan("omarchy", "protonvpn", "").error, "Enter your Proton username")
})

test("builds sign-out only after the VPN is disconnected", () => {
  assert.deepEqual(model.signoutPlan("protonvpn", false), {
    ok: true,
    error: "",
    command: ["protonvpn", "signout"]
  })
  assert.deepEqual(model.signoutPlan("protonvpn", true), {
    ok: false,
    error: "Disconnect before signing out",
    command: []
  })
})

test("parses countries while ignoring refresh chatter and table headers", () => {
  const result = model.parseCountries(`Server list is outdated, updating... This may take a moment.
Country                           Code
--------------------------------  ------
Indonesia                         ID
United Kingdom                    UK
United States                     US`)

  assert.deepEqual(result, [
    { name: "Indonesia", code: "ID" },
    { name: "United Kingdom", code: "UK" },
    { name: "United States", code: "US" }
  ])
})

test("parses city names and their optional features", () => {
  const result = model.parseCities(`Server list is outdated, updating... This may take a moment.

Cities in Indonesia:
City      Features
--------  ----------
Jakarta   P2P
Surabaya
`)

  assert.deepEqual(result, [
    { name: "Jakarta", features: "P2P" },
    { name: "Surabaya", features: "" }
  ])
})

test("builds argument arrays without shell interpolation", () => {
  assert.deepEqual(
    model.connectPlan("protonvpn", "country", "United States; notify-send nope", "p2p"),
    {
      ok: true,
      error: "",
      command: ["protonvpn", "connect", "--country", "United States; notify-send nope", "--p2p"]
    }
  )
})

test("supports every official quick-connect selector", () => {
  assert.deepEqual(model.connectPlan("protonvpn", "fastest", "", "none").command, ["protonvpn", "connect"])
  assert.deepEqual(model.connectPlan("protonvpn", "random", "", "none").command, ["protonvpn", "connect", "--random"])
  assert.deepEqual(model.connectPlan("protonvpn", "city", "New York", "none").command, ["protonvpn", "connect", "--city", "New York"])
  assert.deepEqual(model.connectPlan("protonvpn", "server", "IT#23", "secure core").command, ["protonvpn", "connect", "IT#23", "--securecore"])
})

test("requires a target for scoped selectors", () => {
  const result = model.connectPlan("protonvpn", "country", "", "none")
  assert.equal(result.ok, false)
  assert.equal(result.error, "Enter a country code or name")
  assert.deepEqual(result.command, [])
})

test("favorites are unique, newest first, and removable", () => {
  const jakarta = { mode: "City", target: "Jakarta", feature: "P2P", label: "Jakarta, Indonesia" }
  const fastest = { mode: "Fastest", target: "", feature: "None", label: "Fastest server" }

  let favorites = model.addFavorite([], jakarta, 12)
  favorites = model.addFavorite(favorites, fastest, 12)
  favorites = model.addFavorite(favorites, jakarta, 12)

  assert.deepEqual(favorites, [jakarta, fastest])
  assert.equal(model.favoriteIndex(favorites, jakarta), 0)
  assert.deepEqual(model.removeFavorite(favorites, 0), [fastest])
})

test("favorites respect the configured cap", () => {
  const favorites = model.addFavorite([
    { mode: "Country", target: "US", feature: "None" },
    { mode: "Country", target: "GB", feature: "None" }
  ], { mode: "Country", target: "ID", feature: "None" }, 2)

  assert.deepEqual(favorites.map(item => item.target), ["ID", "US"])
})

test("parses the complete CLI configuration table", () => {
  const values = model.parseConfig(`Current configuration
Setting                  Value
-----------------------  --------------------
netshield                malware-ads-trackers
kill-switch              off
port-forwarding          on
custom-dns               off
vpn-accelerator          on
moderate-nat             off
ipv6                     off
anonymous-crash-reports  off`)

  assert.equal(values.netshield, "malware-ads-trackers")
  assert.equal(values["port-forwarding"], "on")
  assert.equal(values["moderate-nat"], "off")
  assert.equal(Object.keys(values).length, 8)
})

test("builds validated config commands as argument arrays", () => {
  assert.deepEqual(model.configPlan("protonvpn", "kill-switch", "standard", ""), {
    ok: true,
    error: "",
    command: ["protonvpn", "config", "set", "kill-switch", "standard"]
  })
  assert.deepEqual(model.configPlan("protonvpn", "custom-dns", "on", "1.1.1.1,8.8.8.8; nope"), {
    ok: true,
    error: "",
    command: ["protonvpn", "config", "set", "custom-dns", "on", "--dns", "1.1.1.1,8.8.8.8; nope"]
  })
})

test("rejects unsupported settings and custom DNS without servers", () => {
  assert.equal(model.configPlan("protonvpn", "nat-type", "2", "").ok, false)
  assert.equal(model.configPlan("protonvpn", "custom-dns", "on", "").error, "Enter at least one DNS server")
})

test("parses the public IPv4 address", () => {
  assert.deepEqual(model.parsePublicIp("203.0.113.42\n"), {
    ok: true,
    error: "",
    ip: "203.0.113.42"
  })
  assert.equal(model.parsePublicIp("not an ip").ok, false)
})

test("reports an exit-IP transport failure before parsing empty stdout", () => {
  assert.deepEqual(model.parsePublicIpResult(
    45,
    "",
    "curl: (45) Failed binding local connection end\n"
  ), {
    ok: false,
    error: "curl: (45) Failed binding local connection end"
  })
})

test("builds a validated AbuseIPDB browser report command", () => {
  assert.deepEqual(model.abuseIpReportPlan("omarchy", "146.70.14.45"), {
    ok: true,
    error: "",
    command: [
      "omarchy", "launch", "browser",
      "https://www.abuseipdb.com/check/146.70.14.45"
    ]
  })
  assert.equal(model.abuseIpReportPlan("omarchy", "not-an-ip").ok, false)
})

test("builds a validated exit-IP clipboard command", () => {
  assert.deepEqual(model.copyIpPlan("wl-copy", "146.70.14.45"), {
    ok: true,
    error: "",
    command: ["wl-copy", "--type", "text/plain", "146.70.14.45"]
  })
  assert.equal(model.copyIpPlan("wl-copy", "not-an-ip").ok, false)
})

test("pins exit-IP discovery to Proton", () => {
  assert.deepEqual(model.publicIpPlan("curl", "proton0"), {
    ok: true,
    error: "",
    command: [
      "curl",
      "--proto", "=https",
      "--tlsv1.2",
      "--interface", "if!proton0",
      "--ipv4",
      "--fail-with-body",
      "--silent",
      "--show-error",
      "--connect-timeout", "5",
      "--max-time", "12",
      "https://api.ipify.org"
    ]
  })
})

test("detects Proton DNS without building a mutating command", () => {
  assert.deepEqual(model.dnsCompatibilityProbe(
    "Link 48 (proton0): 10.2.0.1\n",
    "proton0"
  ), {
    ok: true,
    needed: true,
    error: ""
  })

  assert.deepEqual(model.dnsCompatibilityProbe(
    "Link 48 (proton0): 1.1.1.1\n",
    "proton0"
  ), {
    ok: true,
    needed: false,
    error: ""
  })
})

test("builds the Proton DNS exception only for explicit application", () => {
  assert.deepEqual(model.dnsCompatibilityApplyPlan("nmcli", "proton0"), {
    ok: true,
    error: "",
    command: [
      "nmcli", "device", "modify", "proton0",
      "connection.dns-over-tls", "0"
    ]
  })
})
