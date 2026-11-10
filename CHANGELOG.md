# Changelog

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
