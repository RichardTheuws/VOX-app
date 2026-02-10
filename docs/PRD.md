# PRD: VOX — Voice-Operated Development Assistant

**Product**: VOX (Voice-Operated eXecution)
**Versie**: 0.1.0 (PRD)
**Datum**: 2026-02-10
**Auteur**: Theuws Development
**Brand**: tools.theuws.com
**Status**: DRAFT

---

## Context

Developers besteden uren per dag aan het typen van terminal commands, navigeren door IDE's, en wachten op LLM-responses die ze vervolgens moeten lezen. Met de opkomst van AI-powered development tools (Claude Code, Cursor, Windsurf) is de bottleneck verschoven van "code schrijven" naar "commands invoeren en output verwerken".

**VOX** lost dit op door spraakgestuurde development mogelijk te maken: je praat tegen je Mac, VOX stuurt commands naar je terminal of IDE, en leest de response samengevat terug. Geen volledige LLM-outputs meer — alleen wat je nodig hebt.

**Doelgroep**: Developers die macOS gebruiken met AI-powered tools (Claude Code, Cursor, Windsurf, VS Code).

---

## 1. Product Vision

### One-liner
> "Talk to your terminal. Hear what matters."

### Core Value Proposition
VOX is een open-source macOS menu bar app waarmee developers via spraak hun terminal en IDE's bedienen, en configureerbare audio-samenvattingen van responses ontvangen.

### Kernprincipes
1. **Privacy-first**: Alle STT gebeurt on-device via Hex/Whisper
2. **Developer-first**: Gebouwd door developers, voor developers
3. **Configureerbaar**: Jij bepaalt hoeveel je hoort (niets, bevestiging, samenvatting, volledig)
4. **Non-invasive**: Menu bar app, geen venster dat in de weg zit
5. **Open source**: MIT-licensed, community-driven

---

## 2. Technische Architectuur

### Programmeertaal: Swift 6 + SwiftUI (macOS-only)

**Waarom Swift in februari 2026:**

| Criterium | Swift/SwiftUI | Tauri/Rust | Electron |
|-----------|--------------|------------|----------|
| macOS systeemintegratie | Native (Accessibility, menu bar, hotkeys) | Beperkt via FFI | Beperkt |
| STT integratie (Hex/WhisperKit) | Native Swift interop | Vereist bridging | Vereist bridging |
| Binary size | ~15MB | ~8MB | ~150MB+ |
| RAM usage | ~30-50MB | ~40-60MB | ~200MB+ |
| Apple Silicon optimalisatie | Native, Core ML, ANE | Goed via LLVM | Matig |
| Terminal/shell integratie | NSTask, Process API | std::process | child_process |
| Open source community (macOS tools) | Groeiend (Hex, Ice, Loop) | Groeiend (Tauri ecosystem) | Gevestigd |

**Conclusie**: Swift 6 is de optimale keuze voor een macOS-only developer tool dat diep integreert met het OS, Hex (ook Swift), en Apple Silicon hardware.

### Architectuurdiagram

```
┌─────────────────────────────────────────────────────┐
│                    VOX (Menu Bar App)                │
│  ┌──────────┐  ┌──────────┐  ┌───────────────────┐  │
│  │ Voice    │  │ Command  │  │ Response          │  │
│  │ Input    │  │ Router   │  │ Processor         │  │
│  │ Module   │  │          │  │                   │  │
│  └────┬─────┘  └────┬─────┘  └────┬──────────────┘  │
│       │              │              │                 │
│  ┌────▼─────┐  ┌────▼─────┐  ┌────▼──────────────┐  │
│  │ Hex      │  │ Terminal │  │ TTS Engine        │  │
│  │ Bridge   │  │ Executor │  │ (Kokoro/Piper/    │  │
│  │ (STT)    │  │          │  │  ElevenLabs/Say)  │  │
│  └──────────┘  └────┬─────┘  └───────────────────┘  │
│                     │                                │
│              ┌──────▼──────┐                         │
│              │ App         │                         │
│              │ Connectors  │                         │
│              │ (Terminal,  │                         │
│              │  VS Code,   │                         │
│              │  Cursor,    │                         │
│              │  Windsurf)  │                         │
│              └─────────────┘                         │
└─────────────────────────────────────────────────────┘
```

### Core Modules

1. **Voice Input Module** — Ontvangt getranscribeerde tekst van Hex
2. **Command Router** — Interpreteert spraak en routeert naar juiste target app
3. **Terminal Executor** — Voert shell commands uit via `Process` API
4. **App Connectors** — Protocol-based plugins voor IDE-integratie
5. **Response Processor** — Filtert/samenvat LLM output op basis van verbosity setting
6. **TTS Engine** — Spreekt response uit via configureerbare TTS backend

---

## 3. MoSCoW Prioritering — Ondersteunde Apps

### MUST Have (v0.1)
| App | Integratiemethode | Functionaliteit |
|-----|-------------------|-----------------|
| **Terminal.app / iTerm2** | `Process` API (stdin/stdout) | Commands uitvoeren, output lezen |
| **Claude Code CLI** | Terminal pipe (claude code draait in terminal) | Prompts dicteren, response samenvatten |
| **Zsh/Bash shell** | Direct shell execution | Willekeurige commands |

### SHOULD Have (v0.2)
| App | Integratiemethode | Functionaliteit |
|-----|-------------------|-----------------|
| **VS Code** | CLI (`code` command) + Extension API | Bestanden openen, commands uitvoeren |
| **Cursor** | CLI + Extension API (VS Code-compatible) | AI prompts dicteren, responses samenvatten |
| **Windsurf** | CLI + Extension API (VS Code-fork) | AI prompts dicteren, responses samenvatten |

### COULD Have (v0.3+)
| App | Integratiemethode | Functionaliteit |
|-----|-------------------|-----------------|
| **Antigravity** | API/CLI (indien beschikbaar) | AI-interactie via voice |
| **Git operations** | Terminal git commands | Commit messages dicteren, status opvragen |
| **Docker** | Terminal docker commands | Container management via voice |
| **SSH sessions** | Terminal SSH pipe | Remote server commands via voice |

### WON'T Have (out of scope v1.0)
- Browser-based tools (ChatGPT web, Claude web)
- Mobile ondersteuning
- Windows/Linux ondersteuning
- Video conferencing integratie
- Volledige IDE refactoring (alleen commands, niet visuele UI-manipulatie)

---

## 4. Response Verbosity System

### Het kernprobleem
LLMs produceren lange responses. Als developer wil je niet 500 woorden horen voorgelezen. VOX biedt 4 verbosity levels:

### Verbosity Levels

| Level | Naam | Wat je hoort | Voorbeeld |
|-------|------|-------------|-----------|
| 0 | **Silent** | Niets (alleen visuele indicator) | *(stilte, groen vinkje in menu bar)* |
| 1 | **Ping** | Alleen status bevestiging | *"Klaar."* / *"Fout opgetreden."* |
| 2 | **Summary** (default) | AI-gegenereerde samenvatting (1-2 zinnen) | *"De functie is toegevoegd aan utils.py. 3 tests slagen."* |
| 3 | **Full** | Volledige response voorgelezen | *(volledige LLM output)* |

### Configuratie-opties
- **Globaal default level**: Stel in via Settings (standaard: Level 2 - Summary)
- **Per-app override**: Bijv. Terminal op Level 1, Claude Code op Level 2
- **Per-command override**: Zeg "summarize" of "full" voor/na een command
- **Error escalation**: Bij errors automatisch naar Level 2+ (configureerbaar)
- **Samenvatting taal**: Nederlands of Engels (configureerbaar, default: taal van input)

### Samenvatting Engine
- Voor Level 2 (Summary): Gebruik een lokaal LLM (bijv. Ollama met een klein model) of een simpele regel-based extractor die:
  - Succes/faal status detecteert
  - Bestandsnamen en nummers extraheert
  - Error messages identificeert
  - Dit comprimeert tot 1-2 zinnen
- Fallback: Als geen lokaal LLM beschikbaar is, gebruik heuristische samenvatting (eerste regel + laatste regel + error detection)

---

## 5. User Interface — Alle Schermen

### Brand Design Tokens (tools.theuws.com)

```
Kleuren (Dark Mode - Default):
  --bg:          #111111 (Void Black)
  --surface:     #1A1A1A (Dark Grey)
  --text:        #F4F4F4 (Off-White)
  --text-muted:  #AAAAAA
  --accent:      #00629B (Deep Blue)
  --border:      #333333
  --success:     #28C76F
  --warning:     #FF9F43
  --error:       #FF4757

Kleuren (Light Mode):
  --bg:          #FFFFFF
  --surface:     #F4F4F4
  --text:        #111111
  --accent:      #00629B
  --border:      #E0E0E0

Typography:
  Headings:  Titillium Web (700, 600)
  Body:      Inter (400, 500)
  Monospace: SF Mono / Menlo (voor terminal output)

Components:
  Border radius: 4px (buttons), 8px (cards)
  Shadows: 0 4px 6px rgba(0,0,0,0.3)
  Transitions: 0.3s ease
```

---

### Scherm 1: Menu Bar Icon + Dropdown

**Locatie**: macOS menu bar (rechts)

```
┌──────────────────────────────────────┐
│  [VOX icon]  ← Klik = dropdown       │
│                                      │
│  ┌────────────────────────────────┐  │
│  │ 🎤 VOX                   v0.1 │  │
│  │ ─────────────────────────────  │  │
│  │ Status: Listening / Idle       │  │
│  │ Target: Terminal.app           │  │
│  │ Verbosity: ●●○○ Summary       │  │
│  │ ─────────────────────────────  │  │
│  │ 🔵 Last: "git status"         │  │
│  │    → 3 files modified          │  │
│  │ ─────────────────────────────  │  │
│  │ ⌥Space  Push-to-talk          │  │
│  │ ⌥⇧Space Toggle always-listen  │  │
│  │ ─────────────────────────────  │  │
│  │ ⚙ Settings...                 │  │
│  │ 📋 History                    │  │
│  │ ⏻ Quit VOX                    │  │
│  └────────────────────────────────┘  │
└──────────────────────────────────────┘
```

**Gedrag**:
- Icon verandert kleur: Idle (grijs), Listening (blauw pulsend), Processing (blauw draaiend), Error (rood)
- Dropdown toont altijd laatste command + response preview
- Keyboard shortcut: `⌥Space` voor push-to-talk (configureerbaar)

---

### Scherm 2: Push-to-Talk Overlay

**Locatie**: Zwevend HUD-venster, gecentreerd op scherm

```
┌─────────────────────────────────────┐
│                                     │
│          ┌───────────────┐          │
│          │               │          │
│          │   ◉ ◉ ◉ ◉    │  ← Waveform visualizer
│          │  (pulserend)  │          │
│          │               │          │
│          └───────────────┘          │
│                                     │
│     "open het bestand utils.py"     │  ← Live transcriptie
│                                     │
│     Target: VS Code                 │  ← Actieve target
│     ⌥Space to stop                  │          │
└─────────────────────────────────────┘
```

**Gedrag**:
- Verschijnt bij `⌥Space` (ingedrukt houden = push-to-talk, kort indrukken = toggle)
- Toont live transcriptie van spraak (via Hex)
- Waveform visualizer in accent blauw (#00629B)
- Semi-transparante achtergrond (blur effect, macOS vibrancy)
- Verdwijnt automatisch na command execution
- Target app detectie: toont welke app momenteel focus heeft

---

### Scherm 3: Settings — General

```
┌─────────────────────────────────────────────────┐
│ VOX Settings                              [×]   │
│ ─────────────────────────────────────────────── │
│ [General] [Voice] [Apps] [TTS] [Advanced]       │
│ ─────────────────────────────────────────────── │
│                                                  │
│ GENERAL                                          │
│                                                  │
│ Launch at login          [Toggle: ON]            │
│ Menu bar icon style      [Dropdown: Monochrome]  │
│ Theme                    [Dropdown: System]      │
│                          ○ Dark  ○ Light  ● System│
│                                                  │
│ KEYBOARD SHORTCUTS                               │
│                                                  │
│ Push-to-talk             [⌥Space]     [Change]   │
│ Toggle always-listen     [⌥⇧Space]   [Change]   │
│ Cancel current command   [Escape]     [Change]   │
│ Cycle verbosity          [⌥V]        [Change]   │
│ Quick target switch      [⌥T]        [Change]   │
│                                                  │
│ LANGUAGE                                         │
│                                                  │
│ Input language           [Dropdown: Auto-detect] │
│ Response language        [Dropdown: Follow input]│
│                                                  │
└─────────────────────────────────────────────────┘
```

---

### Scherm 4: Settings — Voice Input (STT)

```
┌─────────────────────────────────────────────────┐
│ VOX Settings                              [×]   │
│ ─────────────────────────────────────────────── │
│ [General] [Voice] [Apps] [TTS] [Advanced]       │
│ ─────────────────────────────────────────────── │
│                                                  │
│ SPEECH-TO-TEXT ENGINE                             │
│                                                  │
│ Engine                   [Dropdown: Hex]         │
│                          ● Hex (recommended)     │
│                          ○ Built-in (WhisperKit) │
│                                                  │
│ Hex Status               ● Connected             │
│ Hex Version              v0.4.2                  │
│ [Open Hex Settings]      [Install Hex]           │
│                                                  │
│ WHISPER MODEL (when using built-in)              │
│                                                  │
│ Model size               [Dropdown: large-v3]    │
│                          Accuracy: ★★★★★         │
│                          Speed: ★★★☆☆            │
│                          RAM: ~1.5GB             │
│                                                  │
│ ACTIVATION MODE                                  │
│                                                  │
│ ● Push-to-talk (hold ⌥Space)                    │
│ ○ Push-to-toggle (press ⌥Space)                 │
│ ○ Voice-activated (wake word: "Hey Vox")         │
│ ○ Always listening                               │
│                                                  │
│ VOICE TEST                                       │
│ [🎤 Test microphone]    Level: ████████░░ 82%   │
│                                                  │
└─────────────────────────────────────────────────┘
```

---

### Scherm 5: Settings — Apps (Target Configuration)

```
┌─────────────────────────────────────────────────┐
│ VOX Settings                              [×]   │
│ ─────────────────────────────────────────────── │
│ [General] [Voice] [Apps] [TTS] [Advanced]       │
│ ─────────────────────────────────────────────── │
│                                                  │
│ TARGET APPS                                      │
│                                                  │
│ Auto-detect active app   [Toggle: ON]            │
│                                                  │
│ ┌─────────────────────────────────────────────┐ │
│ │ ● Terminal.app          Verbosity: Summary  │ │
│ │   Status: Active        [Configure]         │ │
│ ├─────────────────────────────────────────────┤ │
│ │ ● iTerm2                Verbosity: Summary  │ │
│ │   Status: Active        [Configure]         │ │
│ ├─────────────────────────────────────────────┤ │
│ │ ● Claude Code (CLI)     Verbosity: Summary  │ │
│ │   Status: Active        [Configure]         │ │
│ ├─────────────────────────────────────────────┤ │
│ │ ○ VS Code               Verbosity: Ping     │ │
│ │   Status: Not installed [Install Extension] │ │
│ ├─────────────────────────────────────────────┤ │
│ │ ○ Cursor                Verbosity: Summary  │ │
│ │   Status: Not installed [Install Extension] │ │
│ ├─────────────────────────────────────────────┤ │
│ │ ○ Windsurf              Verbosity: Summary  │ │
│ │   Status: Not detected  [Configure Path]    │ │
│ └─────────────────────────────────────────────┘ │
│                                                  │
│ TARGET ROUTING                                   │
│                                                  │
│ Default target           [Dropdown: Auto-detect] │
│ Fallback target          [Dropdown: Terminal]     │
│                                                  │
│ COMMAND PREFIXES (optional voice routing)         │
│ "terminal ..."  → Terminal.app                    │
│ "code ..."      → VS Code / Cursor / Windsurf    │
│ "claude ..."    → Claude Code CLI                 │
│ "git ..."       → Git (via active terminal)       │
│                                                  │
└─────────────────────────────────────────────────┘
```

---

### Scherm 6: Settings — TTS (Text-to-Speech Output)

```
┌─────────────────────────────────────────────────┐
│ VOX Settings                              [×]   │
│ ─────────────────────────────────────────────── │
│ [General] [Voice] [Apps] [TTS] [Advanced]       │
│ ─────────────────────────────────────────────── │
│                                                  │
│ TEXT-TO-SPEECH ENGINE                             │
│                                                  │
│ Engine                   [Dropdown: Kokoro]      │
│                          ● Kokoro (recommended,  │
│                            lokaal, 82M params)   │
│                          ○ Piper (lokaal, snel)  │
│                          ○ macOS Say (ingebouwd) │
│                          ○ ElevenLabs (cloud)    │
│                          ○ Disabled              │
│                                                  │
│ KOKORO SETTINGS                                  │
│ Voice                    [Dropdown: af_heart]    │
│ Speed                    [Slider: 1.0x ─●── 2.0x]│
│ [▶ Preview voice]                                │
│                                                  │
│ ELEVENLABS SETTINGS (if selected)                │
│ API Key                  [••••••••] [Show/Hide]  │
│ Voice ID                 [Dropdown: Rachel]      │
│ [▶ Preview voice]                                │
│                                                  │
│ DEFAULT VERBOSITY                                │
│                                                  │
│ Global default           [Slider]                │
│ ○ Silent  ○ Ping  ● Summary  ○ Full             │
│                                                  │
│ Error escalation         [Toggle: ON]            │
│ Error verbosity          [Dropdown: Summary]     │
│                                                  │
│ AUDIO OUTPUT                                     │
│ Output device            [Dropdown: System Default]│
│ Volume                   [Slider: ████████░░ 80%] │
│ Interrupt on new command [Toggle: ON]             │
│                                                  │
└─────────────────────────────────────────────────┘
```

---

### Scherm 7: Settings — Advanced

```
┌─────────────────────────────────────────────────┐
│ VOX Settings                              [×]   │
│ ─────────────────────────────────────────────── │
│ [General] [Voice] [Apps] [TTS] [Advanced]       │
│ ─────────────────────────────────────────────── │
│                                                  │
│ SUMMARY ENGINE                                   │
│                                                  │
│ Summarization method     [Dropdown: Heuristic]   │
│                          ● Heuristic (geen LLM)  │
│                          ○ Ollama (lokaal LLM)   │
│                          ○ Claude API             │
│                          ○ OpenAI API             │
│                                                  │
│ Ollama model (if selected)                       │
│ Model                    [Dropdown: llama3.2:3b] │
│ Ollama URL               [localhost:11434]       │
│                                                  │
│ Max summary length       [Slider: 2 zinnen]      │
│                                                  │
│ TERMINAL SETTINGS                                │
│                                                  │
│ Shell                    [Dropdown: Auto-detect]  │
│ Working directory        [Dropdown: Follow terminal]│
│ Command timeout          [Slider: 30s]           │
│ Max output capture       [Slider: 10000 chars]   │
│                                                  │
│ SAFETY                                           │
│                                                  │
│ Confirm destructive commands  [Toggle: ON]       │
│ Destructive patterns:                            │
│   rm -rf, DROP TABLE, git push --force,          │
│   docker rm, sudo, shutdown                      │
│ [Edit patterns...]                               │
│                                                  │
│ LOGGING                                          │
│                                                  │
│ Log commands to file     [Toggle: OFF]           │
│ Log location             [~/. vox/logs/]         │
│                                                  │
│ DATA                                             │
│ [Export settings]  [Import settings]             │
│ [Reset to defaults]                              │
│                                                  │
└─────────────────────────────────────────────────┘
```

---

### Scherm 8: Command History

```
┌─────────────────────────────────────────────────┐
│ VOX History                               [×]   │
│ ─────────────────────────────────────────────── │
│ [Search: ________________] [Filter: All ▼]      │
│ ─────────────────────────────────────────────── │
│                                                  │
│ TODAY                                            │
│ ┌─────────────────────────────────────────────┐ │
│ │ 14:32  🟢 "git status"                     │ │
│ │        → Terminal.app                       │ │
│ │        Summary: 3 files gewijzigd           │ │
│ │        [Copy] [Replay] [Expand]             │ │
│ ├─────────────────────────────────────────────┤ │
│ │ 14:30  🟢 "claude fix de login bug"        │ │
│ │        → Claude Code                        │ │
│ │        Summary: Bug in auth.py gefixt,      │ │
│ │        3 bestanden aangepast.               │ │
│ │        [Copy] [Replay] [Expand]             │ │
│ ├─────────────────────────────────────────────┤ │
│ │ 14:28  🔴 "npm run build"                  │ │
│ │        → Terminal.app                       │ │
│ │        Error: Module not found 'react-dom'  │ │
│ │        [Copy] [Replay] [Expand]             │ │
│ └─────────────────────────────────────────────┘ │
│                                                  │
│ YESTERDAY                                        │
│ ┌─────────────────────────────────────────────┐ │
│ │ 16:45  🟢 "deploy to staging"              │ │
│ │ ...                                         │ │
│ └─────────────────────────────────────────────┘ │
│                                                  │
│ [Clear History]              Showing 24 commands │
└─────────────────────────────────────────────────┘
```

---

### Scherm 9: Destructive Command Confirmation

```
┌─────────────────────────────────────────────────┐
│                                                  │
│     ⚠️  DESTRUCTIVE COMMAND DETECTED             │
│                                                  │
│     Command: rm -rf node_modules/                │
│     Target:  Terminal.app                        │
│                                                  │
│     This command matches a destructive pattern.  │
│     Say "confirm" or "cancel" to proceed.        │
│                                                  │
│     [Cancel]                    [Confirm & Run]  │
│                                                  │
│     Auto-cancel in: 10s                          │
│                                                  │
└─────────────────────────────────────────────────┘
```

---

### Scherm 10: Onboarding / First Run

```
┌─────────────────────────────────────────────────┐
│                                                  │
│           VOX                                    │
│           Voice-Operated eXecution               │
│                                                  │
│     ─────────────────────────────────            │
│                                                  │
│     Step 1/4: Microphone Access                  │
│                                                  │
│     VOX needs microphone access to               │
│     hear your voice commands.                    │
│                                                  │
│     [Grant Access]                               │
│                                                  │
│     ─────────────────────────────────            │
│                                                  │
│     Step 2/4: Install Hex                        │
│                                                  │
│     VOX uses Hex for speech recognition.         │
│     [Download Hex]  [I already have Hex]         │
│                                                  │
│     ─────────────────────────────────            │
│                                                  │
│     Step 3/4: Choose TTS Engine                  │
│                                                  │
│     ● Kokoro (recommended - local, free)         │
│     ○ Piper (local, fast)                        │
│     ○ macOS Say (built-in, basic)                │
│     ○ ElevenLabs (cloud, premium quality)        │
│     [Download Kokoro Model]                      │
│                                                  │
│     ─────────────────────────────────            │
│                                                  │
│     Step 4/4: Test Your Setup                    │
│                                                  │
│     Press ⌥Space and say "hello"                 │
│     [🎤 Test Now]                                │
│                                                  │
│     ✅ "Hello" recognized!                       │
│     🔊 "VOX is ready." played!                   │
│                                                  │
│     [Start Using VOX]                            │
│                                                  │
└─────────────────────────────────────────────────┘
```

---

## 6. Hex Bridge — Integratie Specificatie

### Hoe Hex werkt
Hex is een macOS menu bar app (Swift/SwiftUI) die on-device STT doet via:
- **WhisperKit** (Core ML Whisper model)
- **Parakeet TDT v3** (Core ML via FluidAudio)

### Integratieopties (in volgorde van voorkeur)

1. **Clipboard Bridge** (v0.1 - simpelst)
   - Hex transcribeert spraak → plaatst tekst op clipboard
   - VOX monitort clipboard changes met `NSPasteboard`
   - VOX detecteert of change van Hex komt (via timing + format heuristiek)
   - Pro: Geen aanpassingen aan Hex nodig
   - Con: Deelt clipboard, latency

2. **XPC Service** (v0.2 - ideaal)
   - VOX registreert als XPC client van Hex
   - Hex stuurt transcripties direct naar VOX via IPC
   - Pro: Real-time, dedicated channel
   - Con: Vereist Hex-side support (open PR)

3. **File Watcher** (fallback)
   - Hex schrijft transcripties naar een bekend pad
   - VOX monitort dit bestand met `FSEvents`
   - Pro: Simpel, robuust
   - Con: Disk I/O, iets meer latency

4. **Built-in WhisperKit** (standalone fallback)
   - Als Hex niet geinstalleerd is, gebruik eigen WhisperKit integratie
   - Dezelfde modellen als Hex, maar embedded in VOX
   - Pro: Geen externe dependency
   - Con: Dupliceert functionaliteit, meer RAM

---

## 7. TTS Engine Specificatie

### Tier 1: Kokoro (Recommended Default)
- **Model**: Kokoro-82M (Apache 2.0 license)
- **Kwaliteit**: Vergelijkbaar met ElevenLabs in blind tests
- **Latency**: 40-70ms op GPU, 3-11x realtime op CPU
- **RAM**: ~200MB voor model
- **Voices**: 48+ stemmen, 8 talen
- **Integratie**: Python wrapper via Swift `Process` of native ONNX runtime
- **Apple Silicon**: Ondersteund via MPS (Metal Performance Shaders)

### Tier 2: Piper TTS
- **Model**: ONNX-based VITS models
- **Kwaliteit**: Goed, iets minder natuurlijk dan Kokoro
- **Latency**: Zeer laag (<100ms)
- **RAM**: ~50-100MB
- **Voices**: 100+ voices, vele talen incl. Nederlands
- **Integratie**: CLI binary, makkelijk te wrappen

### Tier 3: macOS `say` (Built-in Fallback)
- **Model**: macOS native TTS
- **Kwaliteit**: Basis, herkenbaar als synthetisch
- **Latency**: Instant
- **RAM**: 0 (OS-level)
- **Integratie**: `NSSpeechSynthesizer` of `AVSpeechSynthesizer`

### Tier 4: ElevenLabs (Cloud Premium)
- **Model**: Proprietary
- **Kwaliteit**: Premium, zeer natuurlijk
- **Latency**: 200-500ms (netwerk)
- **Kosten**: ~$5/maand voor basic plan
- **Integratie**: REST API
- **Vereist**: Internetverbinding + API key

---

## 8. Command Flow — Gedetailleerd

### Happy Path: Voice → Terminal → Response

```
1. User drukt ⌥Space (push-to-talk)
2. VOX toont overlay met waveform
3. User zegt: "git status"
4. Hex transcribeert → "git status"
5. VOX ontvangt transcriptie
6. Command Router herkent: shell command
7. Target: actieve Terminal.app window
8. Terminal Executor runt: git status
9. Output captured: "On branch main\n..."
10. Response Processor:
    - Verbosity = Summary
    - Samenvatting: "Op main branch, 3 bestanden gewijzigd"
11. TTS Engine spreekt samenvatting uit
12. Menu bar icon: groen vinkje (2 seconden)
13. History entry aangemaakt
```

### Flow: Voice → Claude Code → Summarized Response

```
1. User zegt: "claude fix de bug in auth module"
2. Hex transcribeert → "claude fix de bug in auth module"
3. Command Router herkent prefix "claude" → Claude Code target
4. Terminal Executor runt: claude "fix de bug in auth module"
5. VOX monitort stdout stream van Claude Code
6. Claude Code produceert 500+ woorden output
7. Response Processor:
    - Verbosity = Summary
    - Detecteert: bestanden gewijzigd (auth.py, tests/test_auth.py)
    - Detecteert: "Done" / success status
    - Samenvatting: "Auth bug gefixt. 2 bestanden aangepast. Tests slagen."
8. TTS Engine spreekt samenvatting uit
9. Volledige output beschikbaar in History → [Expand]
```

### Flow: Destructive Command

```
1. User zegt: "remove all node modules recursively"
2. Hex transcribeert
3. Command Router interpreteert: "rm -rf node_modules/"
4. Safety check: matched "rm -rf" pattern
5. Confirmation overlay verschijnt
6. TTS: "Destructief command gedetecteerd: rm -rf node_modules. Zeg confirm of cancel."
7a. User zegt "confirm" → command wordt uitgevoerd
7b. User zegt "cancel" → command geannuleerd
7c. 10 seconden timeout → auto-cancel
```

---

## 9. Edge Cases & Error Flows

### STT Edge Cases

| # | Edge Case | Handling |
|---|-----------|----------|
| E1 | Hex niet geinstalleerd | Toon onboarding stap, bied built-in WhisperKit aan |
| E2 | Hex draait niet | Toon notificatie: "Start Hex om voice commands te gebruiken" |
| E3 | Microfoon geen toegang | macOS permission dialog, daarna instructie in Settings |
| E4 | Achtergrondgeluid / onverstaanbaar | Discard + TTS: "Niet verstaan. Probeer opnieuw." |
| E5 | Zeer lange dictatie (>60 sec) | Warning na 30s, auto-stop na 60s met bevestigingsvraag |
| E6 | Verkeerde taal gedetecteerd | Toon transcriptie in overlay zodat user kan cancellen |
| E7 | Homofonen / ambigue commands | Toon transcriptie, wacht 1.5s voor correctie, dan execute |
| E8 | Whisper model niet gedownload | Automatisch downloaden bij eerste gebruik, progress indicator |

### Command Routing Edge Cases

| # | Edge Case | Handling |
|---|-----------|----------|
| E9 | Geen terminal window open | Open nieuw Terminal.app window automatisch |
| E10 | Target app niet geinstalleerd | Foutmelding + suggestie om app te installeren |
| E11 | Ambigue target (meerdere terminals open) | Gebruik de meest recent gefocuste terminal |
| E12 | Command niet herkenbaar als shell/IDE | Vraag bevestiging: "Wil je dit als terminal command uitvoeren?" |
| E13 | Zeer lang command (>500 chars) | Toon preview, vraag bevestiging |
| E14 | Command bevat wachtwoord/secret | NOOIT loggen, mask in history |
| E15 | Path met spaties in command | Automatisch quoten |

### Execution Edge Cases

| # | Edge Case | Handling |
|---|-----------|----------|
| E16 | Command timeout (>30s default) | TTS: "Command duurt langer dan verwacht. Wachten of annuleren?" |
| E17 | Command vereist interactie (y/n prompt) | Detecteer prompt, vraag user via voice |
| E18 | Command produceert enorme output (>10MB) | Truncate output, samenvatting op eerste 10K chars |
| E19 | Command faalt met exit code ≠ 0 | Error escalation: verhoog verbosity, toon error |
| E20 | Sudo vereist wachtwoord | TTS: "Dit command vereist sudo. Voer wachtwoord handmatig in." |
| E21 | Process crashed / SIGTERM | Rapporteer crash, log voor debugging |
| E22 | Netwerk vereist maar offline | Detecteer, meld: "Geen internetverbinding" |

### TTS Edge Cases

| # | Edge Case | Handling |
|---|-----------|----------|
| E23 | Kokoro model niet gedownload | Download bij eerste gebruik, fallback naar macOS Say |
| E24 | TTS engine crashed | Fallback naar macOS Say, log error |
| E25 | Audio output device disconnected | Detecteer, switch naar default, meld aan user |
| E26 | User spreekt terwijl TTS afspeelt | Stop TTS onmiddellijk (interrupt), start nieuwe listening |
| E27 | Response bevat code/special characters | Strip code blocks, lees alleen tekst |
| E28 | Response in onverwachte taal | Lees in detected taal, of skip met "Response beschikbaar in history" |
| E29 | ElevenLabs API rate limit | Fallback naar lokale TTS, meld rate limit |
| E30 | ElevenLabs API key ongeldig | Duidelijke foutmelding in Settings, fallback |

### System Edge Cases

| # | Edge Case | Handling |
|---|-----------|----------|
| E31 | macOS update breekt Accessibility permissions | Detecteer, toon re-authorize instructie |
| E32 | Hex update breekt compatibiliteit | Version check bij startup, waarschuwing als incompatibel |
| E33 | Onvoldoende geheugen voor Whisper model | Detecteer beschikbaar RAM, suggereer kleiner model |
| E34 | App conflict met andere voice tools | Detecteer (bijv. Siri), waarschuw over conflict |
| E35 | Multiple VOX instances | Prevent via `NSRunningApplication` check |

---

## 10. Niet-functionele Eisen

| Eis | Target | Meetmethode |
|-----|--------|-------------|
| STT latency (Hex → VOX) | <200ms | Timestamp delta |
| Command execution start | <100ms na herkenning | Timestamp delta |
| TTS start (na output) | <500ms (lokaal), <1s (cloud) | Timestamp delta |
| RAM gebruik (idle) | <80MB | Activity Monitor |
| RAM gebruik (listening) | <200MB (excl. Whisper model) | Activity Monitor |
| CPU idle | <1% | Activity Monitor |
| App launch time | <2s | Cold start measurement |
| Binary size | <30MB (excl. models) | du -sh |
| Crash rate | <0.1% per sessie | Crash logs |

---

## 11. Security & Privacy

1. **Geen cloud vereist**: Alle core functionaliteit werkt 100% offline (Hex + Kokoro/Piper)
2. **Geen telemetrie**: Geen analytics, geen tracking, geen data naar servers
3. **Geen audio opslag**: Spraak wordt niet opgeslagen, alleen transcripties (optioneel)
4. **Wachtwoord detectie**: Commands die wachtwoorden/secrets bevatten worden gemaskeerd in logs
5. **Destructive command protection**: Configureerbare safeguards
6. **Sandbox**: App draait in macOS sandbox waar mogelijk
7. **Open source audit**: Volledige broncode publiek, reviewbaar
8. **API keys encrypted**: ElevenLabs/Ollama keys opgeslagen in macOS Keychain

---

## 12. Release Roadmap

### v0.1.0 — "First Words" (MVP)
- Menu bar app met push-to-talk
- Hex clipboard bridge voor STT
- Terminal command execution
- macOS `say` TTS (built-in fallback)
- Verbosity levels (Silent, Ping, Summary via heuristic)
- Basic command history
- Onboarding flow
- Destructive command safeguard

### v0.2.0 — "Find Your Voice"
- Kokoro TTS integratie
- Piper TTS integratie
- ElevenLabs TTS integratie
- Improved summarization (Ollama optie)
- VS Code / Cursor / Windsurf integratie
- XPC bridge voor Hex (als Hex dit ondersteunt)
- Voice-activated wake word ("Hey Vox")

### v0.3.0 — "Full Control"
- Antigravity integratie (indien API beschikbaar)
- Git-specifieke voice commands ("commit met bericht ...")
- Docker voice commands
- SSH session support
- Plugin systeem voor custom app connectors
- Community voice command library

### v1.0.0 — "Production Ready"
- Alle MoSCoW Must + Should items compleet
- Volledige test coverage
- Performance geoptimaliseerd
- Documentatie compleet
- Homebrew installatie (`brew install vox`)

---

## 13. Audit Checklist — PRD Completeness

Gebruik deze checklist om te verifiëren dat de PRD alle benodigde elementen bevat:

### Product Definitie
- [x] Product naam en one-liner
- [x] Doelgroep gedefinieerd
- [x] Core value proposition
- [x] Kernprincipes/design principles

### Technische Specificatie
- [x] Programmeertaal keuze met onderbouwing
- [x] Architectuurdiagram
- [x] Core modules beschreven
- [x] STT integratie (Hex bridge) gespecificeerd
- [x] TTS engines gespecificeerd met tiers
- [x] Response verbosity system volledig beschreven

### MoSCoW Prioritering
- [x] Must Have apps gedefinieerd
- [x] Should Have apps gedefinieerd
- [x] Could Have apps gedefinieerd
- [x] Won't Have scope grenzen

### UI/UX Specificatie
- [x] Brand design tokens (tools.theuws.com aligned)
- [x] Scherm 1: Menu Bar dropdown
- [x] Scherm 2: Push-to-Talk overlay
- [x] Scherm 3: Settings — General
- [x] Scherm 4: Settings — Voice Input
- [x] Scherm 5: Settings — Apps
- [x] Scherm 6: Settings — TTS
- [x] Scherm 7: Settings — Advanced
- [x] Scherm 8: Command History
- [x] Scherm 9: Destructive Command Confirmation
- [x] Scherm 10: Onboarding / First Run

### Command Flows
- [x] Happy path: Voice → Terminal → Response
- [x] Happy path: Voice → Claude Code → Summary
- [x] Destructive command flow
- [x] Hex bridge communication flow

### Edge Cases & Error Handling
- [x] STT edge cases (E1-E8)
- [x] Command routing edge cases (E9-E15)
- [x] Execution edge cases (E16-E22)
- [x] TTS edge cases (E23-E30)
- [x] System edge cases (E31-E35)

### Niet-functionele Eisen
- [x] Performance targets (latency, RAM, CPU)
- [x] Security & privacy requirements
- [x] Reliability targets (crash rate)

### Planning
- [x] Release roadmap met versies
- [x] Feature toewijzing per versie

### Open Source
- [x] License model (MIT)
- [x] Privacy-first approach
- [x] No telemetry policy

---

## 14. Open Vragen / Beslissingen voor Development

1. **Hex PR**: Moeten we een PR indienen bij Hex voor XPC/IPC support, of bouwen we eerst op clipboard bridge?
2. **Kokoro integratie**: Python subprocess of native ONNX Swift binding?
3. **Samenvatting engine**: Starten met heuristic-only of direct Ollama integratie?
4. **App distributie**: Mac App Store, Homebrew, of direct DMG download?
5. **CI/CD**: GitHub Actions met Swift build + notarization?

---

*PRD Versie 0.1.0 — Draft voor review*
*Brand: tools.theuws.com style guide applied*
*Datum: 2026-02-10*
