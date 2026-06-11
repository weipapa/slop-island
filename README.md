<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-black?style=flat-square" />
  <img src="https://img.shields.io/badge/swift-5.9-F05138?style=flat-square&logo=swift&logoColor=white" />
  <img src="https://github.com/user/slop-island/actions/workflows/ci.yml/badge.svg" />
</p>

<h1 align="center">Slop Island</h1>

<p align="center">
  <b>Your MacBook notch is a Claude Code dashboard now.</b>
  <br/>
  <sub>Monitor sessions, approve permissions, answer questions — all from the notch.</sub>
</p>

<br/>

## What it does

Slop Island turns the MacBook notch into a live control panel for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Hover the notch to see all running sessions. Click to expand.

**Session monitoring** — Watches Claude Code transcripts via FSEvents. Shows what each session is doing in real time: which tool is running, what file is being edited, how long it's been going.

**Permission requests** — Intercepts `PermissionRequest` hooks before Claude's own TUI shows them. Approve or deny from the notch with one click (or `⌘Y` / `⌘N`). No terminal switching needed.

**Interactive questions** — When Claude calls `AskUserQuestion`, the options appear in the notch as a paginated UI. Pick your answer, and it gets injected into the terminal via synthetic keystrokes.

**Chat preview** — Tap a session to see its conversation history rendered inline, with markdown support and tool call details.

## How it works

```
┌─────────────────────────────────────────────────────┐
│  Claude Code                                        │
│  ┌──────────────┐     settings.json hooks           │
│  │ Session JSONL │──┐  (PermissionRequest,           │
│  │ transcripts   │  │   UserPromptSubmit, Stop, ...) │
│  └──────────────┘  │                                │
│                    │  ┌──────────────────┐           │
│                    │  │ slopisland-hook.py│           │
│                    │  └────────┬─────────┘           │
└────────────────────┼──────────┼──────────────────────┘
                     │          │
              FSEvents│    Unix socket
              (file   │   ~/Library/Application Support/
              changes)│    SlopIsland/hook.sock
                     │          │
┌────────────────────┼──────────┼──────────────────────┐
│  Slop Island       │          │                      │
│  ┌─────────────┐   │   ┌──────┴──────┐               │
│  │AgentMonitor │◄──┘   │ HookServer  │               │
│  │(transcript  │       │(permission  │               │
│  │ tail reader)│       │ lifecycle)  │               │
│  └──────┬──────┘       └──────┬──────┘               │
│         │                     │                      │
│         └──────┬──────────────┘                      │
│                ▼                                     │
│         ┌─────────────┐    ┌──────────────┐          │
│         │SessionStore │───▶│  NotchPanel  │          │
│         │(state       │    │  (SwiftUI)   │          │
│         │ machine)    │    └──────────────┘          │
│         └─────────────┘                              │
└──────────────────────────────────────────────────────┘
```

Two independent data channels feed into a single `SessionStore`:

1. **Transcript monitoring** — `AgentMonitor` watches `~/.claude/projects/` with FSEvents. When a `.jsonl` transcript grows, it reads only the new bytes and extracts the latest action (tool calls, thinking state, session end).

2. **Hook server** — On launch, Slop Island installs a Python hook into Claude Code's `settings.json`. The hook sends events over a private Unix socket. For permission requests, the socket stays open until the user decides — the response flows back to Claude Code through the same connection.

## Install

### Requirements

- macOS 14+ with a notch (MacBook Pro/Air 2021+)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed
- Python 3.14+ (for the hook script)
- Accessibility permission (for keyboard injection on question answers)

### Build from source

```bash
git clone https://github.com/user/slop-island.git
cd slop-island

xcodebuild build \
  -project SlopIsland.xcodeproj \
  -scheme SlopIsland \
  -configuration Release \
  -derivedDataPath build

# The app is at:
# build/Build/Products/Release/SlopIsland.app
```

Or open `SlopIsland.xcodeproj` in Xcode and hit Run.

### First launch

1. Run `SlopIsland.app`. It auto-installs its hook into `~/.claude/settings.json`.
2. Grant Accessibility permission when prompted (System Settings > Privacy & Security > Accessibility).
3. Start a `claude` session in any terminal. Hover the notch — your session appears.

## Usage

| Action | How |
|---|---|
| Open the panel | Hover the notch for 200ms, or click it |
| Close the panel | Move mouse away, or click the notch |
| Approve permission | Click **Allow** or press `⌘Y` |
| Deny permission | Click **Deny** or press `⌘N` |
| Answer a question | Click an option — answer is sent to the terminal |
| View chat history | Click a session row |
| Jump to terminal | Click a non-question session — focuses the terminal tab |
| Settings | Gear icon in the panel header |
| Quit | Power icon in the panel header |

## Project structure

```
SlopIsland/
├── Core/
│   ├── AppSettings.swift          # User preferences
│   ├── IslandViewModel.swift      # Panel state machine + mouse tracking
│   ├── NotchGeometry.swift        # Notch position detection
│   └── LoginItem.swift            # Launch at login
├── Monitor/
│   ├── AgentMonitor.swift         # FSEvents transcript watcher
│   ├── HookServer.swift           # Unix socket server for hook events
│   └── HookInstaller.swift        # Deploys hook into Claude Code settings
├── Models/
│   ├── SessionPhase.swift         # idle → processing → waiting → ended
│   ├── SessionEvent.swift         # All state transitions
│   ├── UserQuestion.swift         # AskUserQuestion model
│   └── ChatMessage.swift          # Transcript message types
├── Services/
│   ├── KeySender.swift            # CGEvent keyboard injection
│   ├── TerminalFocuser.swift      # Focus correct terminal tab
│   ├── ProcessTreeBuilder.swift   # Walk process tree to find terminals
│   ├── ConversationParser.swift   # Parse JSONL transcripts
│   └── ChatHistoryManager.swift   # Conversation history cache
├── Store/
│   └── SessionStore.swift         # Central state, @Observable
├── UI/
│   ├── Views/
│   │   ├── IslandView.swift       # Root view with notch shape + animation
│   │   ├── SessionListContentView # Session list
│   │   ├── QuestionContentView    # Paginated question UI
│   │   ├── PermissionRequestView  # Allow/Deny prompt
│   │   └── ChatContentView        # Conversation viewer
│   ├── Window/
│   │   ├── NotchPanel.swift       # Borderless window positioned at notch
│   │   └── NotchViewController    # Hosting controller
│   └── Components/
│       ├── MarkdownTextView       # Markdown renderer
│       └── ProcessingSpinner      # Activity indicator
└── Resources/
    └── slopisland-hook.py         # Python bridge script
```

## How the hook works

Slop Island registers a Python script as a Claude Code hook for six events: `PermissionRequest`, `UserPromptSubmit`, `SessionStart`, `Notification`, `Stop`, and `SessionEnd`.

For most events, the hook is fire-and-forget — it sends the event over the Unix socket and exits.

For `PermissionRequest`, the hook **blocks**: it sends the event, then waits (up to 5 minutes) for the app to write back `{"decision": "allow"}` or `{"decision": "deny"}`. The response is translated into Claude Code's [hook output format](https://docs.anthropic.com/en/docs/claude-code/hooks) and printed to stdout.

The hook is fully isolated — it uses its own socket path under `~/Library/Application Support/SlopIsland/` and doesn't interfere with other tools.

## Uninstall

Slop Island only touches two locations:

```bash
# Remove the app's data and socket
rm -rf ~/Library/Application\ Support/SlopIsland/

# The hook entries in settings.json are cleaned up automatically on quit,
# or you can remove entries containing "slopisland-hook.py" from:
# ~/.claude/settings.json
```

## License

MIT
