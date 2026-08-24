function clean(value) {
  return String(value === undefined || value === null ? "" : value).trim()
}

function parseStatus(raw) {
  var text = String(raw || "")
  var connected = /^Status:\s*Connected\s*$/mi.test(text)
  var disconnected = /^Status:\s*Disconnected\s*$/mi.test(text)

  if (!connected && !disconnected) {
    return {
      ok: false,
      connected: false,
      message: "Unrecognized Proton VPN status output"
    }
  }

  if (disconnected) {
    return {
      ok: true,
      connected: false,
      statusText: "Disconnected",
      server: "",
      location: "",
      load: "",
      protocol: ""
    }
  }

  var serverLine = text.match(/^Server:\s*(.+?)\s+in\s+(.+)\s*$/mi)
  var loadLine = text.match(/^Load:\s*(.+?)\s*$/mi)
  var protocolLine = text.match(/^Protocol:\s*(.+?)\s*$/mi)

  return {
    ok: true,
    connected: true,
    statusText: "Connected",
    server: serverLine ? clean(serverLine[1]) : "",
    location: serverLine ? clean(serverLine[2]) : "",
    load: loadLine ? clean(loadLine[1]) : "",
    protocol: protocolLine ? clean(protocolLine[1]) : ""
  }
}

function classifyFailure(raw) {
  var text = clean(raw).replace(/\s+/g, " ")
  var needsLogin = /authentication required|please sign in|not signed in/i.test(text)
  var message = needsLogin ? "Sign in from a terminal first" : (text || "Proton VPN command failed")
  if (message.length > 180) message = message.substring(0, 177) + "…"
  return { needsLogin: needsLogin, message: message }
}

function installCliPlan(omarchyCommand) {
  return {
    ok: true,
    error: "",
    command: [
      clean(omarchyCommand) || "omarchy",
      "install", "app", "Proton VPN CLI", "proton-vpn-cli"
    ]
  }
}

function signinPlan(omarchyCommand, cliCommand, username) {
  var account = clean(username)
  if (!account) return { ok: false, error: "Enter your Proton username", command: [] }
  return {
    ok: true,
    error: "",
    command: [
      clean(omarchyCommand) || "omarchy",
      "launch", "terminal", "--",
      clean(cliCommand) || "protonvpn", "signin", account
    ]
  }
}

function signoutPlan(cliCommand, connected) {
  if (connected) return { ok: false, error: "Disconnect before signing out", command: [] }
  return {
    ok: true,
    error: "",
    command: [clean(cliCommand) || "protonvpn", "signout"]
  }
}

function parseCountries(raw) {
  var lines = String(raw || "").split(/\r?\n/)
  var countries = []
  var seen = {}

  for (var i = 0; i < lines.length; i++) {
    var match = lines[i].match(/^\s*(.+?)\s{2,}([A-Z]{2})\s*$/)
    if (!match || match[1].trim().toLowerCase() === "country") continue
    var code = match[2].trim()
    if (seen[code]) continue
    countries.push({ name: match[1].trim(), code: code })
    seen[code] = true
  }

  return countries
}

function parseCities(raw) {
  var lines = String(raw || "").split(/\r?\n/)
  var cities = []
  var inTable = false

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (/^\s*City\s+Features\s*$/.test(line)) {
      inTable = true
      continue
    }
    if (!inTable || /^\s*-+\s+-+\s*$/.test(line)) continue
    if (/^\s*$/.test(line)) {
      if (cities.length > 0) break
      continue
    }

    var columns = line.trim().split(/\s{2,}/)
    var name = clean(columns.shift())
    if (!name) continue
    cities.push({ name: name, features: clean(columns.join(", ")) })
  }

  return cities
}

function connectPlan(cliCommand, mode, target, feature) {
  var executable = clean(cliCommand) || "protonvpn"
  var selectedMode = clean(mode).toLowerCase()
  var selectedTarget = clean(target)
  var selectedFeature = clean(feature).toLowerCase()
  var command = [executable, "connect"]

  if (selectedMode === "random") command.push("--random")
  else if (selectedMode === "country") {
    if (!selectedTarget) return { ok: false, error: "Enter a country code or name", command: [] }
    command.push("--country", selectedTarget)
  } else if (selectedMode === "city") {
    if (!selectedTarget) return { ok: false, error: "Enter a city", command: [] }
    command.push("--city", selectedTarget)
  } else if (selectedMode === "server") {
    if (!selectedTarget) return { ok: false, error: "Enter a server ID", command: [] }
    command.push(selectedTarget)
  } else if (selectedMode !== "fastest") {
    return { ok: false, error: "Unknown connection mode", command: [] }
  }

  if (selectedFeature === "p2p") command.push("--p2p")
  else if (selectedFeature === "secure core") command.push("--securecore")
  else if (selectedFeature === "tor") command.push("--tor")
  else if (selectedFeature !== "none") {
    return { ok: false, error: "Unknown server feature", command: [] }
  }

  return { ok: true, error: "", command: command }
}

function favoriteKey(favorite) {
  if (!favorite) return ""
  return [clean(favorite.mode).toLowerCase(), clean(favorite.target).toLowerCase(), clean(favorite.feature).toLowerCase()].join("\n")
}

function favoriteIndex(favorites, favorite) {
  var values = Array.isArray(favorites) ? favorites : []
  var key = favoriteKey(favorite)
  if (!key) return -1
  for (var i = 0; i < values.length; i++) {
    if (favoriteKey(values[i]) === key) return i
  }
  return -1
}

function addFavorite(favorites, favorite, limit) {
  var values = Array.isArray(favorites) ? favorites : []
  var maximum = Math.max(1, Number(limit) || 12)
  var next = []
  var key = favoriteKey(favorite)
  if (!key) return values.slice(0, maximum)
  next.push(favorite)
  for (var i = 0; i < values.length && next.length < maximum; i++) {
    if (favoriteKey(values[i]) !== key) next.push(values[i])
  }
  return next
}

function removeFavorite(favorites, index) {
  var values = Array.isArray(favorites) ? favorites : []
  var next = []
  for (var i = 0; i < values.length; i++) if (i !== index) next.push(values[i])
  return next
}

function parseConfig(raw) {
  var lines = String(raw || "").split(/\r?\n/)
  var values = {}
  for (var i = 0; i < lines.length; i++) {
    var match = lines[i].match(/^\s*([a-z][a-z0-9-]+)\s{2,}(.+?)\s*$/)
    if (!match || match[1] === "setting") continue
    values[match[1]] = clean(match[2])
  }
  return values
}

function configPlan(cliCommand, setting, value, dnsServers) {
  var executable = clean(cliCommand) || "protonvpn"
  var key = clean(setting).toLowerCase()
  var selected = clean(value).toLowerCase()
  var allowed = {
    "ipv6": ["off", "on"],
    "custom-dns": ["off", "on"],
    "netshield": ["off", "malware-only", "malware-ads-trackers"],
    "port-forwarding": ["off", "on"],
    "kill-switch": ["off", "standard"],
    "moderate-nat": ["off", "on"],
    "vpn-accelerator": ["off", "on"],
    "anonymous-crash-reports": ["off", "on"]
  }
  if (!allowed[key]) return { ok: false, error: "Unknown Proton VPN setting", command: [] }
  if (allowed[key].indexOf(selected) === -1) return { ok: false, error: "Unsupported value for " + key, command: [] }

  var command = [executable, "config", "set", key, selected]
  if (key === "custom-dns" && selected === "on") {
    var dns = clean(dnsServers)
    if (!dns) return { ok: false, error: "Enter at least one DNS server", command: [] }
    command.push("--dns", dns)
  }
  return { ok: true, error: "", command: command }
}

function parsePublicIp(raw) {
  var ip = clean(raw)
  var parts = ip.split(".")
  if (parts.length !== 4) return { ok: false, error: "Exit IP service returned an invalid IPv4 address" }
  for (var i = 0; i < parts.length; i++) {
    if (!/^\d{1,3}$/.test(parts[i])) return { ok: false, error: "Exit IP service returned an invalid IPv4 address" }
    var octet = Number(parts[i])
    if (octet < 0 || octet > 255 || String(octet) !== parts[i]) {
      return { ok: false, error: "Exit IP service returned an invalid IPv4 address" }
    }
  }
  return { ok: true, error: "", ip: ip }
}

function parsePublicIpResult(exitCode, stdout, stderr) {
  if (Number(exitCode) !== 0) {
    return { ok: false, error: classifyFailure(stderr || stdout).message }
  }
  return parsePublicIp(stdout)
}

function publicIpPlan(curlCommand, vpnInterface) {
  var executable = clean(curlCommand) || "curl"
  var interfaceName = clean(vpnInterface)
  if (!interfaceName) return { ok: false, error: "VPN interface is unavailable", command: [] }

  return {
    ok: true,
    error: "",
    command: [
      executable,
      "--proto", "=https",
      "--tlsv1.2",
      "--interface", "if!" + interfaceName,
      "--ipv4",
      "--fail-with-body",
      "--silent",
      "--show-error",
      "--connect-timeout", "5",
      "--max-time", "12",
      "https://api.ipify.org"
    ]
  }
}

function abuseIpReportPlan(omarchyCommand, ip) {
  var parsed = parsePublicIp(ip)
  if (!parsed.ok) return { ok: false, error: parsed.error, command: [] }
  return {
    ok: true,
    error: "",
    command: [
      clean(omarchyCommand) || "omarchy",
      "launch", "browser",
      "https://www.abuseipdb.com/check/" + parsed.ip
    ]
  }
}

function copyIpPlan(wlCopyCommand, ip) {
  var parsed = parsePublicIp(ip)
  if (!parsed.ok) return { ok: false, error: parsed.error, command: [] }
  return {
    ok: true,
    error: "",
    command: [
      clean(wlCopyCommand) || "wl-copy",
      "--type", "text/plain", parsed.ip
    ]
  }
}

function dnsCompatibilityProbe(rawDnsState, vpnInterface) {
  var interfaceName = clean(vpnInterface)
  if (!interfaceName) {
    return { ok: false, needed: false, error: "VPN interface is unavailable" }
  }

  var dnsState = String(rawDnsState || "")
  var usesInternalDns = /(^|\s)(10\.2\.0\.1|2a07:b944::2:1)(\s|$)/i.test(dnsState)
  return {
    ok: true,
    needed: usesInternalDns,
    error: ""
  }
}

function dnsCompatibilityApplyPlan(nmcliCommand, vpnInterface) {
  var interfaceName = clean(vpnInterface)
  if (!interfaceName) {
    return { ok: false, error: "VPN interface is unavailable", command: [] }
  }

  return {
    ok: true,
    error: "",
    command: [
      clean(nmcliCommand) || "nmcli",
      "device", "modify", interfaceName,
      "connection.dns-over-tls", "0"
    ]
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    parseStatus: parseStatus,
    classifyFailure: classifyFailure,
    installCliPlan: installCliPlan,
    signinPlan: signinPlan,
    signoutPlan: signoutPlan,
    parseCountries: parseCountries,
    parseCities: parseCities,
    connectPlan: connectPlan,
    favoriteKey: favoriteKey,
    favoriteIndex: favoriteIndex,
    addFavorite: addFavorite,
    removeFavorite: removeFavorite,
    parseConfig: parseConfig,
    configPlan: configPlan,
    parsePublicIp: parsePublicIp,
    parsePublicIpResult: parsePublicIpResult,
    publicIpPlan: publicIpPlan,
    abuseIpReportPlan: abuseIpReportPlan,
    copyIpPlan: copyIpPlan,
    dnsCompatibilityProbe: dnsCompatibilityProbe,
    dnsCompatibilityApplyPlan: dnsCompatibilityApplyPlan
  }
}
