# MacMirrorScreen

A tiny menu-bar utility for Apple Silicon MacBooks docked to one external monitor.
Plug the monitor in and the built-in panel mirrors it and goes dark; unplug it and the
panel comes back on. No windows, no settings UI: one status-bar icon and a text config file.

- **Mirror mode**: the built-in panel becomes a mirror of the external display, then its
  backlight is turned off. The panel is never *disabled*, only dimmed to 0, so it can always be
  brought back.
- **Remembered per display**: each external monitor gets an entry in the config file; pick
  its mode once from the menu and it is applied automatically on every later plug.
- **Safety nets** so the panel cannot stay dark: restore on unplug, on wake, on quit or
  SIGTERM, on the next launch after a crash, by a 10 s watchdog, and from the menu. Restore
  never goes below 30 % brightness. As a last resort the hardware brightness keys always work.

## Install

Download `MacMirrorScreen.zip` from the latest workflow run or release, unzip, and move
`MacMirrorScreen.app` to `/Applications` **before** first launch (otherwise "Launch at Login"
records a temporary path). The app is ad-hoc signed, not notarised, so Gatekeeper will refuse
it once; either remove the quarantine flag:

```sh
xattr -dr com.apple.quarantine /Applications/MacMirrorScreen.app
```

or open System Settings → Privacy & Security and click *Open Anyway*. Requires macOS 13+.

## Use

Click the `display.2` icon in the menu bar:

```
External: DELL U2723QE
    Do nothing
  ✓ Mirror and turn off built-in
──────────────
Restore built-in display now
Open config file
Launch at Login
──────────────
Quit MacMirrorScreen
```

Choosing *Mirror and turn off built-in* applies it immediately and remembers it. While a display is
in mirror mode the panel is kept dark: if macOS, ambient-light compensation or a brightness key
turns it back up, the watchdog dims it again within 10 s. To light the panel while docked use
*Restore built-in display now* (it stays lit until the next display change) or switch the display
to *Do nothing*.

Mirroring lets macOS pick a mirror-capable mode for the pair, so the external monitor's resolution
or scaling may change; adjust it once in System Settings → Displays and macOS remembers it.

## Config file

`~/.config/macmirrorscreen/config.json`, created on first run and re-read on every display event
(edit it, then re-plug). Unknown monitors are added with mode `none`.

```json
{
  "displays" : {
    "4268-41187-0" : { "mode" : "mirror", "name" : "DELL U2723QE" }
  }
}
```

The key is `vendor-model-serial` as reported by CoreGraphics; the serial is often `0`, so two
identical monitors share one entry. `mode` is `none` or `mirror`.

The file `~/.config/macmirrorscreen/dimmed-brightness` exists only while the tool has dimmed the
panel and holds the brightness to restore; it is written before the panel goes dark and removed
after it is restored, so a crash or a kill never loses the value.

## If the panel is dark

1. Press the brightness-up key: the panel is only dimmed, never disabled.
2. Click the menu-bar icon → *Restore built-in display now*.
3. Relaunch the app: on launch it restores the panel when no mirrored external is online.

Logs go to Console.app (subsystem `io.github.ac50.MacMirrorScreen`) and to stderr when run
from a terminal.

## Build

Swift Package Manager only, no Xcode project, no dependencies. GitHub Actions (`macos-15`,
arm64) runs `swift test` and `scripts/bundle.sh`, which produces `dist/MacMirrorScreen.app`
and the zip. Locally on a Mac: `swift test && scripts/bundle.sh`. Tags `v*` publish a release.

Layout: `Sources/MirrorCore` is Foundation-only (config model and the pure planner, unit
tested); `Sources/MacMirrorScreen` holds the CoreGraphics mirroring, the DisplayServices
brightness calls (loaded with `dlopen`, no link-time dependency), the event loop and the menu.

## 中文说明

MacMirrorScreen 是一个只有状态栏图标的小工具：外接显示器插入时，内置屏幕自动镜像到外接屏并关闭背光；
拔出时内置屏幕自动恢复。配置是 `~/.config/macmirrorscreen/config.json` 文本文件，每台外接屏一条记录，
`mode` 为 `none` 或 `mirror`，在菜单里选一次即记住。

保底策略：内置屏幕只会被调暗到 0，从不被禁用，所以键盘亮度键随时可用；拔出、唤醒、退出、收到 SIGTERM、
崩溃后再次启动、每 10 秒的看门狗以及菜单中的 "Restore built-in display now" 都会恢复亮度，且恢复值不低于 30%。

安装：解压后先移动到 `/Applications` 再启动；未经公证，首次打开需执行
`xattr -dr com.apple.quarantine /Applications/MacMirrorScreen.app` 或在"隐私与安全性"中点击"仍要打开"。
