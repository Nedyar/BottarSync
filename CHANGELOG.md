# Changelog

## 0.7.0 - Add your characters

- **Add a character to your list**: My data has a search box at the bottom: type part of a name and the guild's characters that are nobody's yet and have it show above the box. Click one, or choose it with the arrow keys and press Enter. The added character counts at once as your main or alt, in the Statistics window, the roster's boxes and the file for the bot, and shows as pending until it accepts.
- **The character accepts**: when it logs in without a Discord username, it is asked whether it is yours. Accepting makes only that character yours, not the rest of its WoW account. Rejecting asks for its own username. A character that already has another player's username stays theirs: your list shows it as another player's, it does not count, and you can take it out.
- **Manage your characters from any of them**: My data lists every character of yours, also those that accepted from another WoW account, and any of them changes the username, the mains and the alts.
- On a computer without your saved data, a character is asked whether it is yours too, instead of taking it on its own.
- A member's tooltip in the roster marks the pending characters, and the file for the bot gives each member a `pending` (true while their player's character has not accepted).
- **The Statistics window can be moved**: drag it anywhere, as tall as it was. It opens beside the guild window again.
- Members on 0.6 and before cannot read this version's data, and are told to update. This version still reads their changes.

## 0.6.0 - The roster in numbers

- **Filters on the guild roster**: three new boxes on the guild's Roster tab, right of Offline members: Mains and Alts, ticked, and Banks, not ticked, so bank characters stay out of the list until you tick it. Members without Bot'tar Sync, or without a Discord username, count as mains. Bank characters are those with a bank rank of Guild Bank Alts ("Banco" until the guild master chooses others).
- **Statistics**: a new button left of Offline members opens a window beside the guild window, as tall as it, with the guild's members in numbers. A click on a number filters the roster, and a second click removes the filter:
  - **Characters**: how many mains, alts, bank characters and all of them; a click shows only that kind (it sets the boxes).
  - **Classes**: a bar with a section of each class's color, as wide as its share. A click on a class shows a second bar with its specializations, from Guild Builds. A character whose two specs go into different trees counts in both, and the window says how many do.
  - **Levels**: a card for each ten levels, and one for level 60.
  - Every number counts what the other filters let through, and the offline members only while the roster shows them. The class, specialization and level filters go when the window closes.
- **A member's tooltip in the roster always shows**, not only when a text is cut, and adds their player's Discord username, mains and alts.

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
