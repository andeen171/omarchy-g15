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

const live = parseStatus(execFileSync("g15", ["status"]).toString())
assert.ok(live, "g15 status must print one JSON object")
assert.ok(live.sensors, "hwmon unreadable — is alienware_wmi/dell_smm loaded?")
assert.ok(live.cpu > 0 && live.gpu > 0, "temps must be non-zero")
assert.ok(tempFraction(30) === 0 && tempFraction(95) === 1, "meter spans 30..95")
assert.ok(barText(live).includes("°"), "bar text carries the temps")

console.log("ok — " + barText(live))
