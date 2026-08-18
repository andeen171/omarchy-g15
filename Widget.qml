import QtQuick
import Quickshell.Io
import qs.Ui

// Bar widget for g15. It only shells out to `g15 waybar`, which reads hwmon
// and ~/.config/g15/state — never the USB LED device, so a bar poll can never
// wedge the AW-ELC controller (see protocol.md).
BarWidget {
  id: root
  moduleName: "andeen171.g15"

  property string label: ""
  property string tip: ""

  visible: label !== ""
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: poll
    command: ["g15", "waybar"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) return
        try {
          var json = JSON.parse(raw)
          root.label = String(json.text || "")
          root.tip = String(json.tooltip || "")
        } catch (e) {
          // ponytail: plain text is a valid waybar module output too
          root.label = raw
          root.tip = ""
        }
      }
    }
  }

  Timer {
    interval: Math.max(1, root.setting("interval", 5)) * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!poll.running) poll.running = true
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.label
    tooltipText: root.tip
    onPressed: if (root.bar) root.bar.run(root.setting("onClick", "omarchy-launch-or-focus-tui g15-tui"))
  }
}
