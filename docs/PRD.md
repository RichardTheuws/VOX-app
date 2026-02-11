# PRD: VOX — Hex Companion for Terminal Audio Feedback

**Product**: VOX (Voice-Operated eXecution)
**Versie**: 2.0.0 (PRD)
**Datum**: 2026-02-11
**Auteur**: Theuws Development
**Brand**: tools.theuws.com
**Status**: ACTIVE — reflects v0.6.x implementation
**GitHub**: https://github.com/RichardTheuws/VOX-app

---

## Context

Developers die met AI-tools als Claude Code werken in de terminal, missen audio feedback. Je dicteert een commando via Hex, maar moet vervolgens naar je scherm kijken om de output te lezen. **VOX** vult dit gat: het detecteert wanneer Hex een dictaat naar Terminal stuurt, leest de terminal output, en spreekt een samenvatting terug via TTS.

VOX is een **passieve companion** — het voert zelf geen commands uit, heeft geen microfoontoegang nodig, en vraagt geen accessibility permissions. Hex doet de spraakherkenning, VOX doet het terugpraten.

**Doelgroep**: macOS developers die Hex gebruiken voor spraakdictaat in Terminal.app of iTerm2.

---

## 1. Product Vision

### One-liner
> "Talk to your terminal. Hear what matters."

### Core Value Proposition
VOX is een open-source macOS menu bar companion voor Hex die terminal output samenvat en terugspreekt via configureerbare TTS. Geen extra permissions, geen command execution — puur audio feedback.

### Kernprincipes
1. **Zero-permission**: Geen microphone, geen accessibility — Hex doet de input
2. **Privacy-first**: Alle verwerking lokaal, geen cloud vereist, geen telemetrie
3. **Configureerbaar**: 4 verbosity levels — jij bepaalt hoeveel je hoort
4. **Non-invasive**: Menu bar app met ear icon, geen vensters in de weg
5. **Open source**: MIT-licensed, community-driven

### Hoe VOX werkt

```
Hex (STT) → Dictaat in Terminal → VOX detecteert → Leest output → Spreekt samenvatting
```

Gedetailleerd:
```
1. User activeert Hex (eigen hotkey)
2. User spreekt: "git status"
3. Hex transcribeert on-device → typt tekst in Terminal.app
4. Hex slaat transcriptie op in transcription_history.json
5. VOX detecteert nieuwe entry via file monitoring (0.3s poll)
6. VOX leest Terminal content via AppleScript (snapshot)
7. VOX wacht tot terminal output stabiliseert (1.5s geen verandering)
8. VOX extraheert nieuwe output (diff van snapshot)
9. ResponseProcessor maakt samenvatting op basis van verbosity level
10. TTS Engine spreekt samenvatting uit
11. Entry opgeslagen in CommandHistory
```

---

## 2. Technische Architectuur

### Programmeertaal: Swift 6 + SwiftUI (macOS-only)

**Waarom Swift in februari 2026:**

| Criterium | Swift/SwiftUI | Tauri/Rust | Electron |
|-----------|--------------|------------|----------|
| macOS systeemintegratie | Native (menu bar, AppleScript) | Beperkt via FFI | Beperkt |
| Hex interop | Native Swift — zelfde ecosysteem | Vereist bridging | Vereist bridging |
| Binary size | ~1.3MB | ~8MB | ~150MB+ |
| RAM usage | ~30-50MB | ~40-60MB | ~200MB+ |
| Apple Silicon optimalisatie | Native | Goed via LLVM | Matig |

### Architectuurdiagram

```
┌──────────────────────────────────────────────────┐
│                VOX (Menu Bar App)                 │
│                                                   │
│  ┌──────────┐     ┌────────────────┐             │
│  │ HexBridge│────▶│ AppState       │             │
│  │ (file    │     │ (coordinator)  │             │
│  │  monitor)│     └───┬────────┬───┘             │
│  └──────────┘         │        │                 │
│                       ▼        ▼                 │
│  ┌──────────────┐  ┌──────────────────┐          │
│  │ Terminal     │  │ Response         │          │
│  │ Reader      │  │ Processor        │          │
│  │ (AppleScript)│  │ (heuristic      │          │
│  └──────┬───────┘  │  summarization) │          │
│         │          └────────┬─────────┘          │
│         │                   │                    │
│         │          ┌────────▼─────────┐          │
│         └─────────▶│ TTS Engine       │          │
│                    │ (macOS Say /     │          │
│                    │  Kokoro / 11Labs)│          │
│                    └──────────────────┘          │
│                                                   │
│  ┌──────────────┐  ┌──────────────────┐          │
│  │ Command      │  │ VoxSettings      │          │
│  │ History      │  │ (AppStorage)     │          │
│  └──────────────┘  └──────────────────┘          │
└──────────────────────────────────────────────────┘
```

### Services (5)

| Service | Verantwoordelijkheid | Implementatie |
|---------|---------------------|---------------|
| **HexBridge** | Monitort `transcription_history.json` voor nieuwe Hex dictaten | File polling (0.3s), timestamp seeding, `sourceAppBundleID` filtering |
| **TerminalReader** | Leest Terminal.app / iTerm2 content | AppleScript via `osascript`, output stabilization detection |
| **ResponseProcessor** | Samenvat terminal output op basis van verbosity | Heuristic: git status parser, error detection, Claude output parser |
| **TTSEngine** | Spreekt tekst uit | `NSSpeechSynthesizer` (macOS Say), Kokoro en ElevenLabs gepland |
| **CommandHistory** | Slaat transcripties + responses op | In-memory array met `VoxCommand` entries |

### Models (5)

| Model | Beschrijving |
|-------|-------------|
| **AppMode** | `.idle`, `.monitoring` — 2 states |
| **VerbosityLevel** | `.silent`, `.ping`, `.summary`, `.full` — 4 levels |
| **TargetApp** | Terminal, iTerm2, Claude Code, VS Code, Cursor, Windsurf |
| **VoxCommand** | Transcription + resolved command + target + status + output + summary |
| **VoxSettings** | Alle AppStorage settings (general, TTS, verbosity, apps, advanced) |

### Views (4)

| View | Beschrijving |
|------|-------------|
| **MenuBarView** | Menu bar dropdown met status, last command, verbosity, settings/history links |
| **OnboardingView** | 3-staps wizard: Hex install → TTS keuze → Voice test |
| **SettingsView** | 4 tabs: General, Apps, TTS, Advanced |
| **HistoryView** | Chronologische lijst van transcripties + responses |

---

## 3. Hex Bridge — Integratie Specificatie

### Hoe Hex werkt
Hex is een macOS menu bar app (Swift/SwiftUI) die on-device STT doet via:
- **WhisperKit** (Core ML Whisper model)
- **Parakeet TDT v3** (Core ML via FluidAudio)

Hex slaat elke transcriptie op in:
```
~/Library/Containers/com.kitlangton.Hex/Data/Library/Application Support/
  com.kitlangton.Hex/transcription_history.json
```

### JSON structuur
```json
{
  "history": [
    {
      "id": "uuid",
      "text": "git status",
      "timestamp": 1707654321.123,
      "sourceAppName": "Terminal",
      "sourceAppBundleID": "com.apple.Terminal",
      "duration": 1.2
    }
  ]
}
```

### VOX File Monitor implementatie
- **Methode**: `Timer` polling elke 0.3 seconden
- **Optimalisatie**: Check `modificationDate` eerst — skip parsing als file ongewijzigd
- **Timestamp seeding**: Bij `startMonitoring()` wordt de timestamp van het nieuwste entry opgeslagen, zodat alleen NEW entries worden verwerkt
- **Filtering**: Alleen entries met `sourceAppBundleID` in `monitorableBundleIDs` (Terminal.app, iTerm2) worden verwerkt
- **Andere apps**: Dictaten naar Cursor, WhatsApp, Notes etc. worden genegeerd

### Gemonitorde apps

| App | Bundle ID | Status |
|-----|-----------|--------|
| Terminal.app | `com.apple.Terminal` | ✅ Actief |
| iTerm2 | `com.googlecode.iterm2` | ✅ Actief |
| Alle andere apps | — | ❌ Genegeerd |

---

## 4. Terminal Monitoring — Output Capture

### Methode: AppleScript via `osascript`

**Terminal.app:**
```applescript
tell application "Terminal" to if (count of windows) > 0 then
  get contents of selected tab of front window
```

**iTerm2:**
```applescript
tell application "iTerm2" to tell current session of current tab of current window
  to get contents
```

### Output Stabilization Algorithm

```
1. Neem snapshot van terminal content (direct na Hex transcriptie)
2. Wacht 500ms (laat command starten)
3. Poll elke 300ms voor nieuwe content
4. Als content verandert: reset stabilization timer
5. Als content NIET verandert voor 1.5s: output is gestabiliseerd
6. Extract nieuwe content (diff van snapshot)
7. Timeout na 30s (configureerbaar via settings.commandTimeout)
```

### Diff-extractie
- Line-by-line vergelijking van before/after snapshots
- Vindt common prefix → nieuwe content = lines na divergentie
- Fallback: character-level diff als terminal content op bestaande regels verandert (streaming output)

---

## 5. Response Verbosity System

### Het kernprobleem
Terminal output (vooral van AI-tools als Claude Code) kan honderden regels zijn. Als developer wil je niet alles horen voorgelezen. VOX biedt 4 verbosity levels:

### Verbosity Levels

| Level | Naam | Wat je hoort | Voorbeeld |
|-------|------|-------------|-----------|
| 0 | **Silent** | Niets (alleen visuele indicator) | *(stilte, ear icon in menu bar)* |
| 1 | **Ping** | Alleen status bevestiging | *"Done."* / *"Error occurred."* |
| 2 | **Summary** (default) | Heuristic samenvatting (1-2 zinnen) | *"On main, 3 modified."* |
| 3 | **Full** | Volledige response voorgelezen | *(volledige terminal output, code blocks gestript)* |

### Configuratie
- **Globaal default level**: Settings → TTS tab (standaard: Level 2 - Summary)
- **Per-app override**: Settings → Apps tab — per target app een verbosity instellen
- **Error escalation**: Bij errors automatisch naar hoger level (configureerbaar)

### Heuristic Summarization Engine (huidige implementatie)

De `ResponseProcessor` gebruikt pattern-matching voor slimme samenvattingen:

| Command type | Samenvatting logica |
|-------------|-------------------|
| `git status` | Parsed branch naam, telt modified/staged/untracked files |
| `git log` | Telt commits |
| `npm`/`build` | Detecteert error/success, extraheert eerste error line |
| `ls` | Telt items |
| `claude` | Zoekt file changes, test results, "Done" status |
| Overige | Eerste regel + "(N lines total)" |
| Errors | Exit code + eerste error/fatal/failed regel |

### Speech Cleaning
Voor verbosity level Full wordt output opgeschoond:
- Code blocks (```) → "(code block omitted)"
- ANSI escape codes → verwijderd
- URLs → "link to [domain]"

### Toekomstige samenvatting opties (gepland)
Settings bevat al `SummarizationMethod` enum:
- **Heuristic** (huidige default) — geen LLM, instant
- **Ollama** (gepland) — lokaal LLM voor betere samenvattingen
- **Claude API** (gepland) — cloud, beste kwaliteit
- **OpenAI API** (gepland) — cloud alternatief

---

## 6. TTS Engine Specificatie

### Huidige implementatie: macOS Say

| Eigenschap | Waarde |
|-----------|--------|
| Backend | `NSSpeechSynthesizer` |
| Kwaliteit | Basis, herkenbaar als synthetisch |
| Latency | Instant |
| RAM | 0 (OS-level) |
| Kosten | Gratis |
| Status | ✅ Geïmplementeerd |

### Gepland: Kokoro TTS
- **Model**: Kokoro-82M (Apache 2.0 license)
- **Kwaliteit**: Vergelijkbaar met ElevenLabs in blind tests
- **Latency**: 40-70ms op GPU, 3-11x realtime op CPU
- **RAM**: ~200MB voor model
- **Voices**: 48+ stemmen, 8 talen
- **Integratie**: Python wrapper via Swift `Process` of native ONNX runtime
- **Apple Silicon**: Ondersteund via MPS (Metal Performance Shaders)
- **Status**: ❌ Nog niet geïmplementeerd — UI toont "coming soon"

### Gepland: ElevenLabs
- **Kwaliteit**: Premium, zeer natuurlijk
- **Latency**: 200-500ms (netwerk)
- **Kosten**: ~$5/maand
- **Integratie**: REST API
- **Status**: ❌ Nog niet geïmplementeerd — UI toont "coming soon"

### Gepland: Piper TTS
- **Model**: ONNX-based VITS models
- **Kwaliteit**: Goed, iets minder natuurlijk dan Kokoro
- **Latency**: Zeer laag (<100ms)
- **Status**: ❌ Nog niet geïmplementeerd — UI toont "coming soon"

### TTS Settings (geïmplementeerd)
- Engine selectie (macOS Say actief, rest disabled)
- Speed (0.5x - 2.0x)
- Volume (0-100%)
- Interrupt on new command (toggle)

---

## 7. User Interface

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
```

---

### Scherm 1: Menu Bar Icon + Dropdown

**Locatie**: macOS menu bar (rechts)
**Icon**: Ear (👂) — VOX is een listener, niet een speaker

```
┌──────────────────────────────────────┐
│  [👂 icon]  ← Klik = dropdown        │
│                                      │
│  ┌────────────────────────────────┐  │
│  │ 👂 VOX                 v0.6.x │  │
│  │ ─────────────────────────────  │  │
│  │ Status: Idle / Monitoring...   │  │
│  │ Verbosity: ●●○○ Summary       │  │
│  │ ─────────────────────────────  │  │
│  │ 🔵 Last: "git status"         │  │
│  │    → On main, 3 modified.     │  │
│  │ ─────────────────────────────  │  │
│  │ ⚙ Settings...                 │  │
│  │ 📋 History                    │  │
│  │ ⏻ Quit VOX                    │  │
│  └────────────────────────────────┘  │
└──────────────────────────────────────┘
```

**Gedrag**:
- Icon: `ear` (idle), `eye` (monitoring)
- Dropdown toont status, verbosity slider, laatste command + response
- Links naar Settings en History windows

---

### Scherm 2: Settings (4 tabs)

**Tab 1: General**
```
┌─────────────────────────────────────────────────┐
│ VOX Settings                              [×]   │
│ [General] [Apps] [TTS] [Advanced]               │
│ ─────────────────────────────────────────────── │
│                                                  │
│ GENERAL                                          │
│ Launch at login          [Toggle: OFF]           │
│ Theme                    ○ Dark  ○ Light  ● System│
│                                                  │
│ LANGUAGE                                         │
│ Input language           [Dropdown: Auto-detect] │
│ Response language        [Dropdown: Follow input]│
│                                                  │
└─────────────────────────────────────────────────┘
```

**Tab 2: Apps**
```
┌─────────────────────────────────────────────────┐
│ [General] [Apps] [TTS] [Advanced]               │
│ ─────────────────────────────────────────────── │
│                                                  │
│ MONITORED APPS                                   │
│ Auto-detect active app   [Toggle: ON]            │
│                                                  │
│ ┌─────────────────────────────────────────────┐ │
│ │ ● Terminal.app          Verbosity: Summary  │ │
│ ├─────────────────────────────────────────────┤ │
│ │ ● iTerm2                Verbosity: Summary  │ │
│ ├─────────────────────────────────────────────┤ │
│ │ ● Claude Code (CLI)     Verbosity: Summary  │ │
│ └─────────────────────────────────────────────┘ │
│                                                  │
│ Default target           [Dropdown: Terminal]    │
│                                                  │
└─────────────────────────────────────────────────┘
```

**Tab 3: TTS**
```
┌─────────────────────────────────────────────────┐
│ [General] [Apps] [TTS] [Advanced]               │
│ ─────────────────────────────────────────────── │
│                                                  │
│ TEXT-TO-SPEECH ENGINE                             │
│ Engine        ● macOS Say (built-in)             │
│               ○ Kokoro (coming soon)             │
│               ○ ElevenLabs (coming soon)         │
│               ○ Disabled                         │
│                                                  │
│ Speed         [Slider: 1.0x ────●── 2.0x]       │
│ Volume        [Slider: ████████░░ 80%]           │
│ [▶ Test Voice]                                   │
│                                                  │
│ DEFAULT VERBOSITY                                │
│ ○ Silent  ○ Ping  ● Summary  ○ Full             │
│                                                  │
│ Error escalation         [Toggle: ON]            │
│ Error verbosity          [Dropdown: Summary]     │
│ Interrupt on new command [Toggle: ON]            │
│                                                  │
└─────────────────────────────────────────────────┘
```

**Tab 4: Advanced**
```
┌─────────────────────────────────────────────────┐
│ [General] [Apps] [TTS] [Advanced]               │
│ ─────────────────────────────────────────────── │
│                                                  │
│ SUMMARY ENGINE                                   │
│ Method        ● Heuristic (geen LLM)             │
│               ○ Ollama (coming soon)             │
│               ○ Claude API (coming soon)         │
│               ○ OpenAI API (coming soon)         │
│                                                  │
│ Max summary length       [Slider: 2 sentences]   │
│                                                  │
│ TERMINAL MONITORING                              │
│ Monitor timeout          [Slider: 30s]           │
│ Max output capture       [Slider: 10000 chars]   │
│                                                  │
│ LOGGING                                          │
│ Log to file              [Toggle: OFF]           │
│                                                  │
│ DATA                                             │
│ [Export settings]  [Import settings]             │
│ [Reset to defaults]                              │
│                                                  │
└─────────────────────────────────────────────────┘
```

---

### Scherm 3: Onboarding (3 stappen)

```
┌─────────────────────────────────────────────────┐
│           VOX                                    │
│   "Talk to your terminal. Hear what matters."    │
│             ● ○ ○                                │
│ ─────────────────────────────────────────────── │
│                                                  │
│     Step 1/3: Install Hex                        │
│                                                  │
│     VOX uses Hex for on-device speech            │
│     recognition. Hex dictates into Terminal,     │
│     VOX reads the response back.                 │
│     No data leaves your Mac.                     │
│                                                  │
│     [Download Hex]  [Check Status]               │
│     ✅ Hex detected and running!                 │
│                                                  │
│                              [Next →]            │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│             ● ● ○                                │
│                                                  │
│     Step 2/3: Choose TTS Engine                  │
│                                                  │
│     ● macOS Say (built-in, instant, no setup)    │
│     ○ Kokoro (coming soon — local, free)         │
│     ○ ElevenLabs (coming soon — cloud, premium)  │
│                                                  │
│     [▶ Test Voice]                               │
│     ✅ TTS working!                              │
│                                                  │
│     [← Back]                     [Next →]        │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│             ● ● ●                                │
│                                                  │
│     Step 3/3: Test Your Setup                    │
│                                                  │
│     🟢 Hex is running                            │
│                                                  │
│     ⏳ Listening for Hex transcription...        │
│     Try it now — dictate something with Hex!     │
│                                                  │
│     (auto-starts monitoring when step appears)   │
│                                                  │
│     VOX heard: "hello world"                     │
│     ✅ VOX is ready!                             │
│                                                  │
│     [← Back]              [Start Using VOX]      │
└─────────────────────────────────────────────────┘
```

**Geen permissions nodig**: Geen microphone dialog, geen accessibility dialog.

---

### Scherm 4: Command History

```
┌─────────────────────────────────────────────────┐
│ VOX History                               [×]   │
│ ─────────────────────────────────────────────── │
│                                                  │
│ ┌─────────────────────────────────────────────┐ │
│ │ 14:32  🟢 "git status"                     │ │
│ │        → Terminal.app (monitoring)          │ │
│ │        Summary: On main, 3 modified.        │ │
│ ├─────────────────────────────────────────────┤ │
│ │ 14:30  🟢 "claude fix the login bug"       │ │
│ │        → Terminal.app (monitoring)          │ │
│ │        Summary: Done. 2 files changed,      │ │
│ │        tests passing.                       │ │
│ ├─────────────────────────────────────────────┤ │
│ │ 14:28  🟢 "npm run build"                  │ │
│ │        → Terminal.app (monitoring)          │ │
│ │        Summary: Build completed             │ │
│ │        successfully.                        │ │
│ └─────────────────────────────────────────────┘ │
│                                                  │
│ [Clear All]                    Showing 3 entries │
└─────────────────────────────────────────────────┘
```

---

## 8. Edge Cases & Error Handling

### Hex Bridge Edge Cases

| # | Edge Case | Handling |
|---|-----------|----------|
| E1 | Hex niet geïnstalleerd | Onboarding Step 1 toont download link. VOX werkt niet zonder Hex. |
| E2 | Hex draait niet | Menu bar toont oranje indicator. "Launch Hex" knop in onboarding/settings. |
| E3 | Hex history file niet gevonden | Silently retry. File verschijnt zodra Hex eerste dictaat doet. |
| E4 | Hex history file corrupt/onleesbaar | `readHistoryEntries()` returned `nil`, retry bij volgende poll. |
| E5 | Hex update wijzigt JSON structuur | `Decodable` parsing faalt gracefully. Toekomstige versie: version check. |
| E6 | Hex dictaat naar niet-gemonitorde app | Entry gefilterd op `sourceAppBundleID`. Wordt genegeerd. |
| E7 | Meerdere snelle dictaten achtereen | Elk entry wordt sequentieel verwerkt. Nieuwe entry tijdens `.monitoring` wordt genegeerd (guard check). |

### Terminal Monitoring Edge Cases

| # | Edge Case | Handling |
|---|-----------|----------|
| E8 | Geen terminal window open | `readTerminalContent()` returned `nil`. TTS: "No terminal window found." |
| E9 | Terminal output verandert niet (geen commando) | Output stabilization na 1.5s, diff is leeg → "No new output." |
| E10 | Zeer lange output (>10K chars) | Truncated op `maxOutputCapture` setting. |
| E11 | Monitor timeout (>30s) | Returned whatever output beschikbaar is. Setting configureerbaar. |
| E12 | Terminal wisselt van tab tijdens monitoring | Snapshot was van oorspronkelijke tab. Mogelijke mismatch. Acceptabel voor MVP. |
| E13 | Streaming output (bijv. Claude Code) | Stabilization delay (1.5s) vangt dit op — wacht tot output stopt. |
| E14 | ANSI escape codes in output | `cleanForSpeech()` stripped ANSI codes voor TTS. |

### TTS Edge Cases

| # | Edge Case | Handling |
|---|-----------|----------|
| E15 | TTS engine disabled | Verbosity forced to Silent. Alleen visuele feedback. |
| E16 | NSSpeechSynthesizer deprecated warning | Acceptabel voor MVP. Migratie naar AVSpeechSynthesizer gepland. |
| E17 | Nieuw Hex dictaat terwijl TTS spreekt | `interruptOnNewCommand` setting. Default: stop TTS, start nieuwe monitoring. |
| E18 | Response bevat code blocks | `cleanForSpeech()` vervangt code blocks met "(code block omitted)". |
| E19 | Response bevat URLs | `cleanForSpeech()` vervangt URLs met "link to [domain]". |

### System Edge Cases

| # | Edge Case | Handling |
|---|-----------|----------|
| E20 | Multiple VOX instances | Prevent via single-instance check. |
| E21 | macOS update breekt AppleScript | Terminal reading faalt silently. Toekomstige versie: error reporting. |
| E22 | Hex update breekt history format | JSON decode faalt gracefully, retry bij volgende poll. |
| E23 | App launch na sleep/wake | HexBridge re-seeds timestamp, voorkomt replay van oude entries. |

---

## 9. Niet-functionele Eisen

| Eis | Target | Huidige status |
|-----|--------|---------------|
| Hex → VOX detectie latency | <500ms | ✅ ~300ms (0.3s poll interval) |
| TTS start na output stabilisatie | <200ms | ✅ Instant (macOS Say) |
| RAM gebruik (idle) | <50MB | ✅ ~30MB |
| CPU idle | <1% | ✅ Timer-based polling is lightweight |
| App launch time | <2s | ✅ ~1s |
| Binary size | <5MB | ✅ 1.3MB |
| Crash rate | <0.1% per sessie | ✅ Geen crashes gerapporteerd |
| Test coverage | 32 tests | ✅ VerbosityLevel, TargetApp, VoxCommand |

---

## 10. Security & Privacy

1. **Geen permissions**: Geen microphone, geen accessibility, geen camera
2. **Geen cloud vereist**: Alle core functionaliteit werkt 100% offline
3. **Geen telemetrie**: Geen analytics, geen tracking, geen data naar servers
4. **Geen audio opslag**: VOX neemt niets op — Hex doet de STT
5. **Lokale verwerking**: Terminal content wordt alleen in-memory verwerkt
6. **Geen credentials**: VOX slaat geen wachtwoorden of API keys op (toekomstig: Keychain voor ElevenLabs)
7. **Open source**: Volledige broncode publiek op GitHub, MIT-licensed
8. **Minimale footprint**: Alleen file reading (Hex history) en AppleScript (terminal content)

---

## 11. Release History & Roadmap

### Gerealiseerd

#### v0.1.0 → v0.5.0 — "Voice-Operated Assistant" (gearchiveerd)
Oorspronkelijke architectuur met push-to-talk, command execution, safety checks, accessibility permissions. **Volledig verwijderd in v0.6.0.**

#### v0.6.0 — "Hex Companion" (2026-02-11)
- Gestript tot pure Hex companion: ~1,500 regels verwijderd
- Verwijderd: HotkeyManager, CommandRouter, TerminalExecutor, SafetyChecker, PushToTalkOverlay, DestructiveConfirmView
- Vereenvoudigd: 2 app modes (was 5), 3 onboarding stappen (was 6), 4 settings tabs (was 5)
- Geen permissions meer nodig

#### v0.6.1 — "Auto-start Voice Test" (2026-02-11)
- Onboarding Step 3 start monitoring automatisch (geen "Start Test" knop meer)
- Monitoring stopt bij navigatie terug naar Step 2
- Hex launch → auto-retry monitoring

### Gepland

#### v0.7.0 — "Better Voices" (gepland)
- Kokoro TTS integratie (lokaal, 82M params, near-ElevenLabs kwaliteit)
- Voice selectie en preview
- Mogelijk: Piper TTS als lightweight alternatief

#### v0.8.0 — "Smarter Summaries" (gepland)
- Ollama integratie voor LLM-based samenvattingen
- Betere Claude Code output parsing
- Configureerbare samenvatting prompts

#### v0.9.0 — "Polish" (gepland)
- ElevenLabs TTS integratie (cloud premium)
- AVSpeechSynthesizer migratie (NSSpeechSynthesizer deprecation)
- Export/import settings
- Betere error handling en user feedback

#### v1.0.0 — "Production Ready" (gepland)
- Homebrew installatie (`brew install --cask vox`)
- DMG distribution met notarization
- CI/CD via GitHub Actions
- Volledige documentatie
- Community feedback verwerkt

---

## 12. Scope Grenzen (Won't Have)

| Feature | Reden |
|---------|-------|
| Command execution | VOX voert geen commands uit — Hex typt, terminal voert uit |
| Push-to-talk / hotkeys | Hex heeft eigen hotkey — VOX hoeft niet te luisteren |
| Microphone access | Hex doet alle STT |
| Accessibility permissions | VOX leest terminal via AppleScript, niet via accessibility API |
| IDE integratie (VS Code, Cursor) | VOX monitort alleen Terminal.app / iTerm2 |
| Browser-based tools | Out of scope |
| Windows/Linux | macOS-only |
| Wake word ("Hey VOX") | Hex heeft eigen activatie |
| Destructive command safeguards | VOX voert geen commands uit |

---

## 13. Open Vragen

1. **Kokoro integratie**: Python subprocess of native ONNX Swift binding? Python is sneller te implementeren, ONNX is natiever.
2. **Ollama samenvatting**: Welk model? llama3.2:3b is klein en snel, maar kwaliteit moet getest worden.
3. **App distributie**: Homebrew Cask, DMG download, of beide?
4. **CI/CD**: GitHub Actions met Swift build + notarization?
5. **Terminal reading**: Kan AppleScript vervangen worden door een robuustere methode? (bijv. terminal multiplexer integratie)

---

## 14. Audit Checklist — PRD Completeness

### Product Definitie
- [x] Product naam en one-liner
- [x] Doelgroep gedefinieerd
- [x] Core value proposition
- [x] Kernprincipes/design principles
- [x] "Hoe het werkt" flow

### Technische Specificatie
- [x] Programmeertaal keuze met onderbouwing
- [x] Architectuurdiagram (actueel)
- [x] Services beschreven (5)
- [x] Models beschreven (5)
- [x] Views beschreven (4)

### Hex Bridge
- [x] JSON structuur gedocumenteerd
- [x] File monitoring methode beschreven
- [x] Timestamp seeding uitgelegd
- [x] Source app filtering beschreven

### Terminal Monitoring
- [x] AppleScript methode beschreven
- [x] Output stabilization algorithm
- [x] Diff-extractie uitgelegd

### Verbosity System
- [x] 4 levels beschreven
- [x] Heuristic summarization per command type
- [x] Speech cleaning regels
- [x] Toekomstige LLM opties gedocumenteerd

### TTS Engine
- [x] Huidige implementatie (macOS Say)
- [x] Geplande engines (Kokoro, ElevenLabs, Piper)

### UI Specificatie
- [x] Brand design tokens
- [x] Menu bar dropdown
- [x] Settings (4 tabs)
- [x] Onboarding (3 stappen)
- [x] Command History

### Edge Cases
- [x] Hex bridge edge cases (E1-E7)
- [x] Terminal monitoring edge cases (E8-E14)
- [x] TTS edge cases (E15-E19)
- [x] System edge cases (E20-E23)

### Niet-functionele Eisen
- [x] Performance targets met huidige status
- [x] Security & privacy
- [x] Test coverage

### Planning
- [x] Release history
- [x] Roadmap v0.7 → v1.0
- [x] Scope grenzen (Won't Have)
- [x] Open vragen

---

*PRD Versie 2.0.0 — Reflects v0.6.x Hex Companion architecture*
*Brand: tools.theuws.com style guide applied*
*Datum: 2026-02-11*
