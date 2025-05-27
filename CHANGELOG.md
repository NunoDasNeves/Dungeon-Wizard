# Changelog

## v0.13.0 (2025-05-??)
- Add a button at the Shop to remove a card from your deck, costing 5 gold

## v0.12.4 (2025-03-30)
- Fix crash caused by manually resizing window in certain cases (Thanks to https://github.com/JustinBraben)

## v0.12.3 (2025-03-21)

- Support for building on linux (you need to build it yourself: https://github.com/NunoDasNeves/Dungeon-Wizard)
- Log panic()s to debug-log.txt, and don't strip symbols on release, for stack traces

***Balance***
- Promptitude can be cast on allies as well as self
- Protec can't be cast on enemies, only allies and self
- Rimefrost shields for 7 (up from 5)

## v0.12.2 (2025-03-19)

- Sleep between frames to use less CPU time
- Write options.txt and logs to %APPDATA%\Dungeon Wizard on Windows

## v0.12.1 (2025-03-05)

- Package as "Dungeon Wizard.app" in a .dmg for MacOS distribution
- Write options.txt and logs to /Users/username/Library/Application Support/Dungeon Wizard on MacOS
- Don't open console on Windows
- Improve scrolling when viewing deck

## v0.12.0 (2025-02-28)

- Explosion VFX for gobbomber, fire boom, flame burst
- Progress indicator between rooms
- Additional spell card art
- UI tweaks and bugfixes
- Shop repopulates on buy
- Secret summon

## v0.11.0 (2025-02-22)

***Misc***
- Pretty title screen
- Title screen music and lots of sounds, by Ethan Kelly!
- Volume controls!
- Name the game "Dungeon Wizard"
- More stuff probably, I forgot

***Features***
- You can view your deck by pressing 'N'
- You can stop moving by pressing 'S'
- There's a "How to Play" tutorial, ("???" button in the top right)
- Add several new spells, including 4 new summons, several more ice and lightning spells
- Boss!

***Balance***
- Various tweaks to spell damage, rarity, effect
- Various tweaks to creature damage and HP
- Regenerate mana faster by standing still (or grab the crystals)
- Wave spawning - next wave can now spawn if you've defeated only half the current wave, if you take too long
- Easier spell targeting for e.g. unherring
- Rare (blue) spells appear less frequently
- Shop prices and selection adjusted. Shop always has a rare spell for sale

## v0.10.0 (2025-01-04)

***Misc***
- Added CHANGELOG.md

***Features***
- Spike pits!
    - Most creatures can't path over spikes, unless they can fly or dash over
    - Creatures can teleport/dash/be pushed onto spikes, at which point they take damage and are pushed out (toward the closest pathable tile)
    - So they're basically walls that you can see/shoot/dash over, and can push enemies into!
    - Added spike pits in existing maps and added a couple new maps
- Casting progress bar
- Casting time icons on cards (hourglasses)
- Fire damage visual hit effect
- New room exit doors
- Room rewards are now in chests which spawn after completing a room
- Additional VFX for spells and other things (flame dart, fire boom...)
- New shop room and NPC shopkeeper. He doesn't say much
- Slimes leave behind a nasty trail of goop. Eww! Don't step in it!
- Game window can be freely resized
- You can win the game without crashing it now! (Still no "proper" ending yet, there's a final room that's a little harder)

***Balance***
- Increase bat and sharpboi attack startup time
- Decrease gobbow damage
- Decrease impling hp and damage
- Wave spawning adjusted - instead of always spawning the next wave after a delay, it will wait until the current waves' strength is reduced below a threshold

