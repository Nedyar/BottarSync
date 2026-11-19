# Changelog

## 0.5.0 - Who plays each character

- **Your Discord username**: a member whose account has none yet is asked for it a little after logging in or joining the guild, in a box with an Accept button. It is the account's unique username, in small letters (2 to 32 letters, numbers, `_` or `.`), not the display name nor a server nickname: the box says so, and its tooltip tells where Discord shows it.
- **My data**: a new button on the game's guild window, at the bottom right of the guild's Chat and Roster tabs (Invite Member and Guild Settings move left of it), opens a window where you change your Discord username and tick which of your characters are mains; the others are alts, and you may have several mains. A character whose line is cut shows it whole in a tooltip. A change reaches the guild within seconds. The game's Guild Settings button is widened to show its whole name, which was cut in some languages.
- The name and the mains belong to your WoW account: every character of the account carries them, also while offline, and characters on another account with the same Discord name count as the same player.
- **The file for the bot** gives each member a `discord` (their player's Discord name) and a `main` (true for a main, false for an alt).
- Members on 0.4 or before cannot read this version's data, and are told to update. This version still reads their changes.

## 0.4.0 - Each addon shares its own part

- **Bot'tar Sync shares the character alone**: name, realm, level, class, race, sex and faction. Professions and recipes are Guild Professions & Recipes' to share, and talents, the items worn and the item level Guild Builds' (0.2 or later), so nothing travels twice.
- **The file for the bot still has all of it**: Bot'tar Sync reads each member's part from those addons when it writes the file, in the same format. Talents come from the builds each member shares in Guild Builds ("Share talents" at the bottom of the talent window): a spec not shared has its points per tab and no talents, and a new field, `shared`, says which. Items worn and item level follow Guild Builds' "Share gear".
- Members on 0.3 and this version keep sharing their characters. What 0.3 still sends besides is left out. The admin who writes the file needs this version, with the other addons on, and LibGuildSync 0.3 or later.
- `/bottar status` says when one of those addons is off or missing.

## 0.3.1 - Guild Builds comes along too

- **Brings Guild Builds**, the guild's talent builds and gear sets in the guild roster: the CurseForge app now installs it with Bot'tar Sync, together with the guild's other addons. Bot'tar Sync still runs without it and does not read its data.

## 0.3.0 - Between the guild window and KinFolk

- **A KinFolk button on the game's guild window**, with KinFolk's logo, left of the minimize and close buttons: it opens and closes KinFolk.
- **A guild window button on KinFolk's window**, with the guild tabard, left of its close button: it opens and closes the game's guild window. Neither button touches the other window.
- Both look like the game's own title bar buttons: the same red frame, size, spacing, pressed and highlight looks, with their icon inside.
- **A key to open and close KinFolk**: in the game's Key Bindings, under AddOns, Bot'tar Sync. Shift+J works, for example, while J keeps opening the game's guild window.
- Without KinFolk none of this shows, and the key only says that KinFolk is missing.

## 0.2.1 - KinFolk comes along too

- **Brings KinFolk**, the guild hub addon: the CurseForge app now installs it with Bot'tar Sync, together with the guild's other addons. Bot'tar Sync still runs without it and does not read its data.

## 0.2.0 - The guild's addons in one install

- **Brings the guild's other addons**: the CurseForge app now installs Guild Professions & Recipes and Guild Bank Alts with Bot'tar Sync, so a guild member only needs this one. Bot'tar Sync still runs without them.
- **Now needs LibGuildSync**, the shared code of the guild addons: hidden addon messages, the guild roster, the saved data and the sync. The CurseForge app installs it with Bot'tar Sync; by hand, copy its folder too.
- **Nobody has to update at once**: members on 0.1 and on 0.2.0 keep sharing everything, and the file for the bot does not change.

## 0.1.1 - Alongside the guild's other addons

- **Loads after the guild's other addons**, Guild Professions & Recipes and Guild Bank Alts, when they are installed. Neither is required.

## 0.1.0 - First release

- **Every guild member's characters**, shared through hidden addon messages: level, class, race, sex, faction, item level and equipped items, professions with every learned recipe, and talents, both specs with dual spec.
- **A sync at login**, so you also get the data of guild members you never meet online, as long as someone with the addon is online.
- **A file for your guild's Discord bot**: when you log out or reload the interface, everything goes as JSON into the addon's saved variables file, together with the whole guild roster (rank, public note, level, last time online), also for members without the addon.
- **`/bottar show`** shows a member's data as the bot gets it, in a window you can copy from; `/bottar save` writes the file now.
- **Translated into every client language**: English, German, Spanish, French, Italian, Korean, Portuguese, Russian and Chinese.
