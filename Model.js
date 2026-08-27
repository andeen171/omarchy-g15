// Parsing and formatting for the G15 bar widget. The JSON contract with
// `g15 status` lives here so Panel.qml stays layout.

function emptyStatus() {
  return {
    sensors: false,
    cpu: 0, gpu: 0, fan1: 0, fan2: 0,
    power: "unknown",
    effect: "static",
    brightness: 100,
    color: "#ffffff"
  }
}

// `g15 status` prints one JSON object. Anything else (g15 missing, sensors
// gone) leaves the last good sample in place — see Panel.qml's apply().
function parseStatus(raw) {
  var s = emptyStatus()
  var json
  try {
    json = JSON.parse(String(raw || "").trim())
  } catch (e) {
    return null
  }
  if (!json || typeof json !== "object") return null

  s.sensors = json.sensors === true
  s.cpu = num(json.cpu)
  s.gpu = num(json.gpu)
  s.fan1 = num(json.fan1)
  s.fan2 = num(json.fan2)
  s.power = json.power ? String(json.power) : "unknown"
  s.effect = json.effect ? String(json.effect) : "static"
  s.brightness = Math.max(0, Math.min(100, num(json.brightness)))
  s.color = /^[0-9a-fA-F]{6}$/.test(String(json.color)) ? "#" + json.color : "#ffffff"
  return s
}

function num(v) {
  var n = Number(v)
  return isFinite(n) ? Math.round(n) : 0
}

// Nerd Font glyphs: chip for CPU, GPU card, fan, keyboard for the widget.
function cpuIcon() { return "󰍛" }
function gpuIcon() { return "󰢮" }
function fanIcon() { return "󰈐" }
function widgetIcon() { return "󰌌" }

function barText(s) {
  if (!s.sensors) return widgetIcon()
  return cpuIcon() + " " + s.cpu + "°  " + gpuIcon() + " " + s.gpu + "°"
}

function tooltip(s) {
  if (!s.sensors) return "sensors unavailable"
  return "CPU " + s.cpu + "°C — fan " + rpmText(s.fan1) + "\n"
       + "GPU " + s.gpu + "°C — fan " + rpmText(s.fan2) + "\n"
       + "power: " + s.power
}

function rpmText(rpm) {
  return rpm > 0 ? rpm + " rpm" : "—"
}

// Idle sits near 40 °C and thermal throttling starts around 95 °C, so the
// meter spans 30..95 rather than 0..100 — otherwise it never leaves the left
// third and shows nothing.
function tempFraction(t) {
  return Math.max(0, Math.min(1, (t - 30) / 65))
}

function isHot(t) {
  return t >= 85
}

function powerOptions() {
  return [
    { value: "quiet", label: "Quiet", tooltip: "Lowest fan noise" },
    { value: "balanced", label: "Balanced", tooltip: "Default profile" },
    { value: "performance", label: "Perf", tooltip: "Performance profile" },
    { value: "gmode", label: "G-Mode", tooltip: "Max fans and power (the G key)" }
  ]
}

function effectOptions() {
  return [
    { value: "static", label: "Static", tooltip: "Solid saved color" },
    { value: "pulse", label: "Pulse", tooltip: "Breathe the saved color" },
    { value: "morph", label: "Morph", tooltip: "Fade between two saved colors" },
    { value: "cycle", label: "Cycle", tooltip: "Morph through the spectrum" },
    { value: "rainbow", label: "Rain", tooltip: "Rainbow across the four zones" }
  ]
}
