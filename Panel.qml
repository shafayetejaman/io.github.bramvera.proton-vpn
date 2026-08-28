import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.bramvera.proton-vpn"
  ipcTarget: "io.github.bramvera.proton-vpn"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var favorites: settings && settings.favorites instanceof Array ? settings.favorites : []
  property bool settingsExpanded: false
  property bool exitIpVisible: false
  property bool exitIpCopied: false
  property bool signOutArmed: false

  function requestSignOut() {
    if (vpn.connected || vpn.busy) return
    if (!signOutArmed) {
      signOutArmed = true
      signOutConfirmTimer.restart()
      return
    }
    signOutArmed = false
    signOutConfirmTimer.stop()
    vpn.signOut()
  }

  function selectedCountryCode() {
    var options = countryBox.model || []
    if (countryBox.currentIndex < 0 || countryBox.currentIndex >= options.length) return ""
    return String(options[countryBox.currentIndex].code || "")
  }

  function selectedCityName() {
    var options = cityBox.model || []
    if (cityBox.currentIndex < 0 || cityBox.currentIndex >= options.length) return ""
    return String(options[cityBox.currentIndex].name || "")
  }

  function selectedCityFeatures() {
    var options = cityBox.model || []
    if (cityBox.currentIndex < 0 || cityBox.currentIndex >= options.length) return ""
    return String(options[cityBox.currentIndex].features || "")
  }

  function filteredCountries() {
    var query = String(countrySearch.text || "").trim().toLowerCase()
    if (query === "") return vpn.countries
    var result = []
    for (var i = 0; i < vpn.countries.length; i++) {
      var country = vpn.countries[i]
      var searchable = (String(country.name || "") + " " + String(country.code || "")).toLowerCase()
      if (searchable.indexOf(query) !== -1) result.push(country)
    }
    return result
  }

  function filteredCities() {
    var query = String(citySearch.text || "").trim().toLowerCase()
    if (query === "") return vpn.cities
    var result = []
    for (var i = 0; i < vpn.cities.length; i++) {
      var city = vpn.cities[i]
      var searchable = (String(city.name || "") + " " + String(city.features || "")).toLowerCase()
      if (searchable.indexOf(query) !== -1) result.push(city)
    }
    return result
  }

  function selectFirstFilteredCity() {
    cityBox.currentIndex = cityBox.count > 0 ? 0 : -1
  }

  function selectDefaultCountry() {
    if (vpn.countries.length === 0) return
    var preferred = String((root.settings && root.settings.defaultCountryCode) || "ID").toUpperCase()
    var index = 0
    for (var i = 0; i < vpn.countries.length; i++) {
      if (String(vpn.countries[i].code) === preferred) {
        index = i
        break
      }
    }
    countryBox.currentIndex = index
    if (modeBox.currentText === "City") vpn.loadCities(root.selectedCountryCode())
  }

  function submitConnection() {
    var target = ""
    if (modeBox.currentText === "Country") target = selectedCountryCode()
    else if (modeBox.currentText === "City") target = selectedCityName()
    else if (modeBox.currentText === "Server") target = serverField.text
    if (vpn.connect(modeBox.currentText, target, featureBox.currentText)) serverField.focus = false
  }

  function showServerConnect() {
    modeBox.currentIndex = 4
    Qt.callLater(function() {
      serverField.forceActiveFocus()
      serverField.selectAll()
    })
  }

  function selectedCountryName() {
    var options = countryBox.model || []
    if (countryBox.currentIndex < 0 || countryBox.currentIndex >= options.length) return ""
    return String(options[countryBox.currentIndex].name || "")
  }

  function currentFavorite() {
    var mode = modeBox.currentText
    var target = ""
    var label = mode + " server"
    if (mode === "Country") {
      target = selectedCountryCode()
      label = selectedCountryName()
    } else if (mode === "City") {
      target = selectedCityName()
      label = target + (selectedCountryName() !== "" ? ", " + selectedCountryName() : "")
    } else if (mode === "Server") {
      target = String(serverField.text || "").trim()
      label = target
    } else if (mode === "Random") {
      label = "Random server"
    } else {
      label = "Fastest server"
    }
    return { mode: mode, target: target, feature: featureBox.currentText, label: label }
  }

  function currentFavoriteIndex() {
    return Model.favoriteIndex(favorites, currentFavorite())
  }

  function persistPluginSetting(name, value) {
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return
    var entry = { id: root.moduleName }
    for (var key in settings) if (key !== "id" && key !== name) entry[key] = settings[key]
    entry[name] = value
    root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function persistFavorites(next) {
    persistPluginSetting("favorites", next)
  }

  function configValue(settingName) {
    var value = vpn.configValues ? vpn.configValues[settingName] : undefined
    return value === undefined || value === null ? "" : String(value)
  }

  function configLocked(settingName) {
    return /upgrade to enable/i.test(configValue(settingName))
  }

  function syncConfigControls() {
    var values = ["off", "malware-only", "malware-ads-trackers"]
    netshieldBox.currentIndex = values.indexOf(configValue("netshield"))
  }

  function toggleSettings() {
    settingsExpanded = !settingsExpanded
    if (settingsExpanded) vpn.refreshConfig()
  }

  function applyCustomDns() {
    var servers = String(customDnsField.text || "").trim()
    if (servers === "") {
      vpn.configError = "Enter at least one DNS server"
      vpn.lastError = vpn.configError
      customDnsField.forceActiveFocus()
      return
    }
    persistPluginSetting("customDnsServers", servers)
    vpn.setConfig("custom-dns", "on", servers)
  }

  function toggleCustomDns() {
    if (configValue("custom-dns") === "on") {
      vpn.setConfig("custom-dns", "off", "")
    } else {
      applyCustomDns()
    }
  }

  function toggleCurrentFavorite() {
    var favorite = currentFavorite()
    if ((favorite.mode === "Country" || favorite.mode === "City" || favorite.mode === "Server") && favorite.target === "") {
      vpn.lastError = "Choose a location before adding a favorite"
      return
    }
    var existing = Model.favoriteIndex(favorites, favorite)
    persistFavorites(existing >= 0 ? Model.removeFavorite(favorites, existing) : Model.addFavorite(favorites, favorite, 12))
  }

  function removeFavorite(index) {
    persistFavorites(Model.removeFavorite(favorites, index))
  }

  function connectFavorite(favorite) {
    if (!favorite) return
    vpn.connect(String(favorite.mode || "Fastest"), String(favorite.target || ""), String(favorite.feature || "None"))
  }

  function copyExitIp() {
    if (ipCopyProcess.running) return
    var plan = Model.copyIpPlan("wl-copy", vpn.exitIp)
    if (!plan.ok) {
      vpn.reportError = plan.error
      return
    }
    exitIpCopied = false
    ipCopyProcess.command = plan.command
    ipCopyProcess.running = true
  }

  function favoriteDescription(favorite) {
    if (!favorite) return ""
    var mode = String(favorite.mode || "")
    var feature = String(favorite.feature || "None")
    return feature === "None" ? mode : mode + " · " + feature
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    if (opened) {
      vpn.automaticRefresh()
      if (vpn.countries.length === 0) vpn.refreshLocations()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    } else {
      signOutArmed = false
      signOutConfirmTimer.stop()
    }
  }

  Service {
    id: vpn
    settings: root.settings
  }

  Connections {
    target: vpn
    function onCountriesChanged() { root.selectDefaultCountry() }
    function onCitiesChanged() { Qt.callLater(root.selectFirstFilteredCity) }
    function onConfigValuesChanged() { root.syncConfigControls() }
    function onNeedsLoginChanged() {
      if (!vpn.needsLogin) return
      root.settingsExpanded = false
      root.signOutArmed = false
      signOutConfirmTimer.stop()
    }
    function onExitIpChanged() {
      root.exitIpVisible = false
      root.exitIpCopied = false
    }
  }

  Process {
    id: ipCopyProcess
    running: false
    command: []
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.exitIpCopied = true
        copyFeedbackTimer.restart()
      } else {
        root.exitIpCopied = false
        vpn.reportError = "Could not copy the exit IP"
      }
    }
  }

  Timer {
    id: copyFeedbackTimer
    interval: 1800
    repeat: false
    onTriggered: root.exitIpCopied = false
  }

  Timer {
    id: signOutConfirmTimer
    interval: 6000
    repeat: false
    onTriggered: root.signOutArmed = false
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { vpn.refresh(); return "ok" }
    function refreshLocations(): string { vpn.refreshLocations(); return "ok" }
    function loadCities(countryCode: string): string { vpn.loadCities(countryCode); return "ok" }
    function locationStatus(): string { return vpn.countries.length + " countries; " + vpn.cities.length + " cities for " + vpn.citiesCountryCode }
    function refreshConfig(): string { vpn.refreshConfig(); return "ok" }
    function configStatus(): string { return JSON.stringify(vpn.configValues) }
    function checkExitIp(): string { return vpn.openIpReport() ? "ok" : vpn.reportError }
    function exitIpStatus(): string {
      return JSON.stringify({ ip: vpn.exitIp, status: vpn.reportStatus, error: vpn.reportError, busy: vpn.reportBusy })
    }
    function up(): string { vpn.connect("fastest", "", "none"); return "ok" }
    function disconnect(): string { vpn.disconnect(); return "ok" }
    function status(): string { return vpn.statusText }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      ProtonVpnIcon {
        iconSize: Style.space(11)
        badgeColor: root.urgent
        connected: vpn.connected
        warning: vpn.needsLogin || vpn.lastError !== ""
        busy: vpn.indicatorBusy
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) vpn.toggle()
      else if (buttonCode === Qt.MiddleButton) vpn.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(540))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: countrySearch.activeFocus || citySearch.activeFocus || serverField.activeFocus || customDnsField.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "r" || text === "R") vpn.refresh()
        else if (text === "t" || text === "T") vpn.toggle()
      }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        Column {
          id: content
          width: parent.width
          spacing: Style.space(12)

          Item {
            width: parent.width
            implicitHeight: hero.implicitHeight

            PanelHero {
              id: hero
              width: parent.width
              title: vpn.server || "Proton VPN Control Center"
              meta: vpn.connected && vpn.location !== "" ? vpn.location : vpn.statusText
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: 1.0
              iconComponent: Component {
                ProtonVpnIcon {
                  iconSize: Style.font.display
                  badgeColor: root.urgent
                  connected: vpn.connected
                  warning: vpn.needsLogin || vpn.lastError !== ""
                  busy: vpn.indicatorBusy
                }
              }
              trailingControl: Component {
                ToggleSwitch {
                  id: powerSwitch
                  visible: vpn.installed && !vpn.needsLogin
                  checked: vpn.connected
                  busy: vpn.busy
                  foreground: hero.foreground
                  onToggled: vpn.toggle()

                  PanelToolTip {
                    visible: powerSwitch.containsMouse
                    text: vpn.connected ? "Disconnect Proton VPN" : "Quick connect"
                    fontFamily: hero.fontFamily
                  }
                }
              }
            }
          }

          Text {
            visible: vpn.actionStatus !== "" || vpn.lastError !== ""
            width: parent.width
            text: vpn.actionStatus !== "" ? vpn.actionStatus : vpn.lastError
            color: vpn.lastError !== "" && vpn.actionStatus === "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Column {
            visible: !vpn.installed
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "SETUP"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              width: parent.width
              text: "The official Proton VPN CLI is missing. Omarchy can install proton-vpn-cli in a floating terminal; you may be asked for your sudo password. The CLI cannot run alongside Proton VPN GUI."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            ActionButton {
              width: parent.width
              text: vpn.onboardingBusy ? "Installer terminal active…" : "Install Proton VPN CLI"
              enabled: !vpn.onboardingBusy
              onClicked: vpn.installCli()
            }

            ActionButton {
              width: parent.width
              text: vpn.refreshing ? "Checking…" : "Refresh detection"
              enabled: !vpn.refreshing && !vpn.onboardingBusy
              onClicked: vpn.refresh()
            }
          }

          Column {
            visible: vpn.installed && vpn.needsLogin
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "SIGN IN"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              width: parent.width
              text: "Enter only your Proton username here. Authentication opens in a terminal so this plugin never handles your password."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            TextField {
              id: protonUsernameField
              width: parent.width
              placeholderText: "username or user@proton.me"
              font.family: root.fontFamily
              color: root.foreground
              selectByMouse: true
              onAccepted: vpn.signIn(text)
              background: Rectangle {
                radius: Style.cornerRadius
                color: Style.controlFill(protonUsernameField.activeFocus, protonUsernameField.hovered, root.foreground, Color.accent)
                border.color: Style.controlBorder(protonUsernameField.activeFocus, protonUsernameField.hovered, root.foreground, Color.accent)
                border.width: Style.controlBorderWidth(protonUsernameField.activeFocus, protonUsernameField.hovered)
              }
            }

            ActionButton {
              width: parent.width
              text: vpn.onboardingBusy ? "Sign-in terminal active…" : "Sign in with Proton"
              enabled: !vpn.onboardingBusy && protonUsernameField.text.trim() !== ""
              onClicked: vpn.signIn(protonUsernameField.text)
            }

            ActionButton {
              width: parent.width
              text: vpn.refreshing ? "Checking…" : "Refresh sign-in status"
              enabled: !vpn.refreshing && !vpn.onboardingBusy
              onClicked: vpn.refreshStatus()
            }
          }

          Text {
            visible: (!vpn.installed || vpn.needsLogin) && (vpn.onboardingStatus !== "" || vpn.onboardingError !== "")
            width: parent.width
            text: vpn.onboardingError !== "" ? vpn.onboardingError : vpn.onboardingStatus
            color: vpn.onboardingError !== "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Column {
            visible: vpn.installed && vpn.connected
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "CONNECTION"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            DetailRow { label: "Server"; value: vpn.server }
            DetailRow { label: "Location"; value: vpn.location }
            DetailRow { label: "Load"; value: vpn.load }
            DetailRow { label: "Protocol"; value: vpn.protocol }
            RowLayout {
              width: parent.width
              spacing: Style.space(4)

              Text {
                text: "Exit IP"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                Layout.fillWidth: true
                text: vpn.exitIp !== ""
                  ? (root.exitIpVisible ? vpn.exitIp : "••••••••••••")
                  : (vpn.exitIpBusy ? "Checking…" : "Unavailable")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideLeft
              }

              PanelActionButton {
                visible: vpn.exitIp !== ""
                iconText: root.exitIpVisible ? "󰈉" : "󰈈"
                tooltipText: root.exitIpVisible ? "Hide exit IP" : "Show exit IP"
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.body
                size: Style.space(22)
                onClicked: root.exitIpVisible = !root.exitIpVisible
              }

              PanelActionButton {
                visible: vpn.exitIp !== ""
                iconText: root.exitIpCopied ? "󰄬" : "󰆏"
                tooltipText: root.exitIpCopied ? "Copied" : "Copy exit IP"
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.body
                size: Style.space(22)
                enabled: !ipCopyProcess.running
                onClicked: root.copyExitIp()
              }
            }

            Text {
              visible: vpn.dnsCompatibilityError !== ""
              width: parent.width
              text: vpn.dnsCompatibilityError
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Column {
              visible: vpn.dnsCompatibilityNeeded || vpn.dnsCompatibilityStatus !== ""
              width: parent.width
              spacing: Style.space(6)

              Text {
                width: parent.width
                text: vpn.dnsCompatibilityNeeded
                  ? "Strict DNS-over-TLS may block Proton DNS. Allow a temporary exception for proton0?"
                  : vpn.dnsCompatibilityStatus
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }

              ActionButton {
                visible: vpn.dnsCompatibilityNeeded
                width: parent.width
                text: vpn.dnsCompatibilityBusy ? "Applying DNS exception…" : "Allow Proton DNS"
                enabled: !vpn.dnsCompatibilityBusy
                onClicked: vpn.allowProtonDnsCompatibility()
              }
            }

            Text {
              visible: vpn.reportError !== ""
              width: parent.width
              text: vpn.reportError
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Text {
              visible: vpn.reportStatus !== ""
              width: parent.width
              text: vpn.reportStatus
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignHCenter
            }

            ActionButton {
              width: parent.width
              text: vpn.reportBusy
                ? (vpn.openingReport ? "Opening AbuseIPDB…" : "Finding exit IP…")
                : "Check IP reputation"
              enabled: !vpn.reportBusy && !vpn.busy
              onClicked: vpn.openIpReport()
            }

            Text {
              width: parent.width
              text: "The exit IPv4 is fetched once per VPN server through proton0. The button opens its AbuseIPDB page; no API key is required."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignHCenter
            }
          }

          PanelSeparator {
            visible: vpn.installed && !vpn.needsLogin
            foreground: root.foreground
          }

          Column {
            visible: vpn.installed && !vpn.needsLogin
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "FAVORITES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              visible: root.favorites.length === 0
              width: parent.width
              text: "Choose a quick-connect target and press the star to save it here."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Repeater {
              model: root.favorites
              FavoriteRow {
                required property var modelData
                required property int index
                width: parent.width
                favorite: modelData
                rowIndex: index
              }
            }
          }

          PanelSeparator {
            visible: vpn.installed && !vpn.needsLogin
            foreground: root.foreground
          }

          Column {
            visible: vpn.installed && !vpn.needsLogin
            width: parent.width
            spacing: Style.space(9)

            PanelSectionHeader {
              text: "QUICK CONNECT"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            ActionButton {
              visible: modeBox.currentText !== "Server"
              width: parent.width
              text: vpn.connected
                ? "Switch by server ID (e.g. CH#242)"
                : "Connect by server ID (e.g. CH#242)"
              enabled: !vpn.busy
              onClicked: root.showServerConnect()
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(8)

              ThemedCombo {
                id: modeBox
                Layout.fillWidth: true
                model: ["Fastest", "Random", "Country", "City", "Server"]
                font.family: root.fontFamily
                onCurrentIndexChanged: {
                  if (currentText === "City") vpn.loadCities(root.selectedCountryCode())
                }
              }

              ThemedCombo {
                id: featureBox
                Layout.fillWidth: true
                model: ["None", "P2P", "Secure Core", "Tor"]
                font.family: root.fontFamily
              }
            }

            TextField {
              id: countrySearch
              visible: modeBox.currentText === "Country" || modeBox.currentText === "City"
              width: parent.width
              placeholderText: "Search countries by name or code…"
              font.family: root.fontFamily
              color: root.foreground
              selectByMouse: true
              onTextChanged: Qt.callLater(function() {
                countryBox.currentIndex = countryBox.count > 0 ? 0 : -1
              })
              background: Rectangle {
                radius: Style.cornerRadius
                color: Style.controlFill(countrySearch.activeFocus, countrySearch.hovered, root.foreground, Color.accent)
                border.color: Style.controlBorder(countrySearch.activeFocus, countrySearch.hovered, root.foreground, Color.accent)
                border.width: Style.controlBorderWidth(countrySearch.activeFocus, countrySearch.hovered)
              }
            }

            ThemedCombo {
              id: countryBox
              visible: modeBox.currentText === "Country" || modeBox.currentText === "City"
              width: parent.width
              model: root.filteredCountries()
              textRole: "name"
              valueRole: "code"
              font.family: root.fontFamily
              enabled: !vpn.locationsBusy && vpn.countries.length > 0
              displayText: vpn.locationsBusy && vpn.countries.length === 0 ? "Loading countries…" : currentText
              onCurrentIndexChanged: {
                if (modeBox.currentText === "City") vpn.loadCities(root.selectedCountryCode())
              }
            }

            TextField {
              id: citySearch
              visible: modeBox.currentText === "City"
              width: parent.width
              placeholderText: "Search cities or features…"
              font.family: root.fontFamily
              color: root.foreground
              selectByMouse: true
              onTextChanged: Qt.callLater(root.selectFirstFilteredCity)
              background: Rectangle {
                radius: Style.cornerRadius
                color: Style.controlFill(citySearch.activeFocus, citySearch.hovered, root.foreground, Color.accent)
                border.color: Style.controlBorder(citySearch.activeFocus, citySearch.hovered, root.foreground, Color.accent)
                border.width: Style.controlBorderWidth(citySearch.activeFocus, citySearch.hovered)
              }
            }

            ThemedCombo {
              id: cityBox
              visible: modeBox.currentText === "City"
              width: parent.width
              model: root.filteredCities()
              textRole: "name"
              valueRole: "name"
              font.family: root.fontFamily
              enabled: !vpn.locationsBusy && vpn.cities.length > 0
              displayText: vpn.locationsBusy
                ? "Loading cities…"
                : (currentText || (count > 0 ? "Choose a city" : (citySearch.text.trim() !== "" ? "No matching cities" : "No cities available")))
              onCountChanged: Qt.callLater(root.selectFirstFilteredCity)
            }

            Text {
              visible: modeBox.currentText === "City" && root.selectedCityFeatures() !== ""
              width: parent.width
              text: "Available features: " + root.selectedCityFeatures()
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            TextField {
              id: serverField
              visible: modeBox.currentText === "Server"
              width: parent.width
              placeholderText: "Server ID, for example CH#242"
              font.family: root.fontFamily
              color: root.foreground
              selectByMouse: true
              onAccepted: root.submitConnection()
              background: Rectangle {
                radius: Style.cornerRadius
                color: Style.normalFillFor(root.foreground, Color.accent, root.urgent)
                border.color: serverField.activeFocus ? Color.accent : root.dim
                border.width: 1
              }
            }

            Text {
              visible: modeBox.currentText === "Server"
              width: parent.width
              text: vpn.connected
                ? "Current server: " + vpn.server + ". Enter a different Proton server ID, such as CH#242, to switch directly."
                : "Enter a Proton server ID manually, such as CH#242. The CLI does not provide a browsable server list."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Text {
              visible: vpn.locationError !== ""
              width: parent.width
              text: vpn.locationError
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Text {
              visible: modeBox.currentText === "City" && cityBox.currentText !== ""
              width: parent.width
              text: "Proton CLI will choose the fastest available server in " + cityBox.currentText + ". Individual server lists are not exposed by the official CLI."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(8)

              ActionButton {
                Layout.fillWidth: true
                text: modeBox.currentText === "Server"
                  ? (vpn.connected ? "Switch server" : "Connect to server")
                  : (vpn.connected ? "Connect elsewhere" : "Connect")
                enabled: !vpn.busy
                onClicked: root.submitConnection()
              }

              PanelActionButton {
                iconText: root.currentFavoriteIndex() >= 0 ? "★" : "☆"
                tooltipText: root.currentFavoriteIndex() >= 0 ? "Remove from favorites" : "Add to favorites"
                foreground: root.foreground
                hoverColor: Color.accent
                fontFamily: root.fontFamily
                fontSize: Style.font.subtitle
                size: Style.space(36)
                bordered: true
                enabled: !vpn.busy
                onClicked: root.toggleCurrentFavorite()
              }
            }
          }

          PanelSeparator {
            visible: vpn.installed && !vpn.needsLogin
            foreground: root.foreground
          }

          Column {
            visible: vpn.installed && !vpn.needsLogin
            width: parent.width
            spacing: Style.space(9)

            ActionButton {
              width: parent.width
              text: root.settingsExpanded ? "Hide VPN settings" : "VPN settings"
              enabled: !vpn.configBusy
              onClicked: root.toggleSettings()
            }

            Column {
              visible: root.settingsExpanded
              width: parent.width
              spacing: Style.space(8)

              PanelSectionHeader {
                text: "SETTINGS"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Text {
                visible: vpn.configBusy && !vpn.configLoaded
                width: parent.width
                text: "Loading current Proton VPN configuration…"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Text {
                visible: vpn.configError !== ""
                width: parent.width
                text: vpn.configError
                color: root.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }

              Column {
                width: parent.width
                spacing: Style.spacing.xs

                Text {
                  width: parent.width
                  text: "NetShield"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }

                Text {
                  width: parent.width
                  text: "Block malware, ads, and trackers at the VPN level."
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }

                ThemedCombo {
                  id: netshieldBox
                  width: parent.width
                  model: ["off", "malware-only", "malware-ads-trackers"]
                  font.family: root.fontFamily
                  enabled: vpn.configLoaded && !vpn.configBusy && !root.configLocked("netshield")
                  displayText: root.configLocked("netshield") ? root.configValue("netshield") : currentText
                  onActivated: vpn.setConfig("netshield", currentText, "")
                }
              }

              ConfigToggle {
                width: parent.width
                settingKey: "kill-switch"
                enabledValue: "standard"
                label: "Kill switch"
                description: vpn.connected ? "Disconnect before changing this setting." : "Block internet traffic if the VPN connection drops."
                extraLocked: vpn.connected
              }

              ConfigToggle {
                width: parent.width
                settingKey: "ipv6"
                label: "IPv6"
                description: "Route IPv6 traffic through Proton VPN."
              }

              Column {
                width: parent.width
                spacing: Style.space(8)

                Toggle {
                  width: parent.width
                  checked: root.configValue("custom-dns") === "on"
                  label: "Custom DNS"
                  description: "Normally leave disabled to use Proton DNS and NetShield."
                  foreground: root.foreground
                  accent: Color.accent
                  fontFamily: root.fontFamily
                  enabled: vpn.configLoaded && !vpn.configBusy && !root.configLocked("custom-dns")
                  opacity: enabled ? 1.0 : 0.5
                  onClicked: root.toggleCustomDns()
                }

                TextField {
                  id: customDnsField
                  width: parent.width
                  text: String((root.settings && root.settings.customDnsServers) || "")
                  placeholderText: "1.1.1.1,8.8.8.8"
                  font.family: root.fontFamily
                  color: root.foreground
                  selectByMouse: true
                  onAccepted: root.applyCustomDns()
                  background: Rectangle {
                    radius: Style.cornerRadius
                    color: Style.controlFill(customDnsField.activeFocus, customDnsField.hovered, root.foreground, Color.accent)
                    border.color: Style.controlBorder(customDnsField.activeFocus, customDnsField.hovered, root.foreground, Color.accent)
                    border.width: Style.controlBorderWidth(customDnsField.activeFocus, customDnsField.hovered)
                  }
                }

                Text {
                  width: parent.width
                  text: root.configValue("custom-dns") === "on"
                    ? "Press Enter after editing to apply new addresses."
                    : "Enabling this overrides Proton DNS and NetShield."
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
              }

              ConfigToggle {
                width: parent.width
                settingKey: "port-forwarding"
                label: "Port forwarding"
                description: "Request a forwarded port. An external helper must maintain and retrieve the lease."
              }

              ConfigToggle {
                width: parent.width
                settingKey: "moderate-nat"
                label: "Moderate NAT (NAT Type 2)"
                description: "Improve peer-to-peer connectivity with a less restrictive NAT."
              }

              ConfigToggle {
                width: parent.width
                settingKey: "vpn-accelerator"
                label: "VPN Accelerator"
                description: "Use Proton's connection speed optimization."
              }

              ConfigToggle {
                width: parent.width
                settingKey: "anonymous-crash-reports"
                label: "Anonymous crash reports"
                description: "Allow anonymous CLI crash reports."
              }

              Text {
                width: parent.width
                text: "Values are read from protonvpn config list. Changes use protonvpn config set."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
              }

              PanelSeparator {
                foreground: root.foreground
              }

              PanelSectionHeader {
                text: "ACCOUNT"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Text {
                width: parent.width
                text: vpn.connected
                  ? "Disconnect the VPN before signing out."
                  : "Sign out to clear local Proton credentials and switch accounts."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }

              ActionButton {
                width: parent.width
                text: root.signOutArmed ? "Confirm sign out" : (vpn.connected ? "Disconnect before signing out" : "Sign out")
                enabled: !vpn.busy && !vpn.configBusy && !vpn.connected
                onClicked: root.requestSignOut()
              }
            }
          }

          Text {
            visible: vpn.installed
            width: parent.width
            text: "Left click: panel   Right click: toggle   Middle click: refresh"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }
  }

  component DetailRow: RowLayout {
    required property string label
    required property string value
    property color valueColor: root.foreground
    width: parent ? parent.width : 0
    visible: value !== ""
    spacing: Style.space(12)

    Text {
      text: parent.label
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Text {
      Layout.fillWidth: true
      text: parent.value
      color: parent.valueColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideLeft
    }
  }

  component FavoriteRow: CursorSurface {
    id: favoriteRow
    required property var favorite
    required property int rowIndex

    foreground: root.foreground
    implicitHeight: favoriteContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: vpn.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
      enabled: !vpn.busy
      onClicked: root.connectFavorite(favoriteRow.favorite)
    }

    RowLayout {
      id: favoriteContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.spacing.controlPaddingX
      anchors.rightMargin: Style.spacing.controlPaddingX
      spacing: Style.space(8)

      Column {
        Layout.fillWidth: true
        spacing: Style.spacing.xxs

        Text {
          width: parent.width
          text: String(favoriteRow.favorite.label || favoriteRow.favorite.target || favoriteRow.favorite.mode || "Favorite")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: root.favoriteDescription(favoriteRow.favorite)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        iconText: "󰅖"
        tooltipText: "Remove favorite"
        foreground: root.foreground
        hoverColor: root.urgent
        fontFamily: root.fontFamily
        enabled: !vpn.busy
        onClicked: root.removeFavorite(favoriteRow.rowIndex)
      }
    }
  }

  component ConfigToggle: Toggle {
    required property string settingKey
    property string enabledValue: "on"
    property bool extraLocked: false

    readonly property bool locked: extraLocked || root.configLocked(settingKey)

    checked: root.configValue(settingKey) === enabledValue
    foreground: root.foreground
    accent: Color.accent
    fontFamily: root.fontFamily
    enabled: vpn.configLoaded && !vpn.configBusy && !locked
    opacity: enabled ? 1.0 : 0.5
    onClicked: vpn.setConfig(settingKey, checked ? "off" : enabledValue, "")
  }

  component ActionButton: Rectangle {
    id: actionButton
    property string text: ""
    signal clicked()
    implicitHeight: Style.space(36)
    radius: Style.cornerRadius
    color: mouseArea.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : Style.normalFillFor(root.foreground, Color.accent, root.urgent)
    opacity: enabled ? 1.0 : 0.5

    Text {
      anchors.centerIn: parent
      text: actionButton.text
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
    }

    MouseArea {
      id: mouseArea
      anchors.fill: parent
      hoverEnabled: true
      enabled: actionButton.enabled
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: actionButton.clicked()
    }
  }
}
