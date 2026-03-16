# swiftui-render

Headless SwiftUI renderer -- render views to PNG from the command line, no Xcode or Simulator required.

AI agents can write SwiftUI but can't see it. `swiftui-render` closes that feedback loop: write a view, render it, check the pixels, iterate -- all from the terminal.

```sh
swiftui-render MyView.swift --iphone --dark -o screenshot.png
# 780x1688 @2x (42KB) -> screenshot.png
```

## Install

### From source (recommended)

```sh
git clone https://github.com/olliewagner/swiftui-render.git
cd swiftui-render
Scripts/install.sh
```

This builds a release binary and installs it to `~/.local/bin/swiftui-render`.

### Manual

```sh
swift build -c release
cp -f .build/release/swiftui-render ~/.local/bin/swiftui-render
```

### Homebrew

```sh
brew tap olliewagner/swiftui-render
brew install swiftui-render
```

### Requirements

- macOS 13+ (Ventura or later)
- Xcode Command Line Tools (`xcode-select --install`)
- Apple Silicon (arm64) for Catalyst backend

## Quick start

Create a Swift file with a `struct Preview: View`:

```swift
// MyCard.swift
import SwiftUI

struct Preview: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "star.fill")
                .font(.largeTitle)
                .foregroundColor(.yellow)
            Text("Hello, world!")
                .font(.headline)
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }
}
```

Render it:

```sh
swiftui-render MyCard.swift
# 780x1688 @2x (18KB) -> /tmp/swiftui-render.png
```

## Commands

### `render` (default)

Render a SwiftUI view to PNG.

```sh
# Basic render
swiftui-render render MyView.swift

# iPhone 15 size, dark mode, custom output path
swiftui-render render MyView.swift --iphone --dark -o hero.png

# Custom dimensions
swiftui-render render MyView.swift -w 375 -h 667

# iPhone with device frame (Dynamic Island, status bar, home indicator)
swiftui-render render MyView.swift --device-frame --iphone-pro-max

# JSON output for scripting
swiftui-render render MyView.swift --json
# {"width":780,"height":1688,"size":43520,"path":"/tmp/swiftui-render.png","time_ms":1832}

# Skip cache for fresh render
swiftui-render render MyView.swift --no-cache

# Use daemon for faster re-renders
swiftui-render render MyView.swift --daemon
```

Since `render` is the default subcommand, you can omit it:

```sh
swiftui-render MyView.swift --iphone
```

### `inspect`

Render with debug annotations -- colored bounding boxes around every view, plus a text-based view tree dump.

```sh
swiftui-render inspect MyView.swift --iphone
# 780x1688 @2x (52KB) -> /tmp/swiftui-render.png
# View tree:
#   Box 390x44
#     Text 200x24 @ (95,10)
#     Image 32x32 @ (179,60)
```

### `snapshot`

Output an accessibility tree with element references, similar to agent-browser's snapshot command.

```sh
swiftui-render snapshot MyView.swift --iphone
# @e1 Text "Hello, world!"
# @e2 Button "Submit"
# @e3 Image "star.fill"
```

Requires the daemon (auto-started if not running).

### `diff`

Visual side-by-side diff of two SwiftUI views. Renders both, composites them with "Before" / "After" labels and a separator.

```sh
swiftui-render diff Before.swift After.swift --iphone
# 1600x1718 (87KB) -> /tmp/swiftui-render-diff.png

swiftui-render diff OldCard.swift NewCard.swift -o comparison.png
```

### `preview`

Live preview -- watches the file for changes and re-renders automatically via the daemon.

```sh
swiftui-render preview MyView.swift --iphone
# Watching MyView.swift -- Ctrl+C to stop
# ---
# 780x1688 @2x (42KB) -> /tmp/swiftui-render.png
```

### `daemon`

Manage the hot-reload daemon. The daemon keeps a Catalyst app running in the background so re-renders skip compilation of the host app, making iteration ~5x faster.

```sh
swiftui-render daemon status     # Check if daemon is running
swiftui-render daemon start      # Start the daemon
swiftui-render daemon stop       # Stop the daemon
swiftui-render daemon build      # Build daemon from source
```

### `cache`

Manage the compiled binary cache. Binaries are cached by content hash so identical renders skip compilation entirely.

```sh
swiftui-render cache info        # Show cache size and entry count
swiftui-render cache clear       # Clear all cached binaries
```

## Size presets

| Flag | Device | Points | Pixels @2x |
|------|--------|--------|------------|
| `--iphone` | iPhone 15 | 390x844 | 780x1688 |
| `--iphone-se` | iPhone SE | 375x667 | 750x1334 |
| `--iphone-pro-max` | iPhone 15 Pro Max | 430x932 | 860x1864 |
| `--ipad` | iPad Pro 12.9" | 1024x1366 | 2048x2732 |
| `--widget-small` | Small widget | 170x170 | 340x340 |
| `--widget-medium` | Medium widget | 364x170 | 728x340 |
| `--widget-large` | Large widget | 364x382 | 728x764 |

Or pass custom dimensions: `-w 320 -h 480`

## Shell completions

swiftui-render uses Swift Argument Parser, which supports generating shell completions:

```sh
# Bash
swiftui-render --generate-completion-script bash > ~/.bash_completions/swiftui-render
source ~/.bash_completions/swiftui-render

# Zsh
swiftui-render --generate-completion-script zsh > ~/.zsh/completions/_swiftui-render
# Add ~/.zsh/completions to your fpath in .zshrc

# Fish
swiftui-render --generate-completion-script fish > ~/.config/fish/completions/swiftui-render.fish
```

## Why this exists

Xcode Previews require Xcode to be open, a project file, and a human at the keyboard. They don't work from a terminal, a CI pipeline, or an AI agent's tool loop.

`swiftui-render` is a single binary that takes a `.swift` file and produces a `.png`. No Xcode project. No Simulator. No GUI. Just `stdin -> pixels`.

This makes it possible to:

- **Give AI agents eyes.** An LLM writes SwiftUI, renders it, reads the screenshot, and iterates -- fully autonomous visual development.
- **Screenshot testing in CI.** Render views on every PR and diff against baselines.
- **Rapid prototyping.** Edit a file, render, check -- without waiting for Xcode to index.
- **Design review automation.** Render every screen variant (light/dark, iPhone/iPad, all widget sizes) in one script.

## How it works

swiftui-render compiles your Swift file on the fly, links it against the SwiftUI framework, and runs the resulting binary headlessly. There are three rendering backends:

```
                    ┌─────────────────────────────────────────┐
                    │              swiftui-render              │
                    │          (CLI / ArgumentParser)          │
                    └──────────┬──────────┬──────────┬────────┘
                               │          │          │
                    ┌──────────▼──┐ ┌─────▼─────┐ ┌─▼──────────┐
                    │ ImageRenderer│ │  AppHost  │ │  Catalyst  │
                    │  (default)   │ │ (NSWindow)│ │(Mac Catalyst)│
                    └──────────────┘ └───────────┘ └────────────┘
```

### ImageRenderer (default)

Uses SwiftUI's `ImageRenderer` API (macOS 13+). Fastest option. Renders entirely in-process without creating any windows.

Best for: simple views, text, colors, shapes, SF Symbols.

```sh
swiftui-render MyView.swift                    # uses ImageRenderer by default
swiftui-render MyView.swift --backend default  # explicit
```

### AppHost

Creates an offscreen `NSWindow` with `NSHostingView`, renders via `displayIgnoringOpacity`. Handles more complex view hierarchies than ImageRenderer.

Best for: views that need a window context, complex animations frozen at a frame.

```sh
swiftui-render MyView.swift --backend apphost
```

### Catalyst (Mac Catalyst)

Compiles as a Mac Catalyst app (`arm64-apple-ios17.0-macabi`), runs with full UIKit infrastructure. Most accurate iOS rendering, supports `UIHostingController`, device frames, accessibility tree, debug annotations.

Best for: pixel-accurate iOS screenshots, device frames, inspect/snapshot commands.

```sh
swiftui-render MyView.swift --backend catalyst
```

The daemon also uses Catalyst -- it keeps a host app running and hot-loads your view as a dylib, so re-renders skip the full compilation cycle.

## Input file convention

Every input file must define a `struct Preview: View`. This is the entry point that swiftui-render looks for:

```swift
import SwiftUI

struct Preview: View {
    var body: some View {
        // Your view here
    }
}
```

You can define helper types, extensions, and other structs in the same file -- just make sure `struct Preview: View` exists.

## Comparison

| | swiftui-render | Xcode Previews | swift-snapshot-testing | Prefire |
|---|---|---|---|---|
| Xcode required | No | Yes | Yes (project) | Yes (project) |
| Simulator required | No | No | No | Yes |
| Works from CLI | Yes | No | Partially | No |
| AI agent compatible | Yes | No | No | No |
| Hot reload | Yes (daemon) | Yes | No | No |
| Device frames | Yes | Yes | No | No |
| Accessibility tree | Yes | Limited | No | No |
| Visual diff | Yes | No | Yes | Yes |
| CI-friendly | Yes | No | Yes | Partially |
| Setup required | `swift build` | Xcode project | SPM + XCTest | SPM + Xcode |
| Input format | Single .swift file | Xcode project | XCTest case | Xcode project |

## Project structure

```
swiftui-render/
├── Sources/SwiftUIRender/
│   ├── SwiftUIRender.swift          # Entry point, subcommand registration
│   ├── Options.swift                # Shared CLI options, size presets
│   ├── RenderConfig.swift           # Render configuration, cache keys
│   ├── Commands/
│   │   ├── Render.swift             # Default render command
│   │   ├── Inspect.swift            # Debug annotations + view tree
│   │   ├── Snapshot.swift           # Accessibility tree output
│   │   ├── DiffCommand.swift        # Side-by-side visual diff
│   │   ├── PreviewCommand.swift     # File watcher + live re-render
│   │   ├── DaemonCommand.swift      # Daemon management (start/stop/build)
│   │   └── CacheCommand.swift       # Cache management (info/clear)
│   ├── Compilation/
│   │   └── SwiftCompiler.swift      # swiftc invocation, dylib compilation
│   ├── Renderers/
│   │   ├── CompileAndRender.swift   # Compile-and-run pipeline with caching
│   │   └── DaemonClient.swift       # Daemon IPC (file-based protocol)
│   ├── PostProcessing/
│   │   └── DiffComposer.swift       # Side-by-side image composition
│   └── Templates/
│       └── TemplateGenerator.swift  # Swift source generation for each backend
├── Tests/
│   └── SwiftUIRenderTests.swift     # Unit + integration tests
├── Scripts/
│   ├── install.sh                   # Build and install CLI + daemon
│   └── build-daemon.sh              # Build daemon app separately
├── Formula/
│   └── swiftui-render.rb            # Homebrew formula (template)
└── Package.swift
```

## License

MIT
