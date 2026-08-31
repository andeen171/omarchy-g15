import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// G15 — Dell G15 temps and fans in the bar, with a panel carrying everything
// the TUI controls: power mode, fan boost, and the keyboard backlight.
//
// Reads go through `g15 status` (hwmon, the driver's platform profile and
// ~/.config/g15/state only, never the USB device), so polling can never wedge
// the AW-ELC controller. Writes go
// through the `g15` CLI, which owns the USB protocol.
Panel {
  id: root
  moduleName: "io.github.andeen171.g15"
  ipcTarget: "g15"

  readonly property int refreshIntervalSec: Math.max(1, Math.min(60, setting("refreshIntervalSec", 5)))
  readonly property bool showValues: setting("showValues", true) === true
  // Power modes and fan boost go through WMAX, which needs root; LED control
  // does not. pkexec hands that to the desktop's polkit agent — the shell's own
  // password dialog — so nothing has to be whitelisted in sudoers. Point this
  // at `sudo -n g15` instead if a passwordless rule is what you want.
  readonly property string rootCommand: setting("rootCommand", "pkexec /usr/bin/g15")
  readonly property string tuiCommand: setting("tuiCommand", "omarchy-launch-or-focus-tui g15-tui")

  property var status: Model.emptyStatus()

  // Which swatch the picker edits, and the picker's live HSV. The HSV is only
  // seeded when the picker opens: binding it to `status` would yank the sliders
  // out from under a drag on every poll.
  property int selectedColor: 0
  property bool pickerOpen: false
  property real pickH: 0
  property real pickS: 100
  property real pickV: 100
  readonly property string pickHex: Model.hsvToHex(pickH, pickS, pickV)

  readonly property bool canAdd: status.colors.length < status.maxColors
  readonly property bool canRemove: status.colors.length > status.minColors

  // What we just asked for, shown until the poll that follows the command
  // lands. Without it a control snaps back to the old value for the moment
  // between releasing the slider and the next `g15 status` — and with pkexec
  // that moment lasts as long as the password prompt is up.
  property real pendingBrightness: -1
  property real pendingSpeed: -1
  property real pendingBoost: -1
  property string pendingPower: ""
  property string pendingEffect: ""
  property bool awaitingRefresh: false

  function clearPending() {
    pendingBrightness = -1
    pendingSpeed = -1
    pendingBoost = -1
    pendingPower = ""
    pendingEffect = ""
  }

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
    // Effects hold different-length lists; a switch must not leave the
    // selection pointing past the end.
    if (selectedColor >= status.colors.length) selectedColor = 0
    // This is the read that follows a write, so it either confirms what we
    // asked for or shows that the command failed. Either way it is the truth
    // now, and the optimistic values step aside.
    if (awaitingRefresh) {
      awaitingRefresh = false
      clearPending()
    }
  }

  // Every write is an argv vector, never a shell string, so nothing read from
  // the state file can be re-tokenized.
  function apply_argv(argv) {
    if (actionProc.running) return
    actionProc.command = argv
    actionProc.running = true
  }

  // rootCommand is a user-editable setting (sudo wrapper, doas, ...), so these
  // build a shell string; the arguments are ours, never the state file's.
  function setPower(mode) {
    pendingPower = mode
    apply_argv(["bash", "-lc", root.rootCommand + " power " + mode])
  }

  function setBoost(percent) {
    pendingBoost = Math.round(percent)
    apply_argv(["bash", "-lc", root.rootCommand + " fan boost " + pendingBoost])
  }

  function setEffect(name) {
    pickerOpen = false
    selectedColor = 0
    pendingEffect = name
    apply_argv(["g15", "led", "effect", name])
  }

  function setSpeed(value) {
    pendingSpeed = Math.round(value)
    apply_argv(["g15", "led", "speed", String(pendingSpeed)])
  }

  // The CLI takes the whole list and enforces the per-effect min/max itself,
  // so every edit here is a rewrite of the current effect's list.
  function setColors(list) {
    apply_argv(["g15", "led", "colors", Model.colorArg(list)])
  }

  function openPicker(index) {
    selectedColor = index
    var hsv = Model.hexToHsv(status.colors[index])
    pickH = hsv.h
    pickS = hsv.s
    pickV = hsv.v
    pickerOpen = true
  }

  function commitHex(hex) {
    if (!/^#[0-9a-fA-F]{6}$/.test(hex)) return
    var list = status.colors.slice()
    if (selectedColor >= list.length) return
    if (list[selectedColor] === hex.toLowerCase()) return
    list[selectedColor] = hex
    setColors(list)
  }

  function addColor() {
    if (!canAdd) return
    var list = status.colors.slice()
    list.splice(selectedColor + 1, 0, list[selectedColor])
    selectedColor = selectedColor + 1
    setColors(list)
  }

  function removeColor() {
    if (!canRemove) return
    var list = status.colors.slice()
    list.splice(selectedColor, 1)
    selectedColor = Math.max(0, Math.min(selectedColor, list.length - 1))
    setColors(list)
  }

  function setBrightness(percent) {
    pendingBrightness = Math.round(percent)
    apply_argv(["g15", "led", "brightness", String(pendingBrightness)])
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
    // The change is in effect by the time the CLI exits, so the next read
    // already reflects it.
    onExited: {
      root.awaitingRefresh = true
      root.refresh()
    }
  }

  // hyprpicker overlays the screen and prints the color it is clicked on. The
  // shell already runs as the user, so unlike the TUI this needs no env
  // reconstruction.
  Process {
    id: pickProc
    command: ["hyprpicker", "--format=hex"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var hex = String(text || "").trim().toLowerCase()
        if (!/^#[0-9a-fA-F]{6}$/.test(hex)) return
        var hsv = Model.hexToHsv(hex)
        root.pickH = hsv.h
        root.pickS = hsv.s
        root.pickV = hsv.v
        root.commitHex(hex)
      }
    }
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
            text: "POWER & FANS"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          ButtonGroup {
            options: Model.powerOptions()
            value: root.pendingPower !== "" ? root.pendingPower : root.status.power
            foreground: root.foreground
            background: root.bar ? root.bar.background : Color.background
            accent: Color.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            focusable: false
            onChanged: function(v) { root.setPower(v) }
          }

          SliderRow {
            width: parent.width
            label: Model.fanIcon()
            minimum: 0
            maximum: 100
            step: 5
            value: root.pendingBoost >= 0 ? root.pendingBoost : root.status.boost
            suffix: "%"
            // The mode chips drive the fan curve; this is the manual boost on
            // top of it. Shown from the state file — reading the live value
            // needs root, so it tracks what was last set, not what a mode
            // change did to the fans.
            onCommitted: function(v) { root.setBoost(v) }
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

          SliderRow {
            width: parent.width
            label: "󰃟"
            minimum: 0
            maximum: 100
            step: 5
            value: root.pendingBrightness >= 0 ? root.pendingBrightness : root.status.brightness
            suffix: "%"
            // Applied on release, not on every drag tick: each write is a USB
            // control transfer to the LED controller.
            onCommitted: function(v) { root.setBrightness(v) }
          }

          ButtonGroup {
            options: Model.effectOptions()
            value: root.pendingEffect !== "" ? root.pendingEffect : root.status.effect
            foreground: root.foreground
            background: root.bar ? root.bar.background : Color.background
            accent: Color.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            focusable: false
            onChanged: function(v) { root.setEffect(v) }
          }

          SliderRow {
            width: parent.width
            visible: Model.hasSpeed(root.status.effect)
            label: "󰓅"
            minimum: 1
            maximum: 10
            step: 1
            integer: true
            value: root.pendingSpeed >= 0 ? root.pendingSpeed : root.status.speed
            onCommitted: function(v) { root.setSpeed(v) }
          }

          // ---------- Colors ----------
          Item {
            width: parent.width
            implicitHeight: Math.max(colorsHeader.implicitHeight, colorButtons.implicitHeight)

            PanelSectionHeader {
              id: colorsHeader
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "COLORS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              anchors.left: colorsHeader.right
              anchors.leftMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              // The firmware fixes how many colors each effect blends, so the
              // ceiling is worth showing next to the count.
              text: root.status.colors.length + "/" + root.status.maxColors
              color: root.foreground
              opacity: 0.5
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Row {
              id: colorButtons
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(4)

              PanelActionButton {
                iconText: "+"
                tooltipText: root.canAdd ? "Duplicate the selected color"
                                         : root.status.effect + " takes at most " + root.status.maxColors
                enabled: root.canAdd
                opacity: enabled ? 1 : 0.35
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                onClicked: root.addColor()
              }

              PanelActionButton {
                iconText: "\u2212"
                tooltipText: root.canRemove ? "Remove the selected color"
                                            : root.status.effect + " needs at least " + root.status.minColors
                enabled: root.canRemove
                opacity: enabled ? 1 : 0.35
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                onClicked: root.removeColor()
              }
            }
          }

          Flow {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.status.colors

              delegate: Rectangle {
                required property var modelData
                required property int index

                width: Style.space(30)
                height: Style.space(22)
                radius: Style.cornerRadius > 0 ? Style.space(4) : 0
                color: modelData
                border.width: index === root.selectedColor ? Math.max(2, Style.space(2)) : 1
                border.color: index === root.selectedColor
                  ? root.foreground
                  : Util.alpha(root.foreground, 0.3)

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  // Clicking the open swatch again closes the picker, so the
                  // row doubles as the picker's toggle.
                  onClicked: {
                    if (root.pickerOpen && root.selectedColor === index) root.pickerOpen = false
                    else root.openPicker(index)
                  }
                }
              }
            }
          }

          // ---------- Picker, open on a swatch click ----------
          Column {
            width: parent.width
            visible: root.pickerOpen
            spacing: Style.space(8)

            Flow {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: Model.presets()

                delegate: Rectangle {
                  required property var modelData

                  width: Style.space(18)
                  height: width
                  radius: Style.cornerRadius > 0 ? width / 2 : 0
                  color: modelData
                  border.width: 1
                  border.color: Util.alpha(root.foreground, 0.3)

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      var hsv = Model.hexToHsv(modelData)
                      root.pickH = hsv.h
                      root.pickS = hsv.s
                      root.pickV = hsv.v
                      root.commitHex(modelData)
                    }
                  }
                }
              }
            }

            SliderRow {
              width: parent.width
              label: "Hue"
              minimum: 0
              maximum: 359
              step: 1
              integer: true
              value: root.pickH
              suffix: "°"
              onLive: function(v) { root.pickH = v }
              onCommitted: function(v) { root.commitHex(root.pickHex) }
            }

            SliderRow {
              width: parent.width
              label: "Sat"
              minimum: 0
              maximum: 100
              step: 1
              integer: true
              value: root.pickS
              suffix: "%"
              onLive: function(v) { root.pickS = v }
              onCommitted: function(v) { root.commitHex(root.pickHex) }
            }

            SliderRow {
              width: parent.width
              label: "Val"
              minimum: 0
              maximum: 100
              step: 1
              integer: true
              value: root.pickV
              suffix: "%"
              onLive: function(v) { root.pickV = v }
              onCommitted: function(v) { root.commitHex(root.pickHex) }
            }

            Item {
              width: parent.width
              implicitHeight: Math.max(hexField.implicitHeight, pickerButtons.implicitHeight)

              Rectangle {
                id: preview
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(18)
                height: width
                radius: Style.cornerRadius > 0 ? width / 2 : 0
                color: root.pickHex
                border.width: 1
                border.color: Util.alpha(root.foreground, 0.3)
              }

              TextField {
                id: hexField
                anchors.left: preview.right
                anchors.leftMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(90)
                foreground: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                verticalPadding: Style.space(4)
                placeholderText: root.pickHex
                validator: RegularExpressionValidator { regularExpression: /#?[0-9a-fA-F]{0,6}/ }
                onAccepted: {
                  var hex = text.charAt(0) === "#" ? text : "#" + text
                  if (/^#[0-9a-fA-F]{6}$/.test(hex)) {
                    var hsv = Model.hexToHsv(hex)
                    root.pickH = hsv.h
                    root.pickS = hsv.s
                    root.pickV = hsv.v
                    root.commitHex(hex)
                    text = ""
                  }
                }
              }

              Row {
                id: pickerButtons
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(6)

                Button {
                  text: "Screen"
                  tooltipText: "Pick a color from the screen (hyprpicker)"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  horizontalPadding: Style.spacing.controlPaddingX
                  verticalPadding: Style.space(4)
                  bordered: true
                  onClicked: if (!pickProc.running) pickProc.running = true
                }

                Button {
                  text: "Done"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  horizontalPadding: Style.spacing.controlPaddingX
                  verticalPadding: Style.space(4)
                  bordered: true
                  onClicked: root.pickerOpen = false
                }
              }
            }
          }
        }

      }
    }
  }

  // A labeled slider with its value at the end. `onLive` fires while dragging
  // (the picker previews with it); `onCommitted` fires on release only, so one
  // gesture is one USB write.
  component SliderRow: Item {
    id: sliderRow

    property string label: ""
    property string suffix: ""
    property real value: 0
    property real minimum: 0
    property real maximum: 100
    property real step: 1
    property bool integer: false

    signal live(real value)
    signal committed(real value)

    implicitHeight: Math.max(sliderLabel.implicitHeight, slider.implicitHeight, sliderValue.implicitHeight)

    Text {
      id: sliderLabel
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(30)
      text: sliderRow.label
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    PanelSlider {
      id: slider
      anchors.left: sliderLabel.right
      anchors.leftMargin: Style.space(4)
      anchors.right: sliderValue.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      bar: root.bar
      minimum: sliderRow.minimum
      maximum: sliderRow.maximum
      step: sliderRow.step
      integer: sliderRow.integer
      value: sliderRow.value
      onMoved: function(v) { sliderRow.live(v) }
      onReleased: function(v) { sliderRow.committed(v) }
    }

    Text {
      id: sliderValue
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(34)
      horizontalAlignment: Text.AlignRight
      text: Math.round(slider.liveValue) + sliderRow.suffix
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
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
