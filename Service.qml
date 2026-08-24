import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})
  property bool installed: false
  property bool connected: false
  property bool needsLogin: false
  property bool refreshing: false
  property string statusText: "Checking…"
  property string server: ""
  property string location: ""
  property string load: ""
  property string protocol: ""
  property string actionStatus: ""
  property string lastError: ""
  property var countries: []
  property var cities: []
  property string citiesCountryCode: ""
  property string locationError: ""
  property var configValues: ({})
  property bool configLoaded: false
  property string configError: ""
  property string exitIp: ""
  property string reportStatus: ""
  property string reportError: ""
  property bool dnsCompatibilityNeeded: false
  property string dnsCompatibilityStatus: ""
  property string dnsCompatibilityError: ""
  property string onboardingStatus: ""
  property string onboardingError: ""

  readonly property string cliCommand: String(setting("cliCommand", "protonvpn") || "protonvpn").trim()
  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 30, 5, 3600)
  readonly property bool busy: whichProcess.running || statusProcess.running || actionProcess.running || configActionProcess.running || dnsCompatibilityBusy || onboardingBusy
  readonly property bool indicatorBusy: actionProcess.running || onboardingBusy
  readonly property bool locationsBusy: countriesProcess.running || citiesProcess.running
  readonly property bool configBusy: configListProcess.running || configActionProcess.running
  readonly property bool reportBusy: reportStatusProcess.running || publicIpProcess.running || browserProcess.running
  readonly property bool exitIpBusy: publicIpProcess.running
  readonly property bool openingReport: _openReportAfterLookup && reportBusy
  readonly property bool dnsCompatibilityBusy: dnsProbeProcess.running || dnsApplyProcess.running
  readonly property bool onboardingBusy: onboardingProcess.running
  readonly property bool signInPending: _onboardingMode === "signin"

  property string _statusOutput: ""
  property string _statusError: ""
  property string _actionOutput: ""
  property string _actionError: ""
  property string _actionMode: ""
  property string _countriesOutput: ""
  property string _countriesError: ""
  property string _citiesOutput: ""
  property string _citiesError: ""
  property string _activeCitiesCountryCode: ""
  property string _pendingCitiesCountryCode: ""
  property string _configOutput: ""
  property string _configErrorOutput: ""
  property string _configActionOutput: ""
  property string _configActionError: ""
  property string _reportStatusOutput: ""
  property string _reportStatusErrorOutput: ""
  property string _publicIpOutput: ""
  property string _publicIpErrorOutput: ""
  property string _browserErrorOutput: ""
  property bool _reportTimedOut: false
  property bool _reportCancelled: false
  property bool _openReportAfterLookup: false
  property string _dnsProbeOutput: ""
  property string _dnsProbeErrorOutput: ""
  property string _dnsApplyErrorOutput: ""
  property bool _dnsCompatibilityTimedOut: false
  property string _onboardingErrorOutput: ""
  property string _onboardingMode: ""
  property int _onboardingPollCount: 0

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var value = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(value)) value = fallback
    return Math.max(min, Math.min(max, value))
  }

  function clearConnection() {
    connected = false
    server = ""
    location = ""
    load = ""
    protocol = ""
    clearReport()
    clearDnsCompatibility()
  }

  function clearReport() {
    delayedExitIp.stop()
    reportWatchdog.stop()
    _reportCancelled = true
    if (reportStatusProcess.running) reportStatusProcess.running = false
    if (publicIpProcess.running) publicIpProcess.running = false
    if (browserProcess.running) browserProcess.running = false
    exitIp = ""
    reportStatus = ""
    reportError = ""
    _reportTimedOut = false
    _openReportAfterLookup = false
  }

  function openIpReport() {
    if (!connected) {
      reportError = "Connect Proton VPN before checking its exit IP"
      return false
    }
    if (reportBusy) return false
    _reportStatusOutput = ""
    _reportStatusErrorOutput = ""
    _publicIpOutput = ""
    _publicIpErrorOutput = ""
    _browserErrorOutput = ""
    _reportTimedOut = false
    _reportCancelled = false
    _openReportAfterLookup = true
    reportStatus = ""
    reportError = ""
    reportStatusProcess.command = [cliCommand, "status"]
    reportStatusProcess.running = true
    reportWatchdog.restart()
    return true
  }

  function refreshExitIp() {
    if (!connected || reportBusy) return false
    exitIp = ""
    _publicIpOutput = ""
    _publicIpErrorOutput = ""
    _reportTimedOut = false
    _reportCancelled = false
    _openReportAfterLookup = false
    reportStatus = ""
    reportError = ""
    return startPublicIpCheck()
  }

  function startPublicIpCheck() {
    var plan = Model.publicIpPlan("curl", "proton0")
    if (!plan.ok) {
      reportWatchdog.stop()
      _openReportAfterLookup = false
      reportError = plan.error
      return false
    }
    publicIpProcess.command = plan.command
    publicIpProcess.running = true
    reportWatchdog.restart()
    return true
  }

  function openBrowserForExitIp() {
    var plan = Model.abuseIpReportPlan("omarchy", exitIp)
    if (!plan.ok) {
      reportWatchdog.stop()
      _openReportAfterLookup = false
      reportError = plan.error
      return false
    }
    _browserErrorOutput = ""
    browserProcess.command = plan.command
    browserProcess.running = true
    reportWatchdog.restart()
    return true
  }

  function clearDnsCompatibility() {
    delayedDnsCompatibility.stop()
    dnsCompatibilityWatchdog.stop()
    if (dnsProbeProcess.running) dnsProbeProcess.running = false
    if (dnsApplyProcess.running) dnsApplyProcess.running = false
    dnsCompatibilityNeeded = false
    dnsCompatibilityStatus = ""
    dnsCompatibilityError = ""
    _dnsCompatibilityTimedOut = false
  }

  function inspectProtonDnsCompatibility() {
    if (!connected || dnsCompatibilityBusy) return false
    _dnsProbeOutput = ""
    _dnsProbeErrorOutput = ""
    _dnsApplyErrorOutput = ""
    _dnsCompatibilityTimedOut = false
    dnsCompatibilityNeeded = false
    dnsCompatibilityStatus = ""
    dnsCompatibilityError = ""
    dnsProbeProcess.command = ["resolvectl", "dns", "proton0"]
    dnsProbeProcess.running = true
    dnsCompatibilityWatchdog.restart()
    return true
  }

  function allowProtonDnsCompatibility() {
    if (!connected || !dnsCompatibilityNeeded || dnsCompatibilityBusy) return false
    var plan = Model.dnsCompatibilityApplyPlan("nmcli", "proton0")
    if (!plan.ok) {
      dnsCompatibilityError = plan.error
      return false
    }
    _dnsApplyErrorOutput = ""
    _dnsCompatibilityTimedOut = false
    dnsCompatibilityStatus = "Allowing Proton DNS for this connection…"
    dnsCompatibilityError = ""
    dnsApplyProcess.command = plan.command
    dnsApplyProcess.running = true
    dnsCompatibilityWatchdog.restart()
    return true
  }

  function refresh() {
    if (installed) {
      refreshStatus()
      return
    }
    if (whichProcess.running) return
    refreshing = true
    whichProcess.command = ["which", cliCommand]
    whichProcess.running = true
  }

  function automaticRefresh() {
    if (root.signInPending) return false
    root.refresh()
    return true
  }

  function beginOnboardingPolling(mode) {
    _onboardingMode = mode
    _onboardingPollCount = 0
    onboardingPollTimer.restart()
  }

  function finishOnboardingPolling() {
    onboardingPollTimer.stop()
    _onboardingMode = ""
    _onboardingPollCount = 0
  }

  function installCli() {
    if (installed || onboardingBusy) return false
    var plan = Model.installCliPlan("omarchy")
    if (!plan.ok) {
      onboardingError = plan.error
      return false
    }
    _onboardingErrorOutput = ""
    onboardingError = ""
    onboardingStatus = "Opening the Omarchy installer…"
    lastError = ""
    onboardingProcess.command = plan.command
    onboardingProcess.running = true
    _onboardingMode = "install"
    return true
  }

  function signIn(username) {
    if (!installed || onboardingBusy) return false
    var plan = Model.signinPlan("omarchy", cliCommand, username)
    if (!plan.ok) {
      onboardingError = plan.error
      return false
    }
    _onboardingErrorOutput = ""
    onboardingError = ""
    onboardingStatus = "Complete password and 2FA in the terminal. Automatic polling is paused."
    lastError = ""
    onboardingPollTimer.stop()
    _onboardingPollCount = 0
    _onboardingMode = "signin"
    onboardingProcess.command = plan.command
    onboardingProcess.running = true
    return true
  }

  function refreshStatus() {
    if (!installed || statusProcess.running || actionProcess.running) return
    _statusOutput = ""
    _statusError = ""
    refreshing = true
    statusProcess.command = [cliCommand, "status"]
    statusProcess.running = true
    pollWatchdog.restart()
  }

  function refreshLocations() {
    if (!installed || root.signInPending || countriesProcess.running) return
    _countriesOutput = ""
    _countriesError = ""
    locationError = ""
    countriesProcess.command = [cliCommand, "countries", "list"]
    countriesProcess.running = true
    locationWatchdog.restart()
  }

  function loadCities(countryCode) {
    var code = String(countryCode || "").trim().toUpperCase()
    if (!installed || root.signInPending || code === "") return
    if (citiesProcess.running) {
      _pendingCitiesCountryCode = code
      return
    }
    if (citiesCountryCode === code && cities.length > 0) return
    _activeCitiesCountryCode = code
    _pendingCitiesCountryCode = ""
    _citiesOutput = ""
    _citiesError = ""
    locationError = ""
    cities = []
    citiesCountryCode = ""
    citiesProcess.command = [cliCommand, "cities", "list", code]
    citiesProcess.running = true
    locationWatchdog.restart()
  }

  function refreshConfig() {
    if (!installed || root.signInPending || configListProcess.running || configActionProcess.running) return
    _configOutput = ""
    _configErrorOutput = ""
    configError = ""
    configListProcess.command = [cliCommand, "config", "list"]
    configListProcess.running = true
    configWatchdog.restart()
  }

  function setConfig(settingName, value, dnsServers) {
    if (!installed || configActionProcess.running || actionProcess.running) return false
    var plan = Model.configPlan(cliCommand, settingName, value, dnsServers)
    if (!plan.ok) {
      configError = plan.error
      lastError = plan.error
      return false
    }
    _configActionOutput = ""
    _configActionError = ""
    configError = ""
    lastError = ""
    actionStatus = "Updating " + String(settingName || "setting") + "…"
    configActionProcess.command = plan.command
    configActionProcess.running = true
    configWatchdog.restart()
    return true
  }

  function connect(mode, target, feature) {
    if (!installed || actionProcess.running || configActionProcess.running) return false
    var plan = Model.connectPlan(cliCommand, mode, target, feature)
    if (!plan.ok) {
      lastError = plan.error
      return false
    }
    runAction(plan.command, "Connecting…")
    return true
  }

  function disconnect() {
    if (!installed || !connected || actionProcess.running) return
    runAction([cliCommand, "disconnect"], "Disconnecting…")
  }

  function signOut() {
    if (!installed || needsLogin || statusProcess.running || actionProcess.running || configListProcess.running || configActionProcess.running || onboardingBusy) return false
    var plan = Model.signoutPlan(cliCommand, connected)
    if (!plan.ok) {
      lastError = plan.error
      return false
    }
    runAction(plan.command, "Signing out…", "signout")
    return true
  }

  function toggle() {
    if (connected) disconnect()
    else connect("fastest", "", "none")
  }

  function runAction(command, label, mode) {
    _actionOutput = ""
    _actionError = ""
    _actionMode = String(mode || "")
    lastError = ""
    actionStatus = label
    actionProcess.command = command
    actionProcess.running = true
    actionWatchdog.restart()
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.automaticRefresh()
  }

  Timer {
    id: delayedRefresh
    interval: 700
    repeat: false
    onTriggered: root.refreshStatus()
  }

  Timer {
    id: onboardingPollTimer
    interval: 3000
    repeat: true
    onTriggered: {
      root._onboardingPollCount += 1
      if (root._onboardingPollCount >= 100) {
        root.finishOnboardingPolling()
        root.onboardingStatus = "Use Refresh after completing the terminal step."
      } else {
        root.automaticRefresh()
      }
    }
  }

  Timer {
    id: delayedDnsCompatibility
    interval: 1000
    repeat: false
    onTriggered: root.inspectProtonDnsCompatibility()
  }

  Timer {
    id: delayedExitIp
    interval: 2200
    repeat: false
    onTriggered: root.refreshExitIp()
  }

  Timer {
    id: dnsCompatibilityWatchdog
    interval: 10000
    repeat: false
    onTriggered: {
      root._dnsCompatibilityTimedOut = true
      if (dnsProbeProcess.running) dnsProbeProcess.running = false
      if (dnsApplyProcess.running) dnsApplyProcess.running = false
      root.dnsCompatibilityStatus = ""
      root.dnsCompatibilityError = "Proton DNS compatibility check timed out"
    }
  }

  Timer {
    id: pollWatchdog
    interval: 15000
    repeat: false
    onTriggered: {
      if (statusProcess.running) {
        statusProcess.running = false
        root.refreshing = false
        root.lastError = "Status check timed out"
      }
    }
  }

  Timer {
    id: actionWatchdog
    interval: 60000
    repeat: false
    onTriggered: {
      if (actionProcess.running) {
        actionProcess.running = false
        root.actionStatus = ""
        root.lastError = "Proton VPN command timed out"
      }
    }
  }

  Timer {
    id: locationWatchdog
    interval: 30000
    repeat: false
    onTriggered: {
      if (countriesProcess.running) countriesProcess.running = false
      if (citiesProcess.running) citiesProcess.running = false
      root.locationError = "Location list timed out"
    }
  }

  Timer {
    id: delayedConfigRefresh
    interval: 500
    repeat: false
    onTriggered: root.refreshConfig()
  }

  Timer {
    id: actionMessageTimer
    interval: 4500
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Timer {
    id: configWatchdog
    interval: 30000
    repeat: false
    onTriggered: {
      if (configListProcess.running) configListProcess.running = false
      if (configActionProcess.running) configActionProcess.running = false
      root.actionStatus = ""
      root.configError = "Proton VPN configuration command timed out"
      root.lastError = root.configError
    }
  }

  Timer {
    id: reportWatchdog
    interval: 15000
    repeat: false
    onTriggered: {
      root._reportTimedOut = true
      if (reportStatusProcess.running) reportStatusProcess.running = false
      if (publicIpProcess.running) publicIpProcess.running = false
      if (browserProcess.running) browserProcess.running = false
      root.reportError = root._openReportAfterLookup ? "Opening the IP report timed out" : "Exit IP lookup timed out"
      root._openReportAfterLookup = false
    }
  }

  Process {
    id: whichProcess
    running: false
    command: []
    onExited: function(exitCode) {
      root.installed = exitCode === 0
      if (root.installed) root.refreshStatus()
      else {
        root.refreshing = false
        root.clearConnection()
        root.needsLogin = false
        root.statusText = "CLI not installed"
      }
    }
  }

  Process {
    id: onboardingProcess
    running: false
    command: []
    stderr: StdioCollector {
      id: onboardingStderr
      waitForEnd: true
      onStreamFinished: root._onboardingErrorOutput = text
    }
    onExited: function(exitCode) {
      var stderr = String(onboardingStderr.text || root._onboardingErrorOutput || "")
      if (exitCode !== 0) {
        root.onboardingStatus = ""
        root.onboardingError = Model.classifyFailure(stderr).message
        root.finishOnboardingPolling()
        return
      }

      var mode = root._onboardingMode
      if (mode === "signin") {
        root.onboardingStatus = "Checking sign-in status…"
        root.refreshStatus()
        return
      }

      root.onboardingStatus = "Finish installation in the terminal; detection is automatic."
      root.beginOnboardingPolling(mode)
      root.automaticRefresh()
    }
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: statusStdout
      waitForEnd: true
      onStreamFinished: root._statusOutput = text
    }
    stderr: StdioCollector {
      id: statusStderr
      waitForEnd: true
      onStreamFinished: root._statusError = text
    }
    onExited: function(exitCode) {
      pollWatchdog.stop()
      root.refreshing = false
      var stdout = String(statusStdout.text || root._statusOutput || "")
      var stderr = String(statusStderr.text || root._statusError || "")
      if (exitCode === 0) {
        var parsed = Model.parseStatus(stdout)
        if (parsed.ok) {
          var connectionChanged = parsed.connected && (!root.connected || root.server !== parsed.server)
          var clearExitIp = !parsed.connected || connectionChanged
          root.connected = parsed.connected
          if (clearExitIp) {
            root.clearReport()
            root.clearDnsCompatibility()
          }
          root.needsLogin = false
          root.statusText = parsed.statusText
          root.server = parsed.server
          root.location = parsed.location
          root.load = parsed.load
          root.protocol = parsed.protocol
          root.lastError = ""
          if (root._onboardingMode !== "") {
            root.finishOnboardingPolling()
            root.onboardingStatus = "Proton VPN is ready."
            root.onboardingError = ""
          }
          if (connectionChanged) {
            delayedDnsCompatibility.restart()
            delayedExitIp.restart()
          }
        } else {
          root.clearConnection()
          root.statusText = "Status unavailable"
          root.lastError = parsed.message
        }
      } else {
        var failure = Model.classifyFailure(stderr || stdout)
        root.clearConnection()
        root.needsLogin = failure.needsLogin
        root.statusText = failure.needsLogin ? "Needs sign-in" : "Status unavailable"
        root.lastError = failure.message
        if (failure.needsLogin && root._onboardingMode === "install") {
          root.finishOnboardingPolling()
          root.onboardingStatus = "CLI installed. Sign in to continue."
          root.onboardingError = ""
        }
      }
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: actionStdout
      waitForEnd: true
      onStreamFinished: root._actionOutput = text
    }
    stderr: StdioCollector {
      id: actionStderr
      waitForEnd: true
      onStreamFinished: root._actionError = text
    }
    onExited: function(exitCode) {
      actionWatchdog.stop()
      var stdout = String(actionStdout.text || root._actionOutput || "")
      var stderr = String(actionStderr.text || root._actionError || "")
      var actionMode = root._actionMode
      root._actionMode = ""
      root.actionStatus = ""
      if (exitCode === 0) {
        root.lastError = ""
        if (actionMode === "signout") {
          root.finishOnboardingPolling()
          root.clearConnection()
          root.needsLogin = true
          root.statusText = "Needs sign-in"
          root.configValues = ({})
          root.configLoaded = false
          root.configError = ""
          root.onboardingStatus = "Signed out. Sign in with another account."
          root.onboardingError = ""
          return
        }
        delayedRefresh.restart()
      } else {
        var failure = Model.classifyFailure(stderr || stdout)
        root.needsLogin = failure.needsLogin
        root.lastError = failure.message
      }
    }
  }

  Process {
    id: countriesProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: countriesStdout
      waitForEnd: true
      onStreamFinished: root._countriesOutput = text
    }
    stderr: StdioCollector {
      id: countriesStderr
      waitForEnd: true
      onStreamFinished: root._countriesError = text
    }
    onExited: function(exitCode) {
      if (!citiesProcess.running) locationWatchdog.stop()
      var stdout = String(countriesStdout.text || root._countriesOutput || "")
      var stderr = String(countriesStderr.text || root._countriesError || "")
      if (exitCode === 0) {
        var parsed = Model.parseCountries(stdout)
        if (parsed.length > 0) {
          root.countries = parsed
          root.locationError = ""
        } else {
          root.locationError = "No countries returned by Proton VPN"
        }
      } else {
        root.locationError = Model.classifyFailure(stderr || stdout).message
      }
    }
  }

  Process {
    id: citiesProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: citiesStdout
      waitForEnd: true
      onStreamFinished: root._citiesOutput = text
    }
    stderr: StdioCollector {
      id: citiesStderr
      waitForEnd: true
      onStreamFinished: root._citiesError = text
    }
    onExited: function(exitCode) {
      locationWatchdog.stop()
      var completedCode = root._activeCitiesCountryCode
      var stdout = String(citiesStdout.text || root._citiesOutput || "")
      var stderr = String(citiesStderr.text || root._citiesError || "")
      if (root._pendingCitiesCountryCode !== "" && root._pendingCitiesCountryCode !== completedCode) {
        var pendingCode = root._pendingCitiesCountryCode
        root._pendingCitiesCountryCode = ""
        Qt.callLater(function() { root.loadCities(pendingCode) })
      } else if (exitCode === 0) {
        root.cities = Model.parseCities(stdout)
        root.citiesCountryCode = completedCode
        root.locationError = root.cities.length > 0 ? "" : "No cities available for this country"
      } else {
        root.locationError = Model.classifyFailure(stderr || stdout).message
      }
    }
  }

  Process {
    id: configListProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: configStdout
      waitForEnd: true
      onStreamFinished: root._configOutput = text
    }
    stderr: StdioCollector {
      id: configStderr
      waitForEnd: true
      onStreamFinished: root._configErrorOutput = text
    }
    onExited: function(exitCode) {
      configWatchdog.stop()
      var stdout = String(configStdout.text || root._configOutput || "")
      var stderr = String(configStderr.text || root._configErrorOutput || "")
      if (exitCode === 0) {
        var parsed = Model.parseConfig(stdout)
        root.configValues = parsed
        root.configLoaded = Object.keys(parsed).length > 0
        root.configError = root.configLoaded ? "" : "No Proton VPN settings returned"
      } else {
        root.configError = Model.classifyFailure(stderr || stdout).message
        root.lastError = root.configError
      }
    }
  }

  Process {
    id: configActionProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: configActionStdout
      waitForEnd: true
      onStreamFinished: root._configActionOutput = text
    }
    stderr: StdioCollector {
      id: configActionStderr
      waitForEnd: true
      onStreamFinished: root._configActionError = text
    }
    onExited: function(exitCode) {
      configWatchdog.stop()
      var stdout = String(configActionStdout.text || root._configActionOutput || "")
      var stderr = String(configActionStderr.text || root._configActionError || "")
      if (exitCode === 0) {
        root.configError = ""
        root.lastError = ""
        root.actionStatus = String(stdout || "Setting updated").replace(/\s+/g, " ").trim()
        actionMessageTimer.restart()
        delayedConfigRefresh.restart()
      } else {
        root.actionStatus = ""
        root.configError = Model.classifyFailure(stderr || stdout).message
        root.lastError = root.configError
      }
    }
  }

  Process {
    id: dnsProbeProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: dnsProbeStdout
      waitForEnd: true
      onStreamFinished: root._dnsProbeOutput = text
    }
    stderr: StdioCollector {
      id: dnsProbeStderr
      waitForEnd: true
      onStreamFinished: root._dnsProbeErrorOutput = text
    }
    onExited: function(exitCode) {
      if (root._dnsCompatibilityTimedOut) return
      var stdout = String(dnsProbeStdout.text || root._dnsProbeOutput || "")
      var stderr = String(dnsProbeStderr.text || root._dnsProbeErrorOutput || "")
      if (exitCode !== 0) {
        dnsCompatibilityWatchdog.stop()
        root.dnsCompatibilityError = "Could not inspect Proton DNS: " + Model.classifyFailure(stderr || stdout).message
        return
      }

      var result = Model.dnsCompatibilityProbe(stdout, "proton0")
      if (!result.ok) {
        dnsCompatibilityWatchdog.stop()
        root.dnsCompatibilityError = result.error
      } else {
        dnsCompatibilityWatchdog.stop()
        root.dnsCompatibilityNeeded = result.needed
        root.dnsCompatibilityError = ""
      }
    }
  }

  Process {
    id: dnsApplyProcess
    running: false
    command: []
    stderr: StdioCollector {
      id: dnsApplyStderr
      waitForEnd: true
      onStreamFinished: root._dnsApplyErrorOutput = text
    }
    onExited: function(exitCode) {
      dnsCompatibilityWatchdog.stop()
      if (root._dnsCompatibilityTimedOut) return
      var stderr = String(dnsApplyStderr.text || root._dnsApplyErrorOutput || "")
      if (exitCode === 0) {
        root.dnsCompatibilityNeeded = false
        root.dnsCompatibilityStatus = "Proton DNS is allowed for this connection."
        root.dnsCompatibilityError = ""
      } else {
        root.dnsCompatibilityStatus = ""
        root.dnsCompatibilityError = "Could not enable Proton DNS: " + Model.classifyFailure(stderr).message
      }
    }
  }

  Process {
    id: reportStatusProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: reportStatusStdout
      waitForEnd: true
      onStreamFinished: root._reportStatusOutput = text
    }
    stderr: StdioCollector {
      id: reportStatusStderr
      waitForEnd: true
      onStreamFinished: root._reportStatusErrorOutput = text
    }
    onExited: function(exitCode) {
      if (root._reportTimedOut || root._reportCancelled) return
      var stdout = String(reportStatusStdout.text || root._reportStatusOutput || "")
      var stderr = String(reportStatusStderr.text || root._reportStatusErrorOutput || "")
      if (exitCode !== 0) {
        reportWatchdog.stop()
        root._openReportAfterLookup = false
        root.reportError = Model.classifyFailure(stderr || stdout).message
        return
      }

      var parsed = Model.parseStatus(stdout)
      if (!parsed.ok) {
        reportWatchdog.stop()
        root._openReportAfterLookup = false
        root.reportError = parsed.message
        return
      }
      if (!parsed.connected) {
        root.clearConnection()
        root.statusText = "Disconnected"
        root.reportError = "Proton VPN disconnected before opening the IP report"
        root.lastError = root.reportError
        return
      }

      var connectionChanged = !root.connected || root.server !== parsed.server
      if (connectionChanged) root.exitIp = ""
      root.connected = true
      root.needsLogin = false
      root.statusText = parsed.statusText
      root.server = parsed.server
      root.location = parsed.location
      root.load = parsed.load
      root.protocol = parsed.protocol
      root.lastError = ""
      if (root.exitIp !== "") root.openBrowserForExitIp()
      else root.startPublicIpCheck()
    }
  }

  Process {
    id: publicIpProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: publicIpStdout
      waitForEnd: true
      onStreamFinished: root._publicIpOutput = text
    }
    stderr: StdioCollector {
      id: publicIpStderr
      waitForEnd: true
      onStreamFinished: root._publicIpErrorOutput = text
    }
    onExited: function(exitCode) {
      if (root._reportTimedOut || root._reportCancelled) return
      var stdout = String(publicIpStdout.text || root._publicIpOutput || "")
      var stderr = String(publicIpStderr.text || root._publicIpErrorOutput || "")
      var parsed = Model.parsePublicIpResult(exitCode, stdout, stderr)
      if (parsed.ok && root.connected) {
        root.exitIp = parsed.ip
        if (root._openReportAfterLookup) {
          root.openBrowserForExitIp()
        } else {
          reportWatchdog.stop()
          root.reportStatus = ""
          root.reportError = ""
        }
      } else if (root.connected) {
        reportWatchdog.stop()
        root._openReportAfterLookup = false
        root.reportError = "Could not determine exit IP: " + parsed.error
      }
    }
  }

  Process {
    id: browserProcess
    running: false
    command: []
    stderr: StdioCollector {
      id: browserStderr
      waitForEnd: true
      onStreamFinished: root._browserErrorOutput = text
    }
    onExited: function(exitCode) {
      reportWatchdog.stop()
      if (root._reportTimedOut || root._reportCancelled) return
      var stderr = String(browserStderr.text || root._browserErrorOutput || "")
      if (exitCode === 0 && root.connected) {
        root.reportStatus = "Opened AbuseIPDB report"
        root.reportError = ""
      } else if (root.connected) {
        root.reportStatus = ""
        root.reportError = Model.classifyFailure(stderr).message
      }
      root._openReportAfterLookup = false
    }
  }
}
