# Proxmark3 GUI — handoff notes

**Status:** pre-design. Brainstorming is partly done, the feasibility spike has
passed, and no GUI code exists yet. Started 2026-08-15, moved to the datavault
MacBook 2026-08-16.

## Goal

A simple GUI over the Proxmark3 with four actions: **check connection, read a
tag, write a tag, wipe a tag.** Bench tool for personal use, not a product.

## Decisions locked so far

| Decision | Choice | Why |
|---|---|---|
| Tag family | **LF — T5577 / EM410x** | Read/write/wipe map to different command families per tag type; there is no generic version. T5577 is the standard rewritable LF card, `wipe` is a real single command, and no key management is involved. |
| Write flow | **Copy last-read ID to a blank** | Read populates an ID field, Write clones that ID onto a T5577. Makes the four buttons a coherent sequence. Field stays editable as an override. |
| Repo | **Fork `jonyen/proxmark3`** | Forked from `RfidResearchGroup/proxmark3` 2026-08-15. Left on `master` to match upstream. |

Commands these map to:

- read → `lf search`
- write → `lf em 410x clone --id <10 hex digits>`
- wipe → `lf t55xx wipe`  (destructive: "will destroy any data on tag")

## Direction, pending final approval

**SwiftUI app linking `libpm3` directly via Swift/C interop.**

This was arrived at by elimination, and the reasoning matters because it is easy
to relitigate:

- A **browser page cannot see USB/serial** — correct, and the objection that
  killed the web option.
- But **Electron and Tauri have the identical split**: sandboxed HTML renderer +
  privileged native process (Node / Rust) doing the hardware work. The web
  objection applies to them equally, so all three fell together.
- **Electron** additionally costs ~200MB of Chromium and an npm dependency tree
  in a C repo with zero JS tooling.
- **Tauri** is genuinely better than Electron (~5-10MB, system WKWebView) but
  needs a Rust toolchain that is not installed on either machine, and
  `src-tauri/` is as foreign to this C repo as `node_modules`. On Linux — where
  most pm3 users are — it also needs WebKitGTK dev packages.
- **SwiftUI wins on cost**: Xcode 26.6 and Swift 6.3.3 are already installed on
  both machines, and linking `libpm3` gives a genuine persistent device handle
  rather than a subprocess.

Trade-off accepted: macOS-only, and it lives beside the fork rather than being
contributable upstream.

**Licensing:** proxmark3 is GPLv3. An app linking `libpm3` inherits GPLv3. Fine
for personal use; relevant if it is ever shared.

## Spike results — PASSED on both machines

Verified that `client/experimental_lib` (named "experimental", so this was the
risk) builds and runs on Xcode 26 / arm64.

| Step | This Mac | Datavault (M4 Pro) |
|---|---|---|
| cmake configure | OK | OK |
| Build `libpm3rrg_rdv4.dylib` | OK, 5.3MB | OK, 5.1MB |
| Compile `example_c/test_grab` | OK | OK |
| Runtime init (session log, preferences) | OK | OK |
| Bad-port error path | clean `ERROR: invalid serial port`, exit 1 | same |
| **Real device I/O** | **UNVERIFIED — no hardware attached** | **UNVERIFIED — no hardware attached** |

Everything up to the serial port works: the library loads, resolves symbols,
reads `~/.proxmark3/preferences.json`, and fails gracefully rather than hanging.

### The one open risk

**No Proxmark3 is attached to either machine.** `pm3_open` against real hardware
is the single unverified link. Before writing GUI code, plug the device in and run:

```bash
cd ~/Projects/proxmark3/client/experimental_lib/example_c
DYLD_LIBRARY_PATH=../build ./test_grab "$(ioreg -r -c IOUSBHostDevice -l \
  | awk -F '"' '$2=="USB Vendor Name"{b=($4=="proxmark.org")} b==1 && $2=="IODialinDevice"{print $4}')"
```

Expect real `hw status` output. If that works, the design is de-risked.

Note: on 2026-08-15 `/dev/tty.usbmodemSN234567892` on the other Mac looked like a
Proxmark3 but is an **Anker Type-C hub** (idVendor 10522 / 0x291A). Identify the
device by USB vendor name `proxmark.org`, never by the port name.

## The API the GUI will wrap

From `client/include/pm3.h`:

```c
typedef struct pm3_device pm3;
pm3 *pm3_open(const char *port);
int  pm3_console(pm3 *dev, const char *cmd, bool capture, bool quiet);
const char *pm3_grabbed_output_get(pm3 *dev);
const char *pm3_name_get(pm3 *dev);
void pm3_close(pm3 *dev);
pm3 *pm3_get_current_dev(void);
```

`pm3_open` succeeding *is* the connection check. Read/Write/Wipe are
`pm3_console` calls whose captured output gets parsed. Swift can call all of it
through a bridging header — no wrapper layer needed.

Device discovery on macOS, which is what `pm3` itself does:

```bash
ioreg -r -c IOUSBHostDevice -l | awk -F '"' \
  '$2=="USB Vendor Name"{b=($4=="proxmark.org")} b==1 && $2=="IODialinDevice"{print $4}'
```

A native app can query IOKit directly for this, including live plug/unplug
notifications a CLI cannot provide.

## Rebuilding libpm3

```bash
export PATH="$HOME/bin:$PATH"          # cmake lives in ~/bin on datavault
cd ~/Projects/proxmark3/client/experimental_lib
rm -rf build && mkdir build && cd build
cmake .. -DSKIPPYTHON=1
make -j10
# -> libpm3rrg_rdv4.dylib
```

SWIG is only needed for the Lua/Python wrappers (`00make_swig.sh`), not the C
library. `-DSKIPLUA=1` is silently ignored — the flag does not exist.

## Datavault environment

- Repo: `~/Projects/proxmark3`, `origin` = `jonyen/proxmark3` (SSH),
  `upstream` = `RfidResearchGroup/proxmark3`.
- cmake 4.4.2 standalone at `~/opt/cmake-4.4.2-macos-universal`, symlinked to
  `~/bin/cmake`. **`~/bin` is not on PATH** — export it or use the full path.
  No Homebrew on this machine, deliberately.
- Xcode 26.6, Swift 6.3.3, M4 Pro, GitHub SSH auth working as `jonyen`.
- Build artifacts (`build/`, `test_grab`) are throwaway and gitignored.

## Next steps

1. Attach the Proxmark3 and run the `test_grab` check above.
2. Finish the design: window layout, how `lf search` output is parsed into an
   EM410x ID, error and timeout handling, and where the app lives relative to
   the fork.
3. Confirm whether a scratch T5577 is available. **Write and Wipe alter a
   physical tag and cannot be verified without one** — build them behind a
   confirmation step and leave live testing to a human unless a throwaway tag is
   explicitly offered.
