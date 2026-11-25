# Changelog

## 0.9.1 - The guild window from the Statistics window

- **A guild window button on the Statistics window**: the guild tabard, left of its close button, as on KinFolk's window. It opens and closes the game's guild window, and the Statistics window stays open.
- Members on 0.9.0 and this version share everything: nobody has to update at once.

## 0.9.0 - The guild's Discord on the Guild Info tab

- **Members on 0.8 must update.** What the officers set now carries the guild's Discord link, which 0.8 would leave out of the copies it passes on. Members on 0.8 see a "newer version" notice and stop getting the changes of members on 0.9 until they update; 0.9 still gets theirs.
- **A Discord panel on the Guild Info tab**, under the message of the day and laid out like the game's own panels: the guild's Discord link. The guild master and the officers (the ranks with "Has officer privileges", who edit the guild information too) change it with its Edit link: Enter saves it, Esc leaves it as it was. It reaches the whole guild at once, and lasts while any officer is around. Anyone copies it with the button beside it, which selects it for Ctrl+C: the game lets no addon write to the clipboard.
- **The whole message of the day**: the game showed it in a box three lines high, with arrows to scroll the rest; now it shows all of it.
- **More room for the guild information**: it starts right under the Discord panel and goes down to the bottom, instead of a box 93 pixels high at the bottom, and scrolls only when it does not fit. Its Edit link is the game's own, as before.
- **The Statistics button is on the guild window's title bar**, left of its minimize button, where KinFolk's button was, as an icon with its tooltip. The Roster tab no longer has it, and its Offline members box is back in its place.
- **An Offline members box in the Statistics window**, beside its Characters heading, the same as the game's on the Roster tab: unticked, the numbers and the list count the online members only. It starts as the game's box was left, and follows it whenever that one is clicked; ticking ours changes only the window (were it to change the roster's, the game would block changing notes again).
- **No more KinFolk button on the guild window.** KinFolk's window keeps its button to the guild window, and the key binding still opens KinFolk.

## 0.8.0 - The officers manage the players

- **The guild master and the officers manage every player's data**: the officers are the members whose rank has the game's "Has officer privileges" (in the guild's rank settings). Their My data window has a search box at the top: type a Discord username or the name of any character of the guild, and the window shows that player's username and characters, to change as the player would: the username, the mains, adding any character of the guild and taking any out. My data goes back to their own.
- **What they set prevails**: it counts at once for the whole guild, in the Statistics window, the roster and the file for the bot, over what the player says; a character they add to a player is not pending. The player sees it in their own window but cannot change it: those characters, and their username once the officers set anything about them.
- **Members without Bot'tar Sync get a player too**: a character that is nobody's opens alone in the window, and typing a username makes it that player's main.
- **Renaming a player** changes the username of all their characters, also those on other WoW accounts. Renaming to a username another player has joins the two.
- A character an officer gave to a player goes by that player's data when it logs in, instead of being asked for a username: only that character, not the rest of its WoW account.
- Every officer's addon keeps all the officers' changes, so they last while the one who made them is offline, and once they are no longer an officer.
- **Notes and ranks can always be changed from the guild roster again**: since 0.6, hiding members from the roster made the game block changing a member's notes or rank ("Bot'tar Sync has been blocked from an action only available to the Blizzard UI"), until the interface was reloaded. The game allows those changes only from rows of the roster it drew itself, and hiding members needs the addon to draw them. So the roster lists everyone again, as the game does: its Mains, Alts and Banks boxes are gone, and Bot'tar Sync never draws it again. Nor does it hook the guild window's scripts any longer, which also tainted the roster's rows as the window opened, nor add to a member's right-click menu, whose closing tainted the roster too.
- **The Statistics window lists the members instead**: right of the numbers, as tall as the window, the members the filters let through, in three columns with the game's headers: name (grey while offline), level, and Online or how long ago they were online, as the game's roster tells it. A click on a header sorts by it, another the other way. A member's tooltip tells their rank, level and class, note and player; an officer's click opens their player in My data. The kind cards choose one kind at a time: All, the first card, is chosen when the window opens, and a click on Mains, Alts or Banks lists only that kind (clicked again, All). The class, specialization and level filters filter the list too, and a search box above it finds members by name or Discord username among those listed. Its heading tells how many it shows.
- **The specializations bar always shows**: with no class chosen, it has every class's specializations, each in shades of its class's color; a click filters by one without choosing its class. Characters without builds in Guild Builds no longer have an Unknown section: they count in no specialization.
- Members on 0.7 and before cannot read this version's data, and are told to update. This version still reads their changes.

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
