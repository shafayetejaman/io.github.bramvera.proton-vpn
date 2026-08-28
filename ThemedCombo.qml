import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Themed single-select dropdown for the Proton VPN panel.
//
// Rather than re-deriving the popup/delegate internals (whose model->item
// context is easy to get subtly wrong), this themes the ComboBox through its
// palette plus the trigger's background/contentItem/indicator only. The
// delegate and popup stay on QQC2's default rendering path, so options keep
// rendering correctly for both plain string models and role-based models.
//
// Usage is a drop-in for QQC2 ComboBox: model, textRole/valueRole,
// displayText, currentText/currentIndex, count, onCurrentIndexChanged and
// onActivated all keep working as on plain ComboBox.
ComboBox {
  id: control

  property color foreground: Color.popups.text
  property color popupBackground: Color.popups.background
  property color accent: Color.accent
  property string uiFontFamily: Style.font.family

  palette.highlight: accent
  palette.highlightedText: Style.hoverStateColor(foreground, accent)
  palette.buttonText: foreground
  palette.text: foreground
  palette.window: popupBackground
  palette.dark: Qt.darker(foreground, 1.2)

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
