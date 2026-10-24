# MacMirrorScreen

A tiny menu-bar utility for Apple Silicon MacBooks docked to one external monitor.
Plug the monitor in and it becomes a mirror of the built-in panel, which goes dark while
staying the main display; unplug it and the panel comes back on. No windows, no settings UI:
one status-bar icon and a text config file.

- **Mirror mode**: the external display becomes a mirror of the built-in panel (System Settings
  calls this *Mirror for Built-in Display*), so the panel stays the main display and keeps its
  layout; then the panel's backlight is turned off. The panel is never *disabled*, only dimmed
  to 0, so it can always be brought back.
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
  ✓ Mirror built-in and turn it off
──────────────
Restore built-in display now
Open config file
Launch at Login
──────────────
Quit MacMirrorScreen
```

Choosing *Mirror built-in and turn it off* applies it immediately and remembers it. While a display is
in mirror mode the panel is kept dark: if macOS, ambient-light compensation or a brightness key
turns it back up, the watchdog dims it again within 10 s. To light the panel while docked use
*Restore built-in display now* (it stays lit until the next display change) or switch the display
to *Do nothing*.

The panel is the mirror source, so the external monitor shows the panel's picture at a resolution
taken from the panel and may show black bars. To change the picture size, pick another resolution for
the built-in display in System Settings → Displays; macOS remembers it. Do not make the external the
display being mirrored there (for example *Optimize for* the external monitor): the tool switches that
back at the next display change. To leave the arrangement to macOS, set the display to *Do nothing*.

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

## Why dim instead of disconnect

BetterDisplay, Lunar and blackoutd can remove the built-in panel from the display layout
through a private WindowServer API. That keeps the external monitor's own resolution, but the
disabled state lives in the WindowServer connection of the running process: if that process is
killed, the panel cannot be re-enabled until displays re-enumerate (replug the monitor, or log
out). Because this tool's first rule is that the panel must always come back, v1 only mirrors and
dims. A disconnect mode may arrive later as an explicit opt-in.

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

MacMirrorScreen 是一个只有状态栏图标的小工具：外接显示器插入时，自动把外接屏设为内置屏幕的镜像
（内置屏仍是主显示器），然后关闭内置屏背光；拔出时内置屏幕自动恢复。配置是
`~/.config/macmirrorscreen/config.json` 文本文件，每台外接屏一条记录，`mode` 为 `none` 或 `mirror`，
在菜单里选一次即记住。

镜像时内置屏是镜像源，外接屏显示内置屏的画面，分辨率跟随内置屏，可能出现黑边；要调整画面大小，请在系统设置里
改内置屏的分辨率。若在系统设置里把外接屏改成被镜像的一方，工具会在下一次显示变化时改回来；不想让工具管理时选
"Do nothing"。

保底策略：内置屏幕只会被调暗到 0，从不被禁用，所以键盘亮度键随时可用；拔出、唤醒、退出、收到 SIGTERM、
崩溃后再次启动、每 10 秒的看门狗以及菜单中的 "Restore built-in display now" 都会恢复亮度，且恢复值不低于 30%。

安装：解压后先移动到 `/Applications` 再启动；未经公证，首次打开需执行
`xattr -dr com.apple.quarantine /Applications/MacMirrorScreen.app` 或在"隐私与安全性"中点击"仍要打开"。
