# pm3gui — a small SwiftUI front end for LF tags

A macOS bench tool with four actions over a Proxmark3: **connect, read, write,
wipe**, scoped to LF T5577 / EM410x cards. Personal tooling, not a product, and
not intended to be contributed upstream.

Design notes and the hardware transcripts the parsers were written against are
in [`docs/pm3-gui/HANDOFF.md`](../../docs/pm3-gui/HANDOFF.md).

## Building

The app links `libpm3` out of this same checkout, so build the library first:

```bash
export PATH="$HOME/bin:$PATH"          # cmake lives in ~/bin on some machines
cd client/experimental_lib
rm -rf build && mkdir build && cd build
cmake .. -DSKIPPYTHON=1
make -j10                              # -> libpm3rrg_rdv4.dylib
```

Then:

```bash
cd tools/pm3gui
swift build
./.build/debug/PM3GUI
```

`Package.swift` locates the dylib relative to its own path and bakes in an
rpath, so no `DYLD_LIBRARY_PATH` is needed at run time. Rebuilding `libpm3`
does not require rebuilding the app.

## How it works

| Piece | Role |
|---|---|
| `Sources/CPM3/module.modulemap` | Exposes `client/include/pm3.h` to Swift. No wrapper layer. |
| `PM3Session` | Serialises every libpm3 call onto one dedicated thread. |
| `DeviceFinder` | Locates the serial port through IOKit by USB vendor name. |
| `PM3Output` | Parses `lf` command output. |
| `TagController` | The four actions, and the state the UI binds to. |

## Things worth knowing before changing this

**The port is found by USB vendor name, never by the port name.** An Anker
Type-C hub also enumerates as `/dev/tty.usbmodem…` and has been mistaken for a
Proxmark3. `DeviceFinder` matches on `proxmark.org`.

**`pm3_console`'s return code is not a found/not-found signal.** `lf search`
returns `-10` while successfully reporting a chipset it recognised. Parse the
output text; treat the return code only as a transport hint.

**libpm3 keeps one global current device and its console call blocks** for as
long as the operation takes — seconds, for an LF search. Everything goes through
`PM3Session`'s serial queue, and the UI disables its buttons while a call is in
flight. There is no timeout API, so a wedged device would hang that queue.

**Only one process can hold the serial port.** Quit the app before using the
`pm3` CLI against the same device, and vice versa.

**Wipe is destructive** and sits behind a confirmation dialog. Write verifies by
reading the tag back rather than trusting the write's own success message.

## Licence

proxmark3 is GPLv3 and this app links `libpm3`, so it inherits GPLv3.
