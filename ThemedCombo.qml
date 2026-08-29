import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Themed single-select dropdown for the Proton VPN panel.
//
// Replaces the platform-native ComboBox look with the Omarchy kit chrome: the
// trigger paints with the shared focus/hover state, and the popup reads as a
// panel surface (Color.popups.* background + border) with themed rows. The
// selection bar (popup highlight) and row text bind directly to Color.accent /
// Color.popups.* via control.accent/control.foreground, so they re-render when
// the theme swaps.
//
// Row label is resolved from control.model[index] so both plain string arrays
// (mode/feature/netshield) and role-based object models (country/city through
// textRole) render correctly.
//
// Usage is a drop-in for QQC2 ComboBox: model, textRole/valueRole,
// displayText, currentText/currentIndex, count, onCurrentIndexChanged and
// onActivated all keep working as on plain ComboBox.
ComboBox {
  id: control

  property color foreground: Color.popups.text
  property color popupBackground: Color.popups.background
  property color popupBorder: Color.popups.border
  property color accent: Color.accent
  property string uiFontFamily: Style.font.family

  readonly property var popupBorderSpec: Border.localOrSurfaceSpec(
    "popups", "border", popupBorder, Color.popups.border, Style.normalBorderWidth)

  // Resolve the human label for the row at `index`, robust to JS-array models
  // (strings without textRole, or objects with a textRole).
  function rowLabel(index) {
    var list = control.model
    if (!list || typeof list.length !== "number" || index < 0 || index >= list.length) return ""
    var item = list[index]
    if (control.textRole && item && typeof item === "object") {
      var v = item[control.textRole]
      return v === undefined || v === null ? "" : String(v)
    }
    return item === undefined || item === null ? "" : String(item)
  }

  palette.highlight: accent
  palette.highlightedText: Style.hoverStateColor(foreground, accent)
  palette.buttonText: foreground
  palette.text: foreground
  palette.window: popupBackground
  palette.dark: Qt.darker(foreground, 1.2)

  popup: Popup {
    y: control.height - 1
    width: control.width
    height: Math.min(contentItem.implicitHeight,
                     control.Window.height - topMargin - bottomMargin)
    padding: 1

    contentItem: ListView {
      clip: true
      spacing: Style.spacing.hairline
      implicitHeight: contentHeight
      model: control.delegateModel
      currentIndex: control.highlightedIndex

      ScrollIndicator.vertical: ScrollIndicator {}
    }

    background: BorderSurface {
      color: control.popupBackground
      borderSpec: control.popupBorderSpec
      radius: Style.cornerRadius
    }
  }

  // ItemDelegate keeps QQC2's click-to-select wiring intact; we only restyle its
  // background/contentItem with live Color.*/Style.* bindings so the selection
  // bar re-renders on theme swap.
  delegate: ItemDelegate {
    required property int index

    width: ListView.view.width
    height: Style.spacing.popupRowHeight
    highlighted: control.highlightedIndex === index
    hoverEnabled: true
    onClicked: {
      control.currentIndex = index
      control.activated(index)
      control.popup.close()
    }

    background: Rectangle {
      radius: Style.cornerRadius
      color: (parent.highlighted || parent.hovered)
        ? Style.hoverFillFor(control.foreground, control.accent)
        : "transparent"
    }

    contentItem: Text {
      text: control.rowLabel(index)
      color: (parent.highlighted || parent.hovered)
        ? Style.hoverStateColor(control.foreground, control.accent)
        : control.foreground
      font.family: control.uiFontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
      verticalAlignment: Text.AlignVCenter
      horizontalAlignment: Text.AlignLeft
      leftPadding: Style.spacing.controlPaddingX
      rightPadding: Style.spacing.controlPaddingX
    }
  }

  background: BorderSurface {
    implicitWidth: Style.spacing.dropdownWidth
    implicitHeight: Style.spacing.controlHeight
    color: Style.controlFill(control.activeFocus, control.hovered,
                             control.foreground, control.accent)
    borderSpec: Border.controlSpec(
      control.activeFocus ? "focus"
        : (control.hovered ? "hover-cursor" : "normal"),
      control.foreground, control.accent)
    radius: Style.cornerRadius
  }

  contentItem: Text {
    leftPadding: Style.spacing.controlPaddingX
    rightPadding: control.indicator
      ? control.indicator.width + Style.spacing.controlGap
      : Style.spacing.controlPaddingX
    text: control.displayText
    font: control.font
    color: control.enabled ? control.foreground : Qt.darker(control.foreground, 1.4)
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: Text.AlignLeft
    elide: Text.ElideRight
  }

  indicator: Text {
    x: control.width - width - control.rightPadding
    y: control.topPadding + (control.availableHeight - height) / 2
    text: "󰅀"
    color: Qt.darker(control.foreground, 1.2)
    opacity: control.enabled ? 1 : 0.5
    font.family: control.uiFontFamily
    font.pixelSize: Style.font.body
    verticalAlignment: Text.AlignVCenter
  }
}
