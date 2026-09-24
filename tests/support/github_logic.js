// Runs JavaScript from stdin against the GitHub plugin's logic library
// (GitHubLogic.js, a QML `.pragma library` script), so tests exercise the
// shipped functions directly:
//
//   node github_logic.js <GitHubLogic.js> [args...] <script
//
// The script runs with `L` bound to the library, `args` to the remaining
// arguments, and `require`, and what it returns prints as JSON.
"use strict";

const fs = require("fs");

const [library, ...args] = process.argv.slice(2);
const source = fs.readFileSync(library, "utf8").replace(/^\.pragma library\s*$/m, "");
const names = new Set();
for (const m of source.matchAll(/^(?:function\s+(\w+)|var\s+(\w+))/gm))
    names.add(m[1] || m[2]);
const L = new Function(source + "\nreturn {" + [...names].join(", ") + "};")();
const result = new Function("L", "args", "require", fs.readFileSync(0, "utf8"))(L, args, require);
process.stdout.write(JSON.stringify(result) + "\n");
