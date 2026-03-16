# swiftui-render

Headless SwiftUI renderer CLI. Compiles `.swift` files on the fly, links against SwiftUI, and produces `.png` output -- no Xcode project or Simulator required.

## Build & test

```sh
swift build                    # debug build
swift build -c release         # release build
swift test                     # run all tests
Scripts/install.sh             # build + install to ~/.local/bin
Scripts/build-daemon.sh        # build the daemon app separately
```

The binary lands at `.build/release/swiftui-render` (release) or `.build/debug/swiftui-render` (debug).

## Architecture

### Entry point

`SwiftUIRender.swift` -- registers all subcommands via ArgumentParser. Default subcommand is `Render`.

### Subcommands

- **render** (default): compile + run + output PNG
- **inspect**: render with debug bounding boxes + view tree dump
- **snapshot**: accessibility tree with @e refs (requires daemon)
- **diff**: side-by-side visual diff of two views
- **preview**: file watcher that re-renders on change via daemon
- **daemon**: manage the hot-reload Catalyst daemon (start/stop/build/status)
- **cache**: manage compiled binary cache (info/clear)

### Three rendering backends

1. **ImageRenderer** (default, `--backend default`): Uses SwiftUI's `ImageRenderer` API. Pure AppKit, fastest. Good for simple views.
2. **AppHost** (`--backend apphost`): Offscreen `NSWindow` + `NSHostingView`. Handles views needing a window context.
3. **Catalyst** (`--backend catalyst`): Full Mac Catalyst app (arm64-apple-ios17.0-macabi). Most accurate iOS rendering. Required for device frames, inspect, snapshot.

### Pipeline

1. `RenderOptions` resolves CLI flags into a `RenderConfig`
2. `TemplateGenerator` produces a Swift source file that imports the user's `Preview` struct and renders it
3. `SwiftCompiler` invokes `xcrun swiftc` to compile the user file + template into a binary
4. `CompileAndRender` orchestrates the pipeline with binary caching (SHA-256 of content + options)
5. The compiled binary runs headlessly and writes the PNG

### Daemon mode

For fast iteration, the daemon keeps a Catalyst host app running. New views are compiled into dylibs and hot-loaded via `dlopen`. Communication is file-based:

- `/tmp/swiftui-render-daemon/daemon.pid` -- PID file
- `/tmp/swiftui-render-daemon/request.json` -- render parameters
- `/tmp/swiftui-render-daemon/preview.dylib` -- compiled view
- `/tmp/swiftui-render-daemon/reload.trigger` -- signals daemon to reload
- `/tmp/swiftui-render-daemon/reload.done` -- result from daemon

### Caching

Compiled binaries are cached at `~/.cache/swiftui-render/` keyed by SHA-256(content + options). Identical renders skip compilation entirely. Use `swiftui-render cache clear` to purge.

## Conventions

- **Input files must define `struct Preview: View`**. This is the entry point the template generator looks for. Other types/extensions in the file are fine.
- **Output goes to stdout** (render info like `780x1688 @2x (42KB) -> /path`). Diagnostics go to stderr.
- **JSON mode** (`--json`) outputs machine-readable JSON to stdout.
- **Errors** use `LocalizedError` with descriptive messages. Compilation errors are cleaned to show only filenames, not full paths.

## Key files

| File | Purpose |
|------|---------|
| `Options.swift` | CLI flags, size presets, input validation |
| `RenderConfig.swift` | Immutable config struct, cache key generation |
| `TemplateGenerator.swift` | Generates Swift source for each backend (largest file) |
| `SwiftCompiler.swift` | `swiftc` invocation for executables and dylibs |
| `CompileAndRender.swift` | Full compile-cache-run pipeline |
| `DaemonClient.swift` | Daemon IPC, auto-start, bridge.swift generation |
| `DiffComposer.swift` | AppKit-based side-by-side image composition |
