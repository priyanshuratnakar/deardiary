# PRD: freewrite with a memory

Nov 10, 2026 · @Priyanshu Ratnakar

## Summary

A fork of Farza's freewrite that stays a blank page by default, and gains three things: a talk mode you switch on when you want to be heard, a local memory the AI builds from your entries, and a map that shows that memory as connected thoughts.

It is a personal tool first. One user, one Mac, your own Claude API key. Nothing is hosted and there are no accounts.

|  | v1 | Later |
| --- | --- | --- |
| Platform | macOS 14+, built on the freewrite codebase (MIT) | iOS |
| AI provider | Claude, behind a provider interface | OpenAI and other providers |
| Writing | Freewrite as it is today |  |
| Talk mode | Off by default, one toggle | Replies written on the page itself |
| Memory | Built by AI from text entries, stored as local files | Video transcripts feed memory too |
| Map | AI-built graph, manual fixes allowed | Time slider, filters |

**Not in v1:** sync, sharing, mood tracking, streaks, prompts of the day, templates. The pull toward those is what made Stoic feel heavy.

## Principles

Every feature gets checked against these, in this order.

1. **The page comes first.** With AI off, the app is freewrite and nothing else. No new buttons, panels or nudges appear while you write.
2. **AI is invited, never present by default.** It speaks only when you turn talk mode on or open the map.
3. **Local and readable.** Entries and memory are plain markdown and JSON in a folder you can open, edit, back up or delete.
4. **Memory must show its evidence.** Every thought and every link points back to the entries and the lines it came from. Nothing is asserted without a source in your own writing.
5. **You can overrule the AI.** Anything it gets wrong you can rename, merge, link or delete, and it must respect that afterwards.
6. **It hands you back to yourself.** Talk mode reflects and asks. It does not flatter, diagnose, or try to become the thing you need.

## The experience

### Write (default)

Unchanged from freewrite: the blank page, the 15-minute timer, fonts and size, backspace lock, fullscreen, light and dark, autosave, a new entry each day, and the history sidebar. Video entries keep working and are left alone.

Two words are added to the bottom bar: **talk** and **map**. They only appear once an API key is connected. Freewrite's current Chat button, which opens ChatGPT or Claude in the browser, is replaced by talk.

### Talk (toggle)

Off by default. Turning it on is how you say "I want to be heard now."

- A quiet conversation column opens beside the page. The page stays visible and editable.
- If there is writing on the page, it opens with one short response to what you wrote. If the page is empty, it waits for you.
- Replies stream in. They are short, in plain prose, in the voice of a thoughtful therapist: it reflects what it notices, asks one question at a time, and is honest.
- It knows today's entry, your memory profile, and the past thoughts and entries that relate to what you are saying. When it draws on the past it says which day, so you can check it.
- Each entry keeps its own conversation, saved next to the entry.
- Turning talk off closes the column. No AI call happens while it is off.

### Map

A full-window view of your memory as a graph, in the spirit of Obsidian's graph view.

- Nodes are thoughts: themes, feelings, people, ideas, questions, decisions, events. Size shows how often a thought recurs. Colour shows its kind.
- Lines are relationships with a reason, for example "shows up whenever", "in tension with", "led to".
- Click a node to read what the AI understands about it, how it has changed over time, and the exact lines from your entries behind it. Click a day to open that entry.
- Click a line to read why the two thoughts are connected and which entries show it.
- Manual fixes: rename, merge two nodes, delete, add or remove a link. The AI never undoes a manual fix.
- You can drag nodes. Positions are remembered.

### History and versions

Freewrite's sidebar already lists every entry by day. One addition: each entry keeps timed snapshots, so you can see what a day's entry looked like earlier and restore it.

### Settings

One small sheet: API key, model, AI on or off, "rebuild memory", "open memory folder", and "forget everything the AI has learned" (deletes memory, keeps entries).

## Memory

Memory is a folder of small markdown notes the AI writes about what you write. It is the single source for both talk mode and the map, and it is built to answer two questions: what keeps happening, and why.

### What it stores

| File | Holds |
| --- | --- |
| `memory/profile.md` | A short running picture of you: what is on your mind lately, patterns that hold over weeks, the people and projects that matter. Rewritten as things change. |
| `memory/thoughts/<id>.md` | One note per thought. Kind, other names it goes by, first and last seen, a short "what this is", a dated timeline of how it has shifted, evidence (entry + exact quoted line), and links to other thoughts with a reason and evidence. |
| `memory/entries/<entry-id>.json` | A digest of one entry: 2-3 sentence summary, thoughts it touched, open loops, and a hash of the text so unchanged entries are never reprocessed. |
| `memory/graph.json` | The compiled graph and node positions for the map. Rebuilt from the thought notes. |
| `memory/pins.json` | Your manual fixes: renames, merges, deletions, links. The AI reads this and must obey it. |

Thought notes link to each other with `[[wikilinks]]`, so the memory folder also opens as an Obsidian vault.

### How it gets built

1. **Trigger.** An entry is digested when it has settled: you start a new entry, the day changes, the app has been idle for 10 minutes, or you turn on talk or open the map. Never while you are typing.
2. **Digest.** Claude gets the entry, the profile, and a compact index of existing thoughts (id, label, other names, one line each). It returns structured operations: update an existing thought, create a new one, add a link with a reason and a quoted line, add a timeline note, list open loops.
3. **Apply.** The app validates the operations and writes the files. A quote that does not appear in the entry is rejected, so the AI cannot invent evidence. Pinned fixes win over anything the AI proposes.
4. **Consolidate.** About once a week, or on request, a second pass merges duplicates, retires thoughts that appeared once and never returned, refreshes the profile, and looks for patterns across weeks that single entries cannot show.

### How it gets used

Before each talk reply the app assembles context locally: the profile, today's entry, the thoughts whose names appear in the entry or your message plus their linked neighbours, and the quoted lines and summaries from the entries behind them. No vector database in v1; name and link matching over a personal journal is enough to start, and local embeddings can be added later without changing the files.

### What "smart enough" means here

The target is 100% AI-built with no manual work. Three things keep it from drifting: it must reuse an existing thought before creating a new one, every claim needs a quoted line, and the weekly pass cleans up. It will still get things wrong sometimes, which is why manual fixes exist and are permanent.

## Technical shape

The fork adds new files around freewrite's code and touches the existing files as little as possible, so upstream changes stay easy to pull in.

### What the fork starts with

Checked against the [freewrite repo](https://github.com/farzaa/freewrite) on 10 Nov 2026.

- SwiftUI, macOS 14.0 minimum, MIT licensed.
- Almost everything lives in one file, `ContentView.swift` (about 2,250 lines), plus two video files and the app file.
- Entries are markdown files in the app's `Documents/Freewrite/` folder, named `[uuid]-[yyyy-MM-dd-HH-mm-ss].md`.
- The app is sandboxed with no network permission. AI needs the outgoing-connections entitlement added.
- The repo ships `CLAUDE.md` and `AGENTS.md`, mirrored notes for coding agents. They must be kept in sync when the architecture changes.

### What gets added

| Piece | Job |
| --- | --- |
| `AI/LLMProvider.swift` | A small protocol: stream a reply, complete a structured request. |
| `AI/AnthropicProvider.swift` | Claude Messages API over URLSession, with streaming. No SDK dependency. |
| `AI/Keychain.swift` | API key in the macOS Keychain. Never in a file or UserDefaults. |
| `AI/Prompts.swift` | Talk voice, digest and consolidate prompts in one editable place. |
| `Memory/MemoryStore.swift` | Reads and writes the memory folder. |
| `Memory/MemoryEngine.swift` | Triggers, digest, apply and validate, consolidate. Runs off the main thread. |
| `Memory/ContextBuilder.swift` | Picks what to send with a talk message. |
| `Talk/TalkView.swift` | The conversation column. |
| `Map/MapView.swift` | Graph, layout, node and link detail, manual fixes. |
| `Versions/SnapshotStore.swift` | Timed snapshots per entry. |
| `Settings/SettingsView.swift` | The settings sheet. |

Changes inside `ContentView.swift` are limited to: the two bottom-bar words, swapping the Chat button for talk, hosting the talk column and the map, and calling the memory engine when an entry settles.

### On disk

```text
Documents/Freewrite/
  [uuid]-[date].md              entries, unchanged
  conversations/[uuid].md       talk history per entry
  versions/[uuid]/[time].md     snapshots
  memory/
    profile.md
    thoughts/<id>.md
    entries/<uuid>.json
    graph.json
    pins.json
```

Existing freewrite entries work as they are. Deleting the `memory` folder loses nothing you wrote.

## Privacy and care

**Stored locally is not the same as never leaving the Mac.** Entries and memory live only on your disk, but building memory and talking both send entry text to Claude through your API key. With AI off, nothing is sent anywhere. Settings should say this in one plain sentence.

- The API key lives in the Keychain.
- No analytics, no telemetry, no logging of entry text, including in debug logs.
- Memory building is opt-in and separate from talk, so you can talk without having every entry digested.
- "Forget everything" deletes the memory folder in one click.

**How talk mode behaves.** It sounds like a good therapist but is not one, and says so if asked.

- It reflects, asks, and is honest. It does not flatter, agree just to soothe, diagnose, or label.
- It points you toward the real people in your life when that fits.
- If an entry or message is about wanting to die, self-harm, or being in danger, it drops the reflective style, asks directly whether you are safe, and encourages reaching a real person: someone you trust, Tele-MANAS on 14416 in India, or local emergency services.
- It only states things about your past that it can tie to an entry.

## Milestones

Each one ends with a build you can use. Nothing after M2 is needed for the app to be useful.

| # | Milestone | Done when |
| --- | --- | --- |
| M0 | Fork builds | The fork runs unchanged from Xcode, under its new name, with the MIT license kept. |
| M1 | AI plumbing | You can paste a key in settings and a test message streams back from Claude. With AI off, the app makes no network calls. |
| M2 | Talk mode | Toggle on, it responds to today's entry, the conversation is saved per entry, toggle off and it is freewrite again. |
| M3 | Memory engine | After a week of entries, the memory folder holds a profile and thought notes, every one with quoted evidence, and unchanged entries are not reprocessed. |
| M4 | Memory in talk | Talk mode correctly brings up something from an earlier entry and names the day. |
| M5 | Map | The graph shows thoughts and links, node and link detail show evidence, clicking a day opens the entry. |
| M6 | Fixes and upkeep | Rename, merge, delete and link survive a rebuild. The weekly consolidate pass runs. |
| M7 | Versions and polish | Snapshots with restore, empty states, error messages, dark mode checked. |

## Second round

Added on 11 Nov 2026, after M0 to M7 were built and tried. Two things came out of that first try: without a Claude API key none of the new features could be seen at all, and the model names in Settings were typed text that a stray key press could break.

What stays the same: the look. Dear Diary keeps freewrite's design and stands apart through what it does. A set of three alternative themes was mocked up and dropped.

What changes:

- **Any AI, including a free one.** Settings offers four services: a free open model running on this Mac through Ollama, OpenAI by API key, Claude by API key, or any other service that speaks the OpenAI chat format. A ChatGPT or Claude subscription cannot be used here: neither includes API use by another app.
- **Models are picked, never typed.** The list comes from the chosen service.
- **Settings says what is missing** in one plain line, and old results do not linger.
- **Memory can be found.** The word "Memory" is always in the bottom bar. This is the one exception to principle 1: with AI off it shows whatever is already in memory, or one line on how to set memory up. Nothing is sent until AI is on.
- **Memory looks like a second brain.** The graph shows every day you wrote as a small grey dot, joined by thin straight lines to the thoughts it touched. Thoughts are the coloured dots, bigger the more days touch them. The thoughts that keep coming back end up as hubs with their days fanned around them.
- **A first run says what is here.** A new journal opens on a short Dear Diary welcome in place of freewrite's guide: what the page is, the three new things and that they are off, and where Settings is. A journal that already holds freewrite's guide keeps it.
- **Moving in from freewrite.** Settings can copy entries across from the original freewrite app, videos included. It copies and never moves, leaves the originals alone, and skips empty entries, freewrite's guide and anything already here. Copied entries are not read by the AI until you choose "Rebuild memory", which shows the count first.

| # | Milestone | Done when |
| --- | --- | --- |
| M8 | Settings and any AI | You can choose a service, pick its models from a list, and see what is missing. Talk and memory work through whichever service is chosen. With AI off, the app still makes no network calls. |
| M9 | Memory you can see | "Memory" is always in the bottom bar. The graph shows thoughts and days. Clicking a day shows what it touched and opens the entry. One thought can be dragged onto another to link them, and a thought can be found by name. |
| M10 | First run and moving in | A first run points to setting up AI. Entries from the original freewrite app can be brought across, and they show in History at once. |

## Open questions

- [ ] **Name.** The doc uses "freewrite with a memory" as a placeholder. The fork needs its own name and bundle ID.
- [ ] **Does talk speak first?** The draft says it opens with one short response when there is writing on the page. The alternative is that it always waits for you.
- [ ] **Do conversations feed memory?** The draft says only your entries do. Your side of talk conversations could be included too.
- [ ] **Which model for what?** Talk wants the best voice. Digest runs often and could use a cheaper, faster model. Both should be settings, not hard-coded.
- [ ] **Cost ceiling.** Digesting every entry costs API credits. Worth a monthly soft cap in settings?
- [ ] **Existing entries.** On first run, digest the whole back catalogue or only from today?

## How you'll know it works

This is for you, so the test is your own use over 30 days.

- You still open it to write on days you do not want AI at all.
- Talk mode tells you something about a pattern that you had not put into words, and the evidence checks out.
- You fix the map less each week, not more.
- You never catch it stating something about you that is not in your entries.
