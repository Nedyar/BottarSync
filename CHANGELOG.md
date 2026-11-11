# Changelog

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
