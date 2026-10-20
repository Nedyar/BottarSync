"""Reads the JSON that the Bot'tar Sync addon writes into its saved variables
file, WTF\\Account\\<ACCOUNT>\\SavedVariables\\BottarSync.lua.

The game writes that file as Lua, so the JSON is inside a Lua string:
    BottarSyncJSON = "{\\"format\\":1,...}"
This module finds that line, undoes the Lua string escapes and parses the
JSON. Standard library only (Python 3.8 or later). Same behaviour as
bottarsync.js.

    from bottarsync import read_bottarsync
    data = read_bottarsync(r"C:\\...\\SavedVariables\\BottarSync.lua")
    # data["guilds"][0]["members"] ... (see README.md); None when the file
    # has no JSON yet (export off, or never written)

From the command line: python bottarsync.py <file> [--pretty]
"""
import json
import re
import sys

VARIABLE = b"BottarSyncJSON"

# Lua 5.1 escapes: \a \b \f \n \r \t \v \\ \" \' \<newline> and \ddd.
NAMED_ESCAPES = {
    ord("a"): 7, ord("b"): 8, ord("f"): 12, ord("n"): 10, ord("r"): 13, ord("t"): 9, ord("v"): 11,
    ord("\\"): 92, ord('"'): 34, ord("'"): 39,
}
LINE_BREAKS = (10, 13)
DIGITS = range(48, 58)


def _read_quoted(data, start):
    quote = data[start]
    out = bytearray()
    i = start + 1
    while True:
        if i >= len(data):
            raise ValueError("unfinished Lua string")
        c = data[i]
        if c == quote:
            return bytes(out)
        if c in LINE_BREAKS:
            raise ValueError("line break inside a Lua string")
        if c != 92:
            out.append(c)
            i += 1
            continue
        e = data[i + 1] if i + 1 < len(data) else None
        if e in NAMED_ESCAPES:
            out.append(NAMED_ESCAPES[e])
            i += 2
        elif e in LINE_BREAKS:
            # A backslash before a real line break stands for that line break.
            out.append(10)
            i += 2
            if i < len(data) and data[i] in LINE_BREAKS and data[i] != e:
                i += 1
        elif e in DIGITS:
            i += 1
            digits = b""
            while len(digits) < 3 and i < len(data) and data[i] in DIGITS:
                digits += bytes([data[i]])
                i += 1
            value = int(digits)
            if value > 255:
                raise ValueError("bad Lua escape \\" + digits.decode())
            out.append(value)
        else:
            raise ValueError("bad Lua escape")


def _read_long(data, start):
    match = re.match(rb"\[(=*)\[", data[start:start + 64])
    if not match:
        raise ValueError("not a Lua string")
    begin = start + match.end()
    # A line break right after the opening bracket is not part of the string.
    if data[begin:begin + 2] == b"\r\n":
        begin += 2
    elif data[begin:begin + 1] in (b"\n", b"\r"):
        begin += 1
    close = b"]" + match.group(1) + b"]"
    end = data.find(close, begin)
    if end < 0:
        raise ValueError("unfinished Lua string")
    return data[begin:end]


def extract_json(data):
    """The JSON in the contents (bytes) of a saved variables file, parsed.
    None when the variable is missing or nil."""
    if isinstance(data, str):
        data = data.encode("utf-8")
    matches = list(re.finditer(rb"(?:^|\n)" + VARIABLE + rb"\s*=\s*", data))
    if not matches:
        return None
    start = matches[-1].end()
    c = data[start:start + 1]
    if c in (b'"', b"'"):
        raw = _read_quoted(data, start)
    elif c == b"[":
        raw = _read_long(data, start)
    elif data.startswith(b"nil", start):
        return None
    else:
        raise ValueError("BottarSyncJSON is not a string")
    return json.loads(raw.decode("utf-8"))


def read_bottarsync(path):
    with open(path, "rb") as file:
        return extract_json(file.read())


if __name__ == "__main__":
    files = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not files:
        print("usage: python bottarsync.py <BottarSync.lua> [--pretty]", file=sys.stderr)
        sys.exit(2)
    try:
        result = read_bottarsync(files[0])
    except (OSError, ValueError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
    if result is None:
        print("no BottarSyncJSON in " + files[0], file=sys.stderr)
        sys.exit(1)
    json.dump(result, sys.stdout, ensure_ascii=False, indent=2 if "--pretty" in sys.argv else None)
    print()
