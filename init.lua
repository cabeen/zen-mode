-- Zen Mode for macOS: a distraction-free mode for Hammerspoon
-- Author: Ryan Cabeen <cabeen@gmail.com>
-- Repository: https://github.com/cabeen/zen-mode
-- License: MIT (see LICENSE)

-- Snap windows instantly instead of Hammerspoon's choppy step-animation.
-- Note: this is a global Hammerspoon setting, so it affects any other
-- window-moving scripts in your config too. Zen Mode does its own animation.
hs.window.animationDuration = 0

local topMargin = 40
local bottomMargin = 40
local padding = -2
-- Corner rounding of the cutout. Should be at least the window's own corner
-- radius: too small leaks bright background at the corners, too large just
-- dims a sliver of the window corner. macOS 26 "Tahoe" windows are much
-- rounder (and vary per window); on older macOS ~10 is enough.
local cornerRadius = 24
local fillColor = {white = 0, alpha = 0.85}
local moveDuration = 0.3   -- seconds to glide the window to/from center; 0 = instant
local resizeDuration = 0.3 -- seconds to grow/shrink to full height; 0 = instant

local zenCanvas = nil
local zenWindow = nil
local originalFrame = nil
local escapeHotkey = nil
local zenTracker = nil
local zenAnimator = nil
local lastFrame = nil

local function stopTimers()
    if zenTracker then
        zenTracker:stop()
        zenTracker = nil
    end
    if zenAnimator then
        zenAnimator:stop()
        zenAnimator = nil
    end
end

-- The cutout rect, in canvas-local coordinates
local function cutoutFrame(f, base)
    return {
        x = f.x - base.x - padding,
        y = f.y - base.y - padding,
        w = f.w + (padding * 2),
        h = f.h + (padding * 2)
    }
end

-- Set the window frame, then fit the cutout to where the window actually
-- ended up: apps apply resizes late (and round to their own grid), and a
-- cutout that runs ahead of the window leaks bright background. Reading the
-- frame back means any residual lag errs dark instead of bright.
local function placeWindow(win, f)
    win:setFrame(f, 0)
    local actual = win:frame() or f
    if zenCanvas then
        zenCanvas[2].frame = cutoutFrame(actual, zenCanvas:frame())
    end
    return actual
end

local function easeInOutCubic(t)
    if t < 0.5 then
        return 4 * t ^ 3
    end
    return 1 - (-2 * t + 2) ^ 3 / 2
end

local function lerpFrame(a, b, t)
    return {
        x = a.x + (b.x - a.x) * t,
        y = a.y + (b.y - a.y) * t,
        w = a.w + (b.w - a.w) * t,
        h = a.h + (b.h - a.h) * t
    }
end

-- A frame of the given size, centered within the outer frame
local function centeredIn(outer, size)
    return {
        x = outer.x + (outer.w - size.w) / 2,
        y = outer.y + (outer.h - size.h) / 2,
        w = size.w,
        h = size.h
    }
end

-- Glide the window between frames while fading the backdrop, keeping the
-- cutout glued to the window the whole way, then call done()
local function animate(win, fromFrame, toFrame, alphaFrom, alphaTo, duration, done)
    stopTimers()

    local function finish()
        if zenCanvas then zenCanvas:alpha(alphaTo) end
        placeWindow(win, toFrame)
        done()
    end

    if duration <= 0 then
        finish()
        return
    end

    local start = hs.timer.secondsSinceEpoch()
    zenAnimator = hs.timer.doEvery(1 / 60, function()
        local t = (hs.timer.secondsSinceEpoch() - start) / duration
        if t >= 1 then
            zenAnimator:stop()
            zenAnimator = nil
            finish()
            return
        end
        local e = easeInOutCubic(t)
        if zenCanvas then
            zenCanvas:alpha(alphaFrom + (alphaTo - alphaFrom) * e)
        end
        placeWindow(win, lerpFrame(fromFrame, toFrame, e))
    end)
end

-- Tear everything down once the exit transition has landed
local function finishExit()
    if zenCanvas then
        zenCanvas:delete()
        zenCanvas = nil
    end
    zenWindow = nil
    originalFrame = nil
    lastFrame = nil
end

local function exitZenMode()
    stopTimers()

    -- Crucial: Give the Escape key back to macOS and your terminal!
    if escapeHotkey then
        escapeHotkey:disable()
    end

    if zenCanvas and zenWindow and originalFrame then
        local current = zenWindow:frame()
        if current then
            -- Shrink back to the original size first, under the dark
            -- backdrop, then glide home as the darkness lifts
            local win = zenWindow
            local alpha = zenCanvas:alpha()
            local mid = centeredIn(current, originalFrame)
            animate(win, current, mid, alpha, alpha, resizeDuration, function()
                local settled = win:frame() or mid
                animate(win, settled, originalFrame, alpha, 0, moveDuration, finishExit)
            end)
            return
        end
    end

    finishExit()
end

-- Keep the cutout glued to the window if it is moved or resized
local function trackWindow()
    if not (zenCanvas and zenWindow) then return end

    local f = zenWindow:frame()
    if not f or f.w == 0 then
        -- Window closed or minimized; tear down without touching it
        zenWindow = nil
        exitZenMode()
        return
    end

    if lastFrame and f == lastFrame then return end
    lastFrame = f

    zenCanvas[2].frame = cutoutFrame(f, zenCanvas:frame())
end

-- Create the Escape hotkey, but DO NOT enable it yet.
escapeHotkey = hs.hotkey.new({}, "escape", function()
    exitZenMode()
end)

-- Bind to Option (alt) + Command (cmd) + Z
hs.hotkey.bind({"alt", "cmd"}, "z", function()
    if zenCanvas then
        -- If already active (or mid-transition), toggle it off
        exitZenMode()
    else
        -- Toggle Zen Mode ON. Check that window operations actually work
        -- before darkening anything: without Accessibility access the
        -- blackout canvas would still appear, burying the very Settings
        -- window (or permission prompt) the user needs to see. A functional
        -- test beats asking the system, which can misreport the state.
        local win = hs.window.focusedWindow()
        local frame = win and win:frame()
        if not (frame and frame.w > 0 and frame.h > 0) then
            hs.alert.show(
                "Zen Mode: no focusable window found.\n" ..
                "If a window is focused, Hammerspoon may be missing\n" ..
                "Accessibility access (System Settings → Privacy & Security).",
                3
            )
            return
        end

        zenWindow = win
        originalFrame = frame

        local screen = win:screen()
        local fullMax = screen:fullFrame()
        local f = win:frame()

        f.y = fullMax.y + topMargin
        f.h = fullMax.h - topMargin - bottomMargin
        f.x = fullMax.x + (fullMax.w / 2) - (f.w / 2)

        zenCanvas = hs.canvas.new(fullMax)
        zenCanvas:level(hs.canvas.windowLevels.cursor)

        zenCanvas:appendElements(
            {
                type = "rectangle",
                action = "fill",
                fillColor = fillColor
            },
            {
                type = "rectangle",
                roundedRectRadii = {xRadius = cornerRadius, yRadius = cornerRadius},
                action = "fill",
                compositeRule = "clear",
                frame = cutoutFrame(originalFrame, fullMax)
            }
        )

        -- Start fully transparent, then fade in as the window glides.
        -- Moves are cheap for apps to apply, resizes are not: glide the
        -- window at its original size, and only grow to full height once
        -- the backdrop is fully dark.
        zenCanvas:alpha(0)
        zenCanvas:show()
        win:focus()

        local mid = centeredIn(f, originalFrame)
        animate(win, originalFrame, mid, 0, 1, moveDuration, function()
            local settled = win:frame() or mid
            animate(win, settled, f, 1, 1, resizeDuration, function()
                lastFrame = win:frame() or f
                zenTracker = hs.timer.doEvery(0.03, trackWindow)
            end)
        end)

        -- Enable the Escape key intercept ONLY while Zen Mode is active
        escapeHotkey:enable()
    end
end)
