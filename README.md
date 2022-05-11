# Discord Sync

A Discourse plugin built specifically for aloha.pk, forked from https://github.com/barreeeiroo/discourse-discord-sync

This plugin runs a Discord bot to keep groups and members synced between the aloha.pk forum and Discord server.

This plugin depends on Discord OAuth2 to identify and link Discourse-Discord accounts. If you don't want to allow
users to login with Discord, but you wish to keep linking account, check
[the solution to this topic](https://meta.discourse.org/t/partially-enable-login-option/175330/4?u=barreeeiroo).

This bot will sync all Discourse groups with Discord roles. It will automatically trigger an update when an user
links their Discord account, user groups are changed or profile gets updated.

The !sync command, when used in the designated admin channel, will sync the Discord roles' colors and icons.  

## Installation Instructions

1. Follow the standard guide at [How to install a plugin?](https://meta.discourse.org/t/install-a-plugin/19157?u=barreeeiroo)
with this repository URL.
2. Follow [this guide](https://meta.discourse.org/t/configuring-discord-login-for-discourse/127129) to set up Login with Discord
in your Discourse instance.
3. In the Discord Developer portal, go to Bot, and add it to your server. Make sure you grant him the highest possible role.
4. In Discourse, in Plugin Settings, set `discord sync token` with the Bot token that appears in the previous step.

## Configuration

- **`discord sync enabled`**: Whether or not to enable the integration
- **`discord sync token`**: Bot token from Discord
- **`discord sync prefix`**: Prefix for commands (just `!ping` by now)
- **`discord sync admin channel id`**: Channel to post logging messages (nick changes, role changes, debug messages) and also the channel to run !sync
- **`discord sync public channel id`**: Channel to post formatted role change embedded messages
- **`discord sync role support url`**: Support/info hyperlink in public channel embedded messages
- **`discord sync message footer logo url`**: Image url for icon in public channel embedded messages
- **`discord sync username`**: If true, it will sync all Discord server nicknames to their Discourse username
- **`discord sync verified role`**: Role to add to all users who have a Discourse account
- **`discord sync safe roles`**: List of roles that bot will ignore and will mark as manually granted in Discord
- **`discord debug enabled`**: Toggle debug messages to post in the admin channel


## Updating icon assets
1. Download the svg assets from font-awesome -> https://github.com/FortAwesome/Font-Awesome/tree/6.x/svgs
2. Download and install ImageMagick -> https://imagemagick.org/script/download.php
3. Run the follow cmd on the asset folder(s): magick mogrify -gravity center -scale "80x80" -extent "96x96" -alpha deactivate -negate -transparent black -background none -format png *.svg
4. Drag the outputted pngs into and overwrite discord sync's icons directory
