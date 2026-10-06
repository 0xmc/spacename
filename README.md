# SpaceName

A macOS menu bar item that shows a name for the current desktop (Space).
Each desktop keeps its own name. With multiple displays, each display's menu
bar shows the name of that display's current desktop.

## Build and install

```sh
./build.sh --install
```

This builds `SpaceName.app`, copies it to `/Applications`, and launches it.
To build without installing, run `./build.sh`. The output is in `build/`.

## Usage

Click the menu bar item to do the following. Naming applies to the current
desktop of the display you clicked.

- **Name Desktop** or **Rename Desktop**: set the label for the current desktop.
- **Remove Name**: clear the label. Unnamed desktops show `Desktop N`.
- **Open at Login**: start the app when you log in.

## How it works

macOS has no public API that identifies the current desktop. The app calls
the private CoreGraphics function `CGSCopyManagedDisplaySpaces` and keys each
label by the desktop's UUID, which persists across reboots. Labels are stored
in `UserDefaults` under `com.0xmc.spacename`.

macOS copies a status item identically onto every display's menu bar, so one
status item can't show a different name per display. The status item stays
blank and only reserves space. A click-through window on each display draws
that display's name over its copy of the item.

To print each display's current desktop key and name, run:

```sh
build/SpaceName.app/Contents/MacOS/SpaceName --dump
```
