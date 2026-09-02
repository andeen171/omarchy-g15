// node Model.test.js — guards the `g15 status` JSON contract Panel.qml reads.
// Needs the g15 CLI on PATH; that is the contract being checked.
const fs = require("fs")
const assert = require("assert")
const { execFileSync } = require("child_process")

eval(fs.readFileSync(__dirname + "/Model.js", "utf8"))

// Garbage never replaces the last good sample.
assert.strictEqual(parseStatus("not json"), null)
assert.strictEqual(parseStatus(""), null)
assert.strictEqual(parseStatus("[1,2]").sensors, false)

// A hostile state file cannot smuggle a color into the swatch.
assert.strictEqual(parseStatus('{"color":"red; rm -rf /"}').color, "#ffffff")
assert.strictEqual(parseStatus('{"brightness":900}').brightness, 100)
assert.strictEqual(parseStatus('{"boost":-5}').boost, 0)
assert.deepStrictEqual(parseStatus('{"colors":["ff0000","nope"]}').colors, ["#ff0000"])

// Bounds: an oversized or overlong producer cannot reach the bar.
assert.strictEqual(parseStatus('{"sensors":true}'.padEnd(70000, " ")), null)
assert.strictEqual(parseStatus('{"power":"' + "x".repeat(500) + '"}').power, "unknown")
assert.strictEqual(parseStatus('{"effect":"a b"}').effect, "static")
assert.strictEqual(
  parseStatus('{"colors":' + JSON.stringify(Array(200).fill("ff0000")) + "}").colors.length,
  64
)
assert.strictEqual(parseStatus('{"maxColors":9999}').maxColors, 64)

// The privileged controls key off this compare, so it has to order right.
assert.strictEqual(atLeast("0.3.1", minCliVersion), true)
assert.strictEqual(atLeast("0.3.0", minCliVersion), false)
assert.strictEqual(atLeast("0.3.10", "0.3.9"), true)
assert.strictEqual(atLeast("1.0", "0.3.1"), true)
assert.strictEqual(atLeast("", minCliVersion), false)
assert.strictEqual(atLeast(parseStatus("{}").version, minCliVersion), false)

// HSV is what the picker edits, hex is what the CLI takes.
assert.strictEqual(hsvToHex(0, 100, 100), "#ff0000")
assert.strictEqual(hsvToHex(210, 100, 100), "#0080ff")
assert.strictEqual(hsvToHex(0, 0, 100), "#ffffff")
var hsv = hexToHsv("#0080ff")
assert.ok(Math.abs(hsv.h - 210) < 0.5 && hsv.s === 100 && hsv.v === 100)
assert.strictEqual(colorArg(["#ff0000", "#00ff00"]), "ff0000,00ff00")

const live = parseStatus(execFileSync("g15", ["status"]).toString())
assert.ok(live, "g15 status must print one JSON object")
assert.ok(
  atLeast(live.version, minCliVersion),
  "g15 on PATH is " + live.version + ", need " + minCliVersion + " for the pkexec narrowing"
)
assert.ok(live.sensors, "hwmon unreadable — is alienware_wmi/dell_smm loaded?")
assert.ok(live.cpu > 0 && live.gpu > 0, "temps must be non-zero")
assert.ok(tempFraction(30) === 0 && tempFraction(95) === 1, "meter spans 30..95")
assert.ok(live.colors.length >= live.minColors, "the list respects the effect's minimum")
assert.ok(live.colors.length <= live.maxColors, "the list respects the effect's maximum")
assert.ok(live.speed >= 1 && live.speed <= 10, "speed is 1-10")
// Every swatch must survive the round trip the picker puts it through.
live.colors.forEach(function (c) {
  var hsv = hexToHsv(c)
  assert.strictEqual(hsvToHex(hsv.h, hsv.s, hsv.v), c, "round trip broke " + c)
})
assert.ok(barText(live).includes("°"), "bar text carries the temps")

console.log("ok — " + barText(live))
