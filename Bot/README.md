# Bot'tar Sync: the file for Bot'tar

This document is for whoever programs Bot'tar. It explains where the addon
leaves the guild's data, when the data is updated, how to read it and what it
contains.

## Where the file is

On the bot admin's computer (or on any computer with the addon and the export
turned on, which it is by default):

```
World of Warcraft\_classic_beta_\WTF\Account\<ACCOUNT>\SavedVariables\BottarSync.lua
```

`<ACCOUNT>` is the WoW account's folder, for example `12345678#1`. If the
admin plays on several WoW accounts, each one has its own file.

## Why there is JSON inside a `.lua` file

A WoW addon cannot create files. All the game lets it keep are its *saved
variables*, and the game writes them as Lua code. So the addon puts the whole
JSON text into a Lua string:

```lua
BottarSyncDB = {
	...the addon's internal data, do not use it...
}
BottarSyncJSON = "{\"format\":1,\"addon\":\"Bot'tar Sync\",...}"
```

To get the JSON:

1. Find the line that starts with `BottarSyncJSON = `.
2. Undo the Lua string escapes (`\"`, `\\`, `\n`, `\ddd`...).
3. Parse the result as JSON (UTF-8).

That is already done and tested:

- **Node.js**: [bottarsync.js](bottarsync.js), no dependencies. The addon's
  tests run it and check that it returns exactly the JSON the addon wrote. It
  also read the first file the game wrote.

  ```js
  const { readBottarSync } = require("./bottarsync");
  const data = readBottarSync("C:/.../SavedVariables/BottarSync.lua");
  if (data) console.log(data.guilds[0].members.length);
  ```

- **Python**: [bottarsync.py](bottarsync.py), standard library only. It does
  the same as the Node version, but **it has never been run**: the computer
  it was written on has no Python. If you use it, try it on a real file first.

  ```python
  from bottarsync import read_bottarsync
  data = read_bottarsync(r"C:\...\SavedVariables\BottarSync.lua")
  ```

From the command line: `node bottarsync.js "<path>\BottarSync.lua" --pretty`.

Both return `null`/`None` when the file exists but holds no JSON (for
example, with the export turned off by `/bottar export off`).

## When it is updated

The game only writes the file when the admin:

- logs out or quits the game,
- reloads the interface (`/reload`, or `/bottar save`, which does the same).

While the admin plays, the file **does not change**, even when the addon
already holds newer data. If the game crashes, the file is not written.

Advice for the bot:

- **Watch the file's modification time** and read it again when it changes.
- Use `generatedAt` to know how old the data is.
- **Try again on failure.** The game may be writing the file at that very
  moment; a parse error usually means you read it half-written. Wait a few
  seconds and retry.

The game writes the file with Windows line endings (`\r\n`), escapes only `\"`
and `\\` inside the JSON string and leaves UTF-8 text as it is. The readers
also accept every other Lua 5.1 escape.

## How the data gets there

- Each member with the addon shares their own characters with the guild
  through hidden game messages.
- When a client logs in, whoever is online sends it what it is missing. So the
  admin also gets the data of members they never see online, as long as
  someone with the addon is online when the admin logs in.
- The admin's client reads the full guild roster (rank, note, level, last time
  online) straight from the game, so it includes members without the addon.
- Only IDs travel between clients. **Names** (classes, races, professions,
  recipes, talents and items) **are in the language of the admin's client**
  (the `locale` field).

## Format (version 1)

All times are Unix seconds (UTC), from the game server's clock. Unknown
fields are `null`, but they are always there, in the same order.

If the format ever changes in a way that breaks readers, `format` becomes 2.
New fields may be **added** without changing `format`, so the bot should
ignore fields it does not know.

### Root

| Field | Type | Meaning |
|---|---|---|
| `format` | number | Format version: `1`. |
| `addon` | text | `"Bot'tar Sync"`. |
| `addonVersion` | text | Version of the addon that wrote the file, e.g. `"0.1.0"`. |
| `generatedAt` | number | When the file was written (Unix). |
| `generatedAtUtc` | text | The same in ISO 8601, e.g. `"2026-10-20T21:30:00Z"`. |
| `locale` | text | Language of the client that wrote it (`esES`, `enUS`...); names are in that language. |
| `exportedBy` | object | `name`, `realm` and `guid` of the character that wrote it. |
| `guilds` | list | One entry per guild the client knows, sorted by name. Usually just one; guilds of the admin's alts show up too. |

### Guild (`guilds[]`)

| Field | Type | Meaning |
|---|---|---|
| `name` | text | Guild name. |
| `rosterUpdatedAt` | number or `null` | When the guild roster was read. `null` if this client has never read it (then `members` only has the addon's users). |
| `memberCount` | number | How many members are in `members`. |
| `membersWithAddon` | number | How many of them have addon data. |
| `members` | list | Every member of the guild roster, sorted by name. |

Members who leave the guild disappear from `members` at the next roster read.

### Member (`members[]`)

Each character is a member of its own; alts are not grouped. Identify
characters by their **`guid`**, which never changes. WoW Forever names have a
space ("First Last") and no realm.

| Field | Type | Meaning |
|---|---|---|
| `guid` | text | The character's unique ID, e.g. `"Player-1234-0ABCDEF0"`. |
| `name` | text | Name, as the guild roster shows it. |
| `realm` | text or `null` | Realm. Only known with the addon. |
| `level` | number or `null` | Level. |
| `class` | object or `null` | `id` (classID), `token` (`"HUNTER"`, `"WARRIOR"`...) and `name` (translated). Without the addon, `id` and `name` can be `null`. |
| `race` | object or `null` | `id` (raceID), `token` (`"NightElf"`...) and `name`. Only with the addon. |
| `sex` | text or `null` | `"male"` or `"female"`. Only with the addon. |
| `faction` | text or `null` | `"Alliance"`, `"Horde"` or `"Neutral"`. Only with the addon. |
| `inRoster` | boolean | `true` when the character is in the guild roster. |
| `rank` | object or `null` | `index` (0 = guild master, then 1, 2...) and `name`. |
| `note` | text or `null` | The public note from the guild roster. The officer note is never exported. |
| `online` | boolean or `null` | Online when the roster was read. |
| `lastOnline` | number or `null` | Last time online (Unix). The game only gives how long ago in years, months, days and hours, so it is **approximate** (to the hour). When online, it equals `generatedAt`. |
| `hasAddon` | boolean | Whether there is addon data for this character. When `false`, everything below is `null`. |
| `updatedAt` | number or `null` | Last change to their addon data (Unix). |
| `addonVersion` | text or `null` | The version of the addon they use. |
| `itemLevel` | number or `null` | Average item level of the equipped items, with decimals. |
| `professions` | list or `null` | See below. |
| `talents` | object or `null` | See below. `null` until they could be read, e.g. for characters that have no talents yet. |
| `equipment` | list or `null` | See below. |

### Profession (`professions[]`)

In the character sheet's order: main professions, first aid, fishing, cooking.

| Field | Type | Meaning |
|---|---|---|
| `id` | number | Skill line: 165 Leatherworking, 171 Alchemy, 164 Blacksmithing, 186 Mining... |
| `name` | text or `null` | Translated name. |
| `rank` / `maxRank` | number | Current and maximum skill, e.g. 275 / 300. |
| `recipes` | list or `null` | Learned recipes: `id` (the recipe's spell ID), `name` and `itemId` (the item it makes, or `null`, e.g. for enchants). The empty list `[]` is a profession without recipes (Skinning, Herbalism...). `null` means they have not been read yet: the player has to open that profession's window once. |

### Talents (`talents`)

| Field | Type | Meaning |
|---|---|---|
| `activeSpec` | number | The active spec (1 or 2, with dual spec). |
| `specCount` | number | How many specs the character has (1 or 2). |
| `unspentPoints` | number | Points not spent. |
| `treeId` | number or `null` | ID of the class's talent tree. |
| `specs` | list | One entry per spec. |

Each `specs[]`:

| Field | Type | Meaning |
|---|---|---|
| `group` | number | 1 or 2. |
| `active` | boolean | Whether it is the active one. |
| `summary` | text | Points per tab, e.g. `"31/20/0"`. |
| `tabs` | list | The tabs in order: `index`, `name` and `pointsSpent`. |
| `talents` | list | Only **learned** talents, sorted by tab, row and column. |

Each talent: `tab` (tab number), `tabName`, `row` and `column` (from 1),
`name`, `spellId`, `nodeId`, `rank`, `maxRank`, and `posX`/`posY` (position in
the tree, in the game's units).

> The game gives no rows or columns, only positions. The addon works them out
> from the positions of all the talents of the tab; `posX`/`posY` are there
> too in case a layout does not fit.

### Equipment (`equipment[]`)

Only slots with something equipped.

| Field | Type | Meaning |
|---|---|---|
| `slot` | number | Game slot: 1 head, 2 neck, 3 shoulder, 4 shirt, 5 chest, 6 waist, 7 legs, 8 feet, 9 wrist, 10 hands, 11-12 rings, 13-14 trinkets, 15 back, 16 main hand, 17 off hand, 18 ranged, 19 tabard. |
| `slotName` | text | `head`, `neck`, `shoulder`, `shirt`, `chest`, `waist`, `legs`, `feet`, `wrist`, `hands`, `finger1`, `finger2`, `trinket1`, `trinket2`, `back`, `mainHand`, `offHand`, `ranged`, `tabard`. |
| `itemId` | number | Item ID. |
| `name` | text or `null` | Name, with its random suffix ("... of the Eagle") if it has one. `null` if the admin's client had not loaded the item yet when it wrote the file. |
| `quality` | number or `null` | Quality: 0 poor, 1 common, 2 uncommon, 3 rare, 4 epic, 5 legendary. |
| `itemLevel` | number or `null` | Item level. |
| `enchantId` | number or `null` | Enchant ID, if any. |
| `itemString` | text | The game's full item string (`item:ID:enchant:gems...:suffix:...`), without the fields that change on their own. On WoW Forever random suffixes usually come as bonus IDs, and crafted items end with the GUID of whoever crafted them. |

## Example

The addon's tests made this example, so the names are test names
(`Skill165`, `Spell40101`, `Item 16939`); in the game they are the real ones.
Alice's second spec is cut short.

```json
{
  "format": 1,
  "addon": "Bot'tar Sync",
  "addonVersion": "0.1.0",
  "generatedAt": 1760000305,
  "generatedAtUtc": "2025-10-09T08:58:25Z",
  "locale": "enUS",
  "exportedBy": { "name": "Carol White", "realm": "TestRealm", "guid": "Player-1-00000002" },
  "guilds": [
    {
      "name": "Test Guild",
      "rosterUpdatedAt": 1760000245,
      "memberCount": 2,
      "membersWithAddon": 1,
      "members": [
        {
          "guid": "Player-1-00000001",
          "name": "Alice Smith",
          "realm": "TestRealm",
          "level": 60,
          "class": { "id": 3, "token": "HUNTER", "name": "Hunter" },
          "race": { "id": 4, "token": "NightElf", "name": "Night Elf" },
          "sex": "female",
          "faction": "Alliance",
          "inRoster": true,
          "rank": { "index": 1, "name": "Officer" },
          "note": "Main",
          "online": true,
          "lastOnline": 1760000305,
          "hasAddon": true,
          "updatedAt": 1760000005,
          "addonVersion": "0.1.0",
          "itemLevel": 74.5,
          "professions": [
            {
              "id": 165, "name": "Skill165", "rank": 300, "maxRank": 300,
              "recipes": [ { "id": 19050, "name": "Spell19050", "itemId": 119050 } ]
            },
            { "id": 393, "name": "Skill393", "rank": 275, "maxRank": 300, "recipes": [] }
          ],
          "talents": {
            "activeSpec": 1,
            "specCount": 2,
            "unspentPoints": 0,
            "treeId": 773,
            "specs": [
              {
                "group": 1,
                "active": true,
                "summary": "5/5/0",
                "tabs": [
                  { "index": 1, "name": "Beast Mastery", "pointsSpent": 5 },
                  { "index": 2, "name": "Marksmanship", "pointsSpent": 5 },
                  { "index": 3, "name": "Survival", "pointsSpent": 0 }
                ],
                "talents": [
                  {
                    "tab": 1, "tabName": "Beast Mastery", "row": 1, "column": 1,
                    "name": "Spell40101", "spellId": 40101, "nodeId": 101,
                    "rank": 5, "maxRank": 5, "posX": 1200, "posY": 1500
                  },
                  {
                    "tab": 2, "tabName": "Marksmanship", "row": 1, "column": 2,
                    "name": "Spell40201", "spellId": 40201, "nodeId": 201,
                    "rank": 5, "maxRank": 5, "posX": 4800, "posY": 1500
                  }
                ]
              },
              { "group": 2, "active": false, "summary": "0/0/5", "tabs": ["..."], "talents": ["..."] }
            ]
          },
          "equipment": [
            {
              "slot": 1, "slotName": "head", "itemId": 16939, "name": "Item 16939",
              "quality": 4, "itemLevel": 76, "enchantId": 2543,
              "itemString": "item:16939:2543:0:0:0:0:0::"
            }
          ]
        },
        {
          "guid": "Player-1-00000003",
          "name": "Dan Brown",
          "realm": null,
          "level": 42,
          "class": { "id": 5, "token": "PRIEST", "name": "Priest" },
          "race": null,
          "sex": null,
          "faction": null,
          "inRoster": true,
          "rank": { "index": 4, "name": "Initiate" },
          "note": null,
          "online": false,
          "lastOnline": 1759733845,
          "hasAddon": false,
          "updatedAt": null,
          "addonVersion": null,
          "itemLevel": null,
          "professions": null,
          "talents": null,
          "equipment": null
        }
      ]
    }
  ]
}
```

## Size

About 25 KB of JSON per level 60 character with the addon (15 to 30 KB,
depending on how many recipes it knows; recipes take most of it), and about
0.4 KB per member without it. The file on disk is some 15 % bigger, because of
the escapes, plus the addon's internal data. For 50 members, all with the
addon, that is about 1.5 MB. In the tests, a guild of 900 members with 60
addon users and 600 recipes each comes to about 2 MB of JSON, built in about
0.2 s (outside the game).
