// Runs JavaScript from stdin against the GitHub plugin's logic libraries
// (GitHubLogic.js, GitHubMarkdown.js: QML `.pragma library` scripts), so
// tests exercise the shipped functions directly:
//
//   node github_logic.js <library.js>... [args...] <script
//
// The script runs with `L` bound to every library's names (one namespace),
// `style` to a Markdown style (GitHubMarkdown.js) whose colors are letters,
// `args` to the remaining arguments, and `require`, and what it returns
// prints as JSON.
"use strict";

const fs = require("fs");
const path = require("path");

// A library's top-level functions and variables; the scripts it imports
// (`.import "Other.js" as Other`) load the same way, next to it.
function load(library) {
    const imports = {};
    const source = fs.readFileSync(library, "utf8").replace(/^\.pragma library\s*$/m, "").replace(/^\.import\s+"([^"]+\.js)"\s+as\s+(\w+)\s*$/gm, (m, file, name) => {
        imports[name] = load(path.join(path.dirname(library), file));
        return "";
    });
    const names = new Set();
    for (const m of source.matchAll(/^(?:function\s+(\w+)|var\s+(\w+))/gm))
        names.add(m[1] || m[2]);
    return new Function(...Object.keys(imports), source + "\nreturn {" + [...names].join(", ") + "};")(...Object.values(imports));
}

const argv = process.argv.slice(2);
const libraries = [];
while (argv.length > 0 && argv[0].endsWith(".js"))
    libraries.push(argv.shift());
const L = Object.assign({}, ...libraries.map(load));
const style = {
    "link": "L",
    "codeFont": "m",
    "codeSize": 12,
    "codeBackground": "B",
    "codeText": "T",
    "keyBackground": "K",
    "mark": "Y"
};
const result = new Function("L", "style", "args", "require", fs.readFileSync(0, "utf8"))(L, style, argv, require);
process.stdout.write(JSON.stringify(result) + "\n");
