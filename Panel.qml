import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// G15 — Dell G15 temps and fans in the bar, with a panel for the two things
// the TUI is otherwise needed for: power mode and keyboard backlight.
//
// Reads go through `g15 status` (hwmon + ~/.config/g15/state only, never the
// USB device), so polling can never wedge the AW-ELC controller. Writes go
// through the `g15` CLI, which owns the USB protocol.
Panel {
  id: root
  moduleName: "io.github.andeen171.g15"
  ipcTarget: "g15"

  readonly property int refreshIntervalSec: Math.max(1, Math.min(60, setting("refreshIntervalSec", 5)))
  readonly property bool showValues: setting("showValues", true) === true
  // Power and fan control need root; LED control does not. See README for the
  // sudoers line this default expects.
  readonly property string powerCommand: setting("powerCommand", "sudo -n g15 power")
  readonly property string tuiCommand: setting("tuiCommand", "omarchy-launch-or-focus-tui g15-tui")

  property var status: Model.emptyStatus()

  readonly property bool readoutsVisible: !button.vertical && showValues && status.sensors
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function apply(raw) {
    var parsed = Model.parseStatus(raw)
    // A failed read (g15 upgrading, hwmon module reloading) must not blank the
    // bar — keep the last good sample.
    if (parsed) status = parsed
  }

  // Every write is an argv vector, never a shell string, so nothing read from
  // the state file can be re-tokenized.
  function apply_argv(argv) {
    if (actionProc.running) return
    actionProc.command = argv
    actionProc.running = true
  }

  function setPower(mode) {
    // powerCommand is a user-editable setting (sudo wrapper, doas, ...), so it
    // is a shell string; `mode` only ever comes from Model.powerOptions().
    apply_argv(["bash", "-lc", root.powerCommand + " " + mode])
  }

  function setEffect(name) {
    apply_argv(["g15", "led", "effect", name])
  }

  function setBrightness(percent) {
    apply_argv(["g15", "led", "brightness", String(Math.round(percent))])
  }

  Process {
    id: statusProc
    command: ["g15", "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.apply(text)
    }
  }

  Process {
    id: actionProc
    // The CLI writes the state file before exiting, so the next read already
    // reflects the change.
    onExited: root.refresh()
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  onOpenedChanged: if (opened) refresh()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.readoutsVisible ? Model.barText(root.status) : Model.widgetIcon()
    tooltipText: Model.tooltip(root.status)
    onPressed: function(b) {
      // The panel covers the common cases; the TUI stays one right-click away.
      if (b === Qt.RightButton) root.bar.run(root.tuiCommand)
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
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(16)

        // ---------- Sensors ----------
        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "SENSORS"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          SensorRow {
            width: parent.width
            icon: Model.cpuIcon()
            name: "CPU"
            temp: root.status.cpu
            rpm: root.status.fan1
          }

          SensorRow {
            width: parent.width
            icon: Model.gpuIcon()
            name: "GPU"
            temp: root.status.gpu
            rpm: root.status.fan2
          }

          Text {
            visible: !root.status.sensors
            width: parent.width
            text: "no data — needs g15 0.3.0+ on PATH"
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        PanelSeparator { foreground: root.foreground }

        // ---------- Power ----------
        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "POWER MODE"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          ButtonGroup {
            options: Model.powerOptions()
            value: root.status.power
            foreground: root.foreground
            background: root.bar ? root.bar.background : Color.background
            accent: Color.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            focusable: false
            onChanged: function(v) { root.setPower(v) }
          }

          Text {
            visible: root.status.power === "unknown"
            width: parent.width
            text: "unknown until a mode is set once (needs root — see README)"
            color: root.foreground
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        PanelSeparator { foreground: root.foreground }

        // ---------- Keyboard backlight ----------
        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "KEYBOARD LIGHT"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Item {
            width: parent.width
            implicitHeight: Math.max(swatch.height, brightness.implicitHeight, brightnessValue.implicitHeight)

            Rectangle {
              id: swatch
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(14)
              height: width
              radius: Style.cornerRadius > 0 ? width / 2 : 0
              color: root.status.color
              opacity: root.status.brightness > 0 ? 1 : 0.3
              border.width: 1
              border.color: Util.alpha(root.foreground, 0.3)
            }

            PanelSlider {
              id: brightness
              anchors.left: swatch.right
              anchors.leftMargin: Style.space(10)
              anchors.right: brightnessValue.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              bar: root.bar
              minimum: 0
              maximum: 100
              step: 5
              integer: true
              value: root.status.brightness
              // Applied on release, not on every drag tick: each write is a USB
              // control transfer to the LED controller, and the CLI persists
              // state on each one.
              onReleased: function(v) { root.setBrightness(v) }
            }

            Text {
              id: brightnessValue
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: Math.round(brightness.liveValue) + "%"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignRight
              width: Style.space(34)
            }
          }

          ButtonGroup {
            options: Model.effectOptions()
            value: root.status.effect
            foreground: root.foreground
            background: root.bar ? root.bar.background : Color.background
            accent: Color.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            focusable: false
            onChanged: function(v) { root.setEffect(v) }
          }

          Text {
            width: parent.width
            text: "Effects reuse the colors last set from the TUI or CLI."
            color: root.foreground
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        PanelSeparator { foreground: root.foreground }

        // ---------- Footer ----------
        Item {
          width: parent.width
          implicitHeight: tuiButton.implicitHeight

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Colors, per-zone control"
            color: root.foreground
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Button {
            id: tuiButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "Open TUI"
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            bordered: true
            onClicked: {
              root.bar.run(root.tuiCommand)
              root.close()
            }
          }
        }
      }
    }
  }

  // One sensor line: icon and name, the temperature as a meter, rpm at the end.
  component SensorRow: Item {
    id: row

    property string icon: ""
    property string name: ""
    property int temp: 0
    property int rpm: 0

    implicitHeight: Math.max(label.implicitHeight, rpmText.implicitHeight, Style.space(14))

    Text {
      id: label
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: row.icon + "  " + row.name
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Text {
      id: tempText
      anchors.left: label.right
      anchors.leftMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(40)
      text: row.temp > 0 ? row.temp + "°" : "—"
      horizontalAlignment: Text.AlignRight
      color: Model.isHot(row.temp) ? Color.urgent : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Rectangle {
      id: meter
      anchors.left: tempText.right
      anchors.leftMargin: Style.space(10)
      anchors.right: rpmText.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      height: Math.max(3, Style.space(4))
      radius: height / 2
      color: Util.alpha(root.foreground, 0.18)

      Rectangle {
        width: parent.width * Model.tempFraction(row.temp)
        height: parent.height
        radius: parent.radius
        color: Model.isHot(row.temp) ? Color.urgent : root.foreground
        Behavior on width { NumberAnimation { duration: 200 } }
      }
    }

    Text {
      id: rpmText
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(64)
      horizontalAlignment: Text.AlignRight
      text: Model.rpmText(row.rpm)
      color: root.foreground
      opacity: 0.7
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
