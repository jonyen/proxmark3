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
| App location | **`tools/pm3gui/` inside the fork** | Keeps the app and the `libpm3` it links versioned together. Never PR'd upstream. |

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
| **Real device I/O** | untested here | **VERIFIED 2026-08-17** |

Everything up to the serial port works: the library loads, resolves symbols,
reads `~/.proxmark3/preferences.json`, and fails gracefully rather than hanging.

### The open risk is closed

On 2026-08-17 a Proxmark3 was attached to the datavault MacBook at
`/dev/tty.usbmodemiceman1` and all four GUI actions were driven end to end
through `libpm3` — `pm3_open`, `pm3_console`, `pm3_grabbed_output_get`,
`pm3_close` — against a real T5577:

| Action | Command | Result |
|---|---|---|
| Connect | `pm3_open` + `hw status` | Full firmware status returned |
| Read | `lf search` | Chip and ID reported |
| Write | `lf em 410x clone --id 0102030405` | `Tag T55x7 written`, ID read back correctly |
| Wipe | `lf t55xx wipe` | All 8 page-0 blocks reset, tag reads blank after |

The design is de-risked. No wrapper process is needed; the library is enough.

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

## What the captured output actually looks like

Measured on real hardware, not guessed. These are what the GUI parses.

**`pm3_console` return code is not a found/not-found signal.** `lf search`
returned `-10` while successfully reporting `Chipset... T55xx`, and returned `0`
on a full EM410x hit. Parse the text; use the return code only to detect a
transport failure.

Read, tag present:

```
[+] EM 410x ID 0102030405
[+] EM410x ( RF/64 )
...
[+] Valid EM410x ID found!
```

Read, no tag (`rc = -10`):

```
[-] No known 125/134 kHz tags found!
[=] Couldn't identify a chipset
```

Read, blank T5577 on the antenna (`rc = -10` — it is a chip, but carries no ID):

```
[-] No known 125/134 kHz tags found!
[+] Chipset... T55xx
```

Write (`rc = 0`):

```
[#] Tag T55x7 written with 0xff8060280c048142
[+] Done!
```

Wipe (`rc = 0`) writes 8 blocks and prints one line per block:

```
[=] Writing page 0  block: 00  data: 0x000880E0
...
[=] Writing page 0  block: 07  data: 0x00000000
```

Line prefixes are consistent and worth keying on: `[+]` success, `[-]` failure,
`[=]` informational, `[#]` message from the device firmware, `[?]` hint.

`lf t55xx detect` is the cheapest "is a writable tag present" probe, and reports
`Password set...... No` — worth surfacing, since a passworded tag will fail to
write.

## The heap overflow the GUI flushed out

`pm3_grabbed_output_get` terminated the captured output at
`g_grabbed_output.size`, which is the *allocated capacity*, not the number of
bytes written — that is `idx`. Every call wrote one zero byte past the end of
the heap allocation.

The CLI survives it because it calls the function once or twice and exits. A GUI
captures output on every button press, so the corrupted malloc metadata gets
reused and the process dies somewhere unrelated — first as a SIGTRAP inside
AppKit's AutoFill, then as `AutoreleasePoolPage busted` on a dispatch worker
thread. Neither backtrace mentioned proxmark3 code.

Fixed in `client/src/pm3.c`. To reproduce it on any build predating that fix:

```bash
MALLOC_STRICT_SIZE=1 MallocGuardEdges=1 \
  DYLD_INSERT_LIBRARIES=/usr/lib/libgmalloc.dylib \
  DYLD_LIBRARY_PATH=../build ./test_grab <port>
```

Guard malloc puts the allocation flush against a guard page, so the one-byte
overrun becomes an immediate SIGSEGV inside `pm3_grabbed_output_get` instead of
damage that surfaces minutes later. **Worth running any new libpm3 client under
this at least once** — the failure mode is otherwise near-undebuggable.

## Next steps

1. ~~Attach the Proxmark3 and run the check.~~ Done 2026-08-17.
2. ~~Build the SwiftUI app in `tools/pm3gui/`.~~ Done — connect and read are
   verified in the running app.
3. Exercise Write and Wipe through the UI with a T5577 on the antenna. Both are
   implemented and both refuse to run unless `lf t55xx detect` confirms a
   writable, non-passworded T55xx, but neither has been clicked yet.

### A note on automating the UI

Driving the app with `System Events` coordinate clicks is unreliable — the
window loses frontmost while the machine is in use and clicks land in other
applications. Use accessibility references instead; the controls carry
identifiers (`connectToggle`, `read`, `write`, `wipe`, `tagID`).

Setting the text field's value through accessibility updates the `NSTextField`
but does not propagate to the SwiftUI binding, so Write stays disabled. The ID
has to be typed, or set in code.
