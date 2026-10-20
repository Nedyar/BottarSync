"use strict";
// Reads the JSON that the Bot'tar Sync addon writes into its saved variables
// file, WTF\Account\<ACCOUNT>\SavedVariables\BottarSync.lua.
//
// The game writes that file as Lua, so the JSON is inside a Lua string:
//     BottarSyncJSON = "{\"format\":1,...}"
// This module finds that line, undoes the Lua string escapes and parses the
// JSON. No dependencies (Node.js 14 or later).
//
//     const { readBottarSync } = require("./bottarsync");
//     const data = readBottarSync("C:/.../SavedVariables/BottarSync.lua");
//     // data.guilds[0].members ... (see README.md); null when the file has
//     // no JSON yet (export off, or never written)
//
// From the command line: node bottarsync.js <file> [--pretty]

const fs = require("fs");

const VARIABLE = "BottarSyncJSON";

// Lua 5.1 escapes: \a \b \f \n \r \t \v \\ \" \' \<newline> and \ddd.
const NAMED_ESCAPES = { a: 7, b: 8, f: 12, n: 10, r: 13, t: 9, v: 11, "\\": 92, '"': 34, "'": 39 };

// Reads the quoted Lua string that starts at text[start] (text holds one
// character per byte). Returns its bytes.
function readQuoted(text, start) {
  const quote = text[start];
  const bytes = [];
  let i = start + 1;
  for (;;) {
    if (i >= text.length) throw new Error("unfinished Lua string");
    const c = text[i];
    if (c === quote) return Buffer.from(bytes);
    if (c === "\n" || c === "\r") throw new Error("line break inside a Lua string");
    if (c !== "\\") {
      bytes.push(text.charCodeAt(i));
      i += 1;
      continue;
    }
    const e = text[i + 1];
    if (e in NAMED_ESCAPES) {
      bytes.push(NAMED_ESCAPES[e]);
      i += 2;
    } else if (e === "\n" || e === "\r") {
      // A backslash before a real line break stands for that line break.
      bytes.push(10);
      i += 2;
      if ((text[i] === "\n" || text[i] === "\r") && text[i] !== e) i += 1;
    } else if (e >= "0" && e <= "9") {
      let digits = "";
      i += 1;
      while (digits.length < 3 && text[i] >= "0" && text[i] <= "9") {
        digits += text[i];
        i += 1;
      }
      const value = parseInt(digits, 10);
      if (value > 255) throw new Error("bad Lua escape \\" + digits);
      bytes.push(value);
    } else {
      throw new Error("bad Lua escape \\" + e);
    }
  }
}

// Reads a long Lua string, [[...]] or [==[...]==], that starts at text[start].
function readLong(text, start) {
  const open = /^\[(=*)\[/.exec(text.slice(start, start + 64));
  if (!open) throw new Error("not a Lua string");
  let from = start + open[0].length;
  // A line break right after the opening bracket is not part of the string.
  if (text[from] === "\r" && text[from + 1] === "\n") from += 2;
  else if (text[from] === "\n" || text[from] === "\r") from += 1;
  const close = "]" + open[1] + "]";
  const to = text.indexOf(close, from);
  if (to < 0) throw new Error("unfinished Lua string");
  return Buffer.from(text.slice(from, to), "latin1");
}

// The JSON text in the contents of a saved variables file (a Buffer or a
// string), parsed. null when the variable is missing or nil.
function extractJSON(contents) {
  const text = Buffer.isBuffer(contents) ? contents.toString("latin1") : Buffer.from(contents, "utf8").toString("latin1");
  const pattern = new RegExp("(?:^|\\n)" + VARIABLE + "\\s*=\\s*", "g");
  let match;
  let last = null;
  while ((match = pattern.exec(text)) !== null) last = match;
  if (!last) return null;
  const start = last.index + last[0].length;
  const c = text[start];
  let bytes;
  if (c === '"' || c === "'") bytes = readQuoted(text, start);
  else if (c === "[") bytes = readLong(text, start);
  else if (text.startsWith("nil", start)) return null;
  else throw new Error(VARIABLE + " is not a string");
  return JSON.parse(bytes.toString("utf8"));
}

function readBottarSync(path) {
  return extractJSON(fs.readFileSync(path));
}

module.exports = { readBottarSync, extractJSON };

if (require.main === module) {
  const args = process.argv.slice(2);
  const file = args.find((a) => !a.startsWith("--"));
  if (!file) {
    console.error("usage: node bottarsync.js <BottarSync.lua> [--pretty]");
    process.exit(2);
  }
  try {
    const data = readBottarSync(file);
    if (data === null) {
      console.error("no " + VARIABLE + " in " + file);
      process.exit(1);
    }
    process.stdout.write(JSON.stringify(data, null, args.includes("--pretty") ? 2 : 0) + "\n");
  } catch (error) {
    console.error(error.message);
    process.exit(1);
  }
}
