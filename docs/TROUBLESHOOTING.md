# Troubleshooting

## Capture overlay will not close

Try any of these independent controls:

1. Press `Esc`.
2. Press `⌘.`.
3. Right-click anywhere.
4. Click **Cancel · Esc** in the upper-right corner of either display.
5. Use the SnapMark menu-bar icon and choose **Quit SnapMark**.
6. Press `⌘Q` while SnapMark is active.

The overlay also cancels itself after 60 seconds. As an external last resort,
open Terminal and run:

```sh
pkill -x SnapMark
```

## Screen Recording permission repeats

Keep only one installed copy of SnapMark and launch it consistently from that
path. If the permission database contains an obsolete development build:

```sh
tccutil reset ScreenCapture local.fatih.snapmark
```

Then reopen the installed app, begin a capture, and grant permission once.

## macOS says the app cannot be opened

Public releases are ad-hoc signed and not notarized. Try opening
`SnapMark.app` once, then use **System Settings → Privacy & Security → Open
Anyway**. macOS saves an exception for that app. A self-signed certificate
does not grant automatic Gatekeeper approval to downloaded apps; see
[Local signing](LOCAL_SIGNING.md) for what it does provide.

## The wrong display is saved

**Save Current Screen to Desktop** saves the display containing the mouse
pointer. Move the pointer to the desired display before selecting the command
or pressing `⌘⇧1`.
