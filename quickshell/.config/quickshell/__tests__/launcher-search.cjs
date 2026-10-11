const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const source = fs.readFileSync(path.join(__dirname, "../LauncherSearch.js"), "utf8")
    .replace(/^\.pragma library\s*/, "");
const search = vm.createContext({});
vm.runInContext(source, search);
assert(search.score("Firefox", "firefox") > search.score("Firefox Developer", "firefox"));
assert(search.score("Firefox", "ffx") >= 0);
assert.equal(search.score("Firefox", "kitty"), -1);
const rows = [
    { title: "Firefox", category: "Apps" },
    { title: "Firefox documentation", category: "Windows" },
    { title: "Clipboard history", category: "Actions" },
];
assert.equal(search.filterRows({ rows, query: "fire", scope: "Windows" })[0].category, "Windows");
assert.equal(search.filterRows({ rows, query: "clipboard", scope: "All" })[0].category, "Actions");
assert.equal(search.filterRows({ rows, query: "missing", scope: "All" }).length, 0);
process.stdout.write("Launcher search tests passed\n");
