# Ryan's Zen Mode

A lightweight, native-feeling [Hammerspoon](https://www.hammerspoon.org/) script that gives **every Mac app** a distraction-free "Zen Mode."

Unlike the focus modes built into individual editors, this works system-wide: press one hotkey and whatever window is active — terminal, code editor, browser, PDF reader, anything — is centered on screen and stretched to full height, while the rest of your desktop, including the macOS Menu Bar and Dock, fades into darkness. Press it again (or hit `Esc`) and your window snaps back exactly where it was.

## Screenshots

**Before:** a typical desktop, with the active window off-center and the wallpaper, Menu Bar, and Dock competing for attention.

![Desktop before enabling Zen Mode](screenshots/before.jpg)

**After:** with Zen Mode enabled, the window is centered and maximized to full height, and everything else fades into darkness.

![Desktop after enabling Zen Mode](screenshots/after.jpg)

## Features

* **Any app, no per-app setup** — this is a global mode, not an app feature: it operates on whatever window is focused, so the same hotkey zens your terminal, browser, notes app, or anything else.
* **One-keystroke toggle** — `Option + Cmd + Z` enters or exits Zen Mode instantly.
* **Centered, full-height layout** — the window keeps its width, grows to full screen height, and is centered horizontally.
* **Aggressive UI hiding** — the darkening canvas renders at the macOS cursor window level, completely burying the Menu Bar and Dock.
* **Hermetic visual seal** — a slightly inset, rounded cutout hugs the inside of the macOS window frame, so no background pixels leak through the corners.
* **Smooth transitions** — entering plays a two-phase ease-in-out choreography: the window glides to center as the backdrop fades to black, then grows to full height under the darkness; exiting reverses it. Both phases are tunable (or fully off) via `moveDuration` and `resizeDuration`.
* **Live window tracking** — drag or resize the window while Zen Mode is active and the cutout follows it; if the window closes, the overlay tears itself down.
* **Safe Escape hook** — `Esc` exits Zen Mode instantly, but the key is only intercepted while Zen Mode is active; the moment you exit, it's handed back to macOS so Vim, terminals, and normal OS behavior work as usual.
* **State restoration** — your window's exact position and size are remembered and restored when you exit.

## Requirements

* macOS
* [Hammerspoon](https://www.hammerspoon.org/) — `brew install --cask hammerspoon`

## Installation

1. Install [Hammerspoon](https://www.hammerspoon.org/) and launch it:

   ```sh
   brew install --cask hammerspoon
   ```

2. Grant Hammerspoon **Accessibility** permissions (`System Settings > Privacy & Security > Accessibility`).
3. Append the contents of [`init.lua`](init.lua) from this repository to your `~/.hammerspoon/init.lua`.
4. Click the Hammerspoon icon in the Menu Bar and select **Reload Config**.

## Usage

| Action | Keys |
| --- | --- |
| Toggle Zen Mode on the focused window | `Option + Cmd + Z` |
| Exit Zen Mode | `Option + Cmd + Z` or `Esc` |

## How it works

Instead of resizing or hiding other apps, the script draws a single full-screen [CoreGraphics canvas](https://www.hammerspoon.org/docs/hs.canvas.html) over everything — elevated to the cursor window level so it covers the Menu Bar and Dock — and then punches a transparent, rounded-corner hole exactly where your focused window sits. Your window stays a completely normal, interactive window; everything around it is simply blacked out.

## Prior art

Several existing tools cover parts of this idea:

* **Distraction dimmers** — [HazeOver](https://hazeover.com/) (paid) and free alternatives like [FocusDim](https://www.producthunt.com/products/focusdim) automatically dim *background windows* whenever focus changes. They are passive, always-on effects: they don't touch the desktop wallpaper, Menu Bar, or Dock, and they never move or resize your window.
* **Hammerspoon's built-in [`hs.window.highlight`](https://www.hammerspoon.org/docs/hs.window.highlight.html)** — its "isolate" mode covers other windows and the desktop with an opaque overlay, and is the closest relative to the technique used here. It doesn't reposition the window or hide the Menu Bar and Dock.
* **App-specific zen modes** — VS Code, Obsidian, iA Writer, and others ship a centered, chrome-free writing mode, but only inside that one app.
* **Native macOS full screen** — hides the Menu Bar and Dock, but stretches the window edge-to-edge rather than framing it.

What this script does differently is combine those pieces into one deliberate, reversible gesture that works on **any** window: a single hotkey centers the window at full height, blacks out everything else on screen — wallpaper, Menu Bar, and Dock included — in one synchronized animated transition, and puts the window back exactly where it was when you leave. It's also not an app: it's ~250 lines of dependency-free Lua you can read in a few minutes and tweak to taste.

## Design notes

Most of the effort in this script went into small UX details that are easy to get wrong:

* **Smooth animation.** Hammerspoon's built-in window animation (`hs.window.animationDuration`) steps the window through a series of synchronous Accessibility calls, which looks choppy. Zen Mode disables it and runs its own 60 Hz animation clock, easing the window frame and the backdrop's alpha together from a single timeline. The animation is time-based rather than step-based: if an app is slow to apply a frame, it just renders fewer intermediate frames — the transition always completes on schedule.

* **Move, then resize.** Moving a window is cheap for the target app; resizing forces a re-layout on every step (terminals reflow their whole character grid). So the transition is choreographed in two phases: the window glides to center *at its original size* while the screen fades to black, and only grows to full height once the backdrop is fully dark — the most forgiving moment for the less-smooth resize. Exiting mirrors this: shrink in the dark, then glide home as the darkness lifts.

* **Handling window edges.** The cutout is fitted to where the window *actually is*, not where it was asked to be. Apps apply frame changes late and round them to their own grids (a terminal snaps to character cells), so a cutout that follows the requested frame runs ahead of the window and leaks bright background mid-animation. After every frame change the script reads the real frame back and fits the cutout to that — any residual lag then errs dark (window briefly under the overlay) instead of bright. The cutout is also inset slightly (`padding = -2`) so the darkness overlaps the window edge rather than leaving a bright seam.

* **Handling window corners.** The cutout's corner radius must be at least the window's own corner radius, or a sliver of undimmed background peeks through at the corner diagonal. macOS 26 "Tahoe" made window corners dramatically rounder — and the radius varies from window to window, with no public API to query it. The default (`cornerRadius = 24`) is deliberately generous because the failure directions aren't symmetric: too large merely dims a sliver of the window's corner, while too small leaks bright background.

* **Hiding the Menu Bar and Dock.** An ordinary overlay window sits below the system UI. The canvas is escalated to the *cursor* window level — above the Menu Bar and Dock levels — so the blackout genuinely covers everything on screen except your window.

* **Why the backdrop is dark, not blurred.** A frosted-glass blur would be pretty, but macOS offers no public way for a script to blur what's behind an arbitrary window (the real backdrop-blur machinery is private API territory). The workaround — screenshot the desktop, blur it, display the result — needs Screen Recording permission and produces a frozen image that goes stale the moment anything behind it changes or the window moves. A translucent dark fill achieves the same focusing effect, stays live, and costs nothing. The backdrop also stays dark regardless of the system's light/dark appearance: darkness lowers both the brightness and the contrast of the background clutter, whereas a light scrim would itself become the brightest thing on screen — the spotlight metaphor works in either mode.

## Customization

A few variables in `init.lua` control the aesthetics:

| Variable | Default | Effect |
| --- | --- | --- |
| `topMargin` | `40` | Distance from the top of the screen, clearing the Menu Bar and camera notch. |
| `bottomMargin` | `40` | Distance from the bottom of the screen. |
| `cornerRadius` | `24` | Corner rounding of the cutout. Should be at least the window's own corner radius: too small leaks bright background at the corners, too large just dims a sliver of the window corner. macOS 26 "Tahoe" windows are much rounder than older releases (where `10` is enough). |
| `padding` | `-2` | Edge seal between the cutout and the window. Negative values overlap the window slightly to prevent light bleed; a positive value (e.g. `25`) leaves a gap so the native macOS drop shadow shows. |
| `fillColor` | `{white = 0, alpha = 0.85}` | Backdrop color. Raise or lower `alpha` (`0.0`–`1.0`) for lighter dimming or pitch black. |
| `moveDuration` | `0.3` | Seconds for the glide to/from center. Set to `0` for instant snapping. |
| `resizeDuration` | `0.3` | Seconds for the grow/shrink to full height. Set to `0` for instant snapping. |

To use a different hotkey, change the modifiers and key in the `hs.hotkey.bind({"alt", "cmd"}, "z", ...)` call.

## Notes and limitations

* **Tested on macOS 26 "Tahoe" only.** The Hammerspoon APIs used here are old and stable, so earlier releases should work, but they haven't been verified — and the `cornerRadius` default is tuned for Tahoe's rounder windows (drop it to ~`10` on older macOS). Reports from other versions are welcome.
* Windows that can't be resized (e.g. some utility and settings windows) will center but keep their size; the cutout adapts to whatever the window actually does.
* Native full-screen windows don't respond: macOS puts them in their own Space and ignores the reposition, so the window simply doesn't move. Leave full screen first. Switching Spaces while Zen Mode is active is untested territory; the hotkey or `Esc` will restore things.
* The script sets `hs.window.animationDuration = 0` globally, which also disables the built-in move animation for any other window scripts in your Hammerspoon config (Zen Mode does its own animation).

* While Zen Mode is active, `Esc` is captured globally to exit. If you rely on `Esc` inside an app (e.g. Vim), toggle off with `Option + Cmd + Z` instead, or remap the escape hook.
* The overlay covers the screen the focused window is on; other displays are unaffected.
* One window at a time: pressing the hotkey while Zen Mode is active always exits, even if a different window is now focused — press it again to zen the new window.

## Author

[Ryan Cabeen](https://cabeen.io/)

## License

[MIT](LICENSE)
