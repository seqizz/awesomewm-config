## My AwesomeWM config

This is the reason I'm still not using Wayland. Too good to lose.

#### Highlights

- Just 4 permanent tags, no transient crap: `term`, `chat`, `web`, `mail`
- Only 2 active layouts: Tile and Max (default)
- Remembers/loads which tags were visible/active on every individual screen on WM (re)start
- Handmade theme
  - Powerline-style wibar
  - Gruvbox colors, different colors hinting the status of all widgets
  - Custom volume/brightness sliders & media notifications
  - Random wallpapers per screen, from given directory
- Multi-monitor support
  - The X display which has "primary" set shows systray and 2 tags (term & chat) on it, so primary is needed
  - Non-primary displays get the web & mail tags (replicated if more screens available)
  - Dynamic re-organisation of tags in case of screen addition/removal (so no clients get lost)
  - If a monitor is widescreen, automatically split into 2 equal "fake" screens (which you can expand/shrink)
- Taglist hints client count by dots, dynamically updated
- Keyboard oriented
  - Can resize, change tag, move, minimize, even suspend any client via shortcuts
    - Special keys for moving clients between visible screens
  - Can toggle special "sticky" mode for client
    - Very useful to keep meetings on the corner & on top
    - Can be even toggled to "shy" mode, which makes it semi-transparent and actively escape from mouse
- Useful widgets on wibar, as needed/supported by environment
  - Rotate screen toggle
  - Touchscreen toggle
  - Caps lock warning widget (only visible while caps lock on)
  - Pressure information widget (Linux PSI)
  - ~~Keyboard layout toggle~~ (disabled, as I'm using a single layout now)
  - Interactive Spotify widget (when app is running)
    - Can also swallow the client


#### Window related shortcuts

| Shortcut                    | Action                                                                |
| ---                         | ---                                                                   |
| Win + Arrows                | Swap focus between windows                                            |
| Win + Shift + WASD          | Move (floating) windows to that direction (***)                       |
| Win + Shift + Arrows        | Move windows to the screen on that direction                          |
| Win + Ctrl + Arrows         | Expand (floating) windows to that direction                           |
| Win + Ctrl + Shift + Arrows | Shrink (floating) windows from that direction                         |
| Win + Q                     | Kill window                                                           |
| Win + Enter                 | Swap master window                                                    |
| Win + WASD                  | Expand active (tiling) windows size to that direction (***)           |
| Win + Z                     | Minimize Window                                                       |
| Ctrl + Alt + S              | Suspend window (Linux SIGSTOP)                                        |
| Ctrl + Alt + W              | Make window sticky + on top (e.g. video meeting)                      |
| Ctrl + Alt + Shift + S      | Make window sticky (*)                                                |
| Win + Esc                   | Hide sticky windows                                                   |
| Win + F7 / F8               | Expand / Shrink fake screens (**)                                     |
| Win + 1234 (n)              | Go to nth tag                                                         |
| Win + Shift + 1234 (n)      | Move window to nth tag                                                |
| Win + Tab                   | Tab-cycle between tags (via [alttab](https://github.com/sagb/alttab)) |

And of course, I have tons of other shortcuts for launching helpful stuff, but that's not config-related.

(\*) Looking for a better shortcut / not commonly used

(\*\*) I am doing this with a keyboard knob generally, which is a lot easier

(\*\*\*) TODO: Needs single shortcut for all situations, auto-detect floating or not

![screenshot single screen](./screenshot.jpg)
  
![screenshot double screens](./screenshot2.jpg)

