import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Themed single-select dropdown for the Proton VPN panel. Replaces the
// platform-native ComboBox look with the Omarchy kit chrome: the trigger
// paints with the shared focus/hover state, and the popup reads as a panel
// surface (Color.popups.* background + border) with themed rows.
//
// Usage is a drop-in for QQC2 ComboBox: model, textRole/valueRole,
// displayText, currentText/currentIndex, onCurrentIndexChanged and
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
      model: control.popup.visible ? control.delegateModel : null
      currentIndex: control.highlightedIndex

      ScrollIndicator.vertical: ScrollIndicator {}
    }

    background: BorderSurface {
      color: control.popupBackground
      borderSpec: control.popupBorderSpec
      radius: Style.cornerRadius
    }
  }

  delegate: Rectangle {
    required property int index

    width: control.width
    height: Style.spacing.popupRowHeight
    radius: Style.cornerRadius
    color: control.highlightedIndex === index
      ? Style.hoverFillFor(control.foreground, control.accent)
      : "transparent"

    Text {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.spacing.controlPaddingX
      anchors.rightMargin: Style.spacing.controlPaddingX
      text: control.textRole
        ? (Array.isArray(control.model) ? model[control.textRole] : modelData[control.textRole])
        : modelData
      color: control.highlightedIndex === index
        ? Style.hoverStateColor(control.foreground, control.accent)
        : control.foreground
      font.family: control.uiFontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
      verticalAlignment: Text.AlignVCenter
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
    color: control.hovered ? control.foreground : control.foreground
    opacity: control.enabled ? 1 : 0.5
    font.family: control.uiFontFamily
    font.pixelSize: Style.font.body
    verticalAlignment: Text.AlignVCenter
  }
}
