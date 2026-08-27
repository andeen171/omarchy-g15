// Parsing and formatting for the G15 bar widget. The JSON contract with
// `g15 status` lives here so Panel.qml stays layout.

function emptyStatus() {
  return {
    sensors: false,
    cpu: 0, gpu: 0, fan1: 0, fan2: 0,
    power: "unknown",
    boost: 0,
    effect: "static",
    brightness: 100,
    speed: 5,
    color: "#ffffff",
    colors: ["#ffffff"],
    minColors: 1,
    maxColors: 1
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
  s.boost = Math.max(0, Math.min(100, num(json.boost)))
  s.brightness = Math.max(0, Math.min(100, num(json.brightness)))
  s.speed = Math.max(1, Math.min(10, num(json.speed) || 5))
  s.color = isHex(json.color) ? "#" + json.color : "#ffffff"
  s.minColors = Math.max(1, num(json.minColors) || 1)
  s.maxColors = Math.max(s.minColors, num(json.maxColors) || s.minColors)
  s.colors = (Array.isArray(json.colors) ? json.colors : [])
    .filter(isHex)
    .map(function (c) { return "#" + String(c).toLowerCase() })
  if (s.colors.length === 0) s.colors = [s.color]
  return s
}

function isHex(v) {
  return /^[0-9a-fA-F]{6}$/.test(String(v))
}

// The CLI takes the list bare and comma-separated: `g15 led colors ff00aa,00ffaa`.
function colorArg(colors) {
  return colors.map(function (c) { return String(c).replace("#", "") }).join(",")
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

// ---------------------------------------------------------------- picker
//
// The same nine presets the TUI offers on its picker's first row, so a color
// named there is the same color here.
function presets() {
  return ["#ffffff", "#ff0000", "#ff8800", "#ffff00", "#00ff00",
          "#00ffff", "#0066ff", "#8800ff", "#ff00aa"]
}

// HSV is what the picker's three sliders edit; the wire format is hex. Ported
// from the TUI's conversions so both agree on what "hue 210" looks like.
function hexToHsv(hex) {
  var v = parseInt(String(hex).replace("#", ""), 16)
  if (!isFinite(v)) return { h: 0, s: 0, v: 100 }
  var r = ((v >> 16) & 255) / 255, g = ((v >> 8) & 255) / 255, b = (v & 255) / 255
  var max = Math.max(r, g, b), min = Math.min(r, g, b), d = max - min
  var h = 0
  if (d !== 0) {
    if (max === r) h = 60 * (((g - b) / d) % 6)
    else if (max === g) h = 60 * ((b - r) / d + 2)
    else h = 60 * ((r - g) / d + 4)
  }
  if (h < 0) h += 360
  // Unrounded: rounding here costs up to a whole step per channel, so opening
  // the picker on a color and nudging one slider would silently rewrite the
  // other two. The sliders snap to integers on drag; the display rounds.
  return { h: h % 360, s: (max === 0 ? 0 : d / max) * 100, v: max * 100 }
}

function hsvToHex(h, s, v) {
  s = s / 100
  v = v / 100
  var c = v * s
  var x = c * (1 - Math.abs(((h / 60) % 2) - 1))
  var m = v - c
  var rgb
  switch (Math.floor(h / 60) % 6) {
  case 0: rgb = [c, x, 0]; break
  case 1: rgb = [x, c, 0]; break
  case 2: rgb = [0, c, x]; break
  case 3: rgb = [0, x, c]; break
  case 4: rgb = [x, 0, c]; break
  default: rgb = [c, 0, x]
  }
  return "#" + rgb.map(function (n) {
    return ("0" + Math.round((n + m) * 255).toString(16)).slice(-2)
  }).join("")
}

// Static holds one color, so its speed is meaningless — the firmware only uses
// the tempo for the animated effects.
function hasSpeed(effect) {
  return effect !== "static"
}
