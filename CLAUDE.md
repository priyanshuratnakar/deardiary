# Freewrite - Technical Documentation for AI Agents

> **⚠️ IMPORTANT FOR AI AGENTS**: This file (`AGENTS.md`) and `CLAUDE.md` are clones and must be kept in sync.
>
> Update both files when changes are **substantial** and meaningfully affect future agent understanding (for example: architecture, data flow, storage/permissions, threading behavior, user-facing workflows, or major bug fixes).
>
> For minor tweaks (small UI polish, copy edits, tiny refactors), updates are optional. Do **not** churn these docs on every small code change.
>
> If one file is updated, mirror the same change in the other file immediately.

## Dear Diary fork (read this first)

This repo is **Dear Diary**, a personal fork of freewrite that adds an AI talk mode, a local AI-built memory and a map of that memory. The spec is `docs/PRD.md` and is the source of truth for the fork. Everything below this section describes the original freewrite code, which the fork keeps and builds around. Where this document and the code disagree, trust the code.

### M0: renamed, no behaviour change

- **App name**: the built app is `Dear Diary.app` (`PRODUCT_NAME = "Dear Diary"`). The Xcode project, target, scheme, source folder and Swift module are all still called `freewrite` (`PRODUCT_MODULE_NAME = freewrite`), so the build command below is unchanged and upstream changes stay easy to pull in.
- **Bundle ID**: `com.priyanshuratnakar.deardiary` (test targets: `com.priyanshuratnakar.deardiaryTests` and `com.priyanshuratnakar.deardiaryUITests`).
- **Signing**: automatic signing with the owner's personal Apple Development team. To build on another Mac, set your own team on the three targets.
- **Where data really lives**: the app is sandboxed, so `Documents/Freewrite/` resolves to `~/Library/Containers/com.priyanshuratnakar.deardiary/Data/Documents/Freewrite/`. That is a different folder from the original freewrite app's container (`app.humansongs.freewrite`), so the two apps do not see each other's entries. The folder name `Freewrite` and the entry filename format are unchanged.
- **Permission prompts** (camera, microphone, speech recognition) say "Dear Diary" instead of "Freewrite".
- `LICENSE` (MIT, Farza's copyright notice) is kept as is.

### M1: AI plumbing

With AI off (the default) the app still behaves exactly like freewrite and makes no network requests. Nothing was added to the writing page.

New files (the project picks up anything under `freewrite/` automatically, no project edits needed):

- `freewrite/AI/LLMProvider.swift`: the provider-neutral interface. `stream(_:)` returns the reply piece by piece, `complete(_:)` returns it whole. Also `LLMRequest`, `LLMMessage` and `LLMError`, whose `userMessage` is the plain sentence shown to the user.
- `freewrite/AI/AnthropicProvider.swift`: Claude's Messages API over `URLSession` (no SDK). `POST https://api.anthropic.com/v1/messages` with headers `x-api-key`, `anthropic-version: 2026-10-21`, `content-type: application/json`. The body carries only `model`, `max_tokens`, `system`, `messages` and `stream`. It never sends `temperature`, `top_p` or `top_k` (this API version rejects them) and sends no `thinking` or `effort` settings, so each model runs with its own defaults and any model name typed in Settings works. `AnthropicStreamParser` reads the `data:` lines of the event stream, keeps `text_delta` text, and skips pings, thinking and unknown event types. A `stop_reason` of `refusal` becomes `LLMError.refused`.
- `freewrite/AI/AISettings.swift`: AI on or off (default off), the talk model and the memory ("digest") model, stored in UserDefaults under `ai.enabled`, `ai.talkModel`, `ai.digestModel`. **Model IDs exist only here**, as defaults and settings. Never write a model ID into networking or feature logic.
- `freewrite/AI/Keychain.swift`: the API key, stored as a generic password in the macOS Keychain (service `<bundle id>.anthropic-api-key`). It is never written to a file or to UserDefaults.
- `freewrite/AI/Prompts.swift`: every prompt the app sends. Add digest and consolidate prompts here, not next to the code that uses them.
- `freewrite/Settings/SettingsView.swift`: the Settings window (AI on/off, API key, the two models, a Test connection button). It is opened from the app menu (Settings…, ⌘,) through a SwiftUI `Settings` scene in `freewriteApp.swift`.
- `freewrite/Settings/StorageRoot.swift`: decides which folder the journal lives in (see below).

**The network gate.** (Widened in M8 to three clients, each with its own gate; see below.) Every request goes through `AnthropicProvider.authorizedRequest`, which calls `AISettings.access()` first. If AI is off or there is no key, it throws `LLMError.aiOff` or `.missingKey` before `URLSession` is touched. All AI networking must go through `AnthropicProvider`; do not create another `URLSession` anywhere else.

**Privacy rules for new code.** Never log entry text, memory content, prompts, replies or the API key, including in debug `print`s. The AI and Settings files contain no `print` calls; keep it that way.

**Storage root.** `ContentView` no longer builds the journal path itself; it reads `StorageRoot.url` (the only change made to `ContentView.swift` in M1). The folder is chosen once at launch:

1. If the environment variable `DEARDIARY_STORAGE_ROOT` is set, that folder is used. The app is sandboxed, so it must be inside the app's container, for example `~/Library/Containers/com.priyanshuratnakar.deardiary/Data/tmp/dev-journal`.
2. If the app was started by Xcode's test runner, a fresh folder under the temporary directory is used.
3. Otherwise `Documents/Freewrite`, as before.

Agents: never run or test against the owner's real journal. Launch development builds with `DEARDIARY_STORAGE_ROOT` set, and use made-up entries. macOS also blocks other processes from reading the app's container, so check storage through the app's own console output rather than by listing the folder.

**Entitlement added:** `com.apple.security.network.client` (outgoing connections), and nothing else.

**Tests.** Run them with:

```bash
xcodebuild test -project freewrite.xcodeproj -scheme freewrite -only-testing:freewriteTests
```

The unit tests start the app itself, which is why the storage root switches to a temporary folder under test. They never use the real network (`StubURLProtocol` in `freewriteTests/TestSupport.swift` answers every request), the real API key (a throwaway Keychain service) or the real preferences (a throwaway UserDefaults suite). `SettingsSnapshotTests` draws the Settings window off screen and attaches a picture to the test results. The UI test target is freewrite's and is not part of this command.

### M2: talk mode

Talk is a conversation column that opens beside the page when the user clicks "Talk" in the bottom bar. It is off by default, and no request is made while it is off.

New files:

- `freewrite/Talk/TalkController.swift`: `TalkController` (is talk available, is it on, building requests, saving), `TalkTranscript` (what the column shows) and `TalkEntry` (the entry being read).
- `freewrite/Talk/TalkView.swift`: `TalkView` (what `ContentView` hosts), `TalkColumn` (the conversation and input), `TalkWordButton` (the bottom-bar word), `TalkStyle` and `BackspaceLockScope`.
- `freewrite/Talk/ConversationStore.swift`: `TalkMessage` and the markdown file format.
- `freewrite/AI/Prompts.swift` now holds the talk voice and safety behaviour (`talkVoice`, `talkSystem`, `talkOpener`, `talkDeclinedNotice`), written from the PRD's "Privacy and care" section.

Rules the code follows (keep them when changing it):

- **When Talk shows.** Only when AI is on and a key is saved (`TalkController.isAvailable`; since M8, when the chosen service is ready) and a text entry is open. Otherwise freewrite's "Chat" button is shown, unchanged. Video entries always keep "Chat".
- **When talk speaks first.** Once, at the moment it is switched on, and only if the page has writing and that entry has no saved conversation. Showing a different entry while talk is on never sends anything by itself.
- **What is sent.** Each request is `Prompts.talkSystem` (the voice plus the entry as it reads at that moment, between `<entry>` markers) and the conversation so far. Since M4, notes from memory are added when memory is on (see below).
- **Off means off.** Switching talk off, switching AI off in Settings, or removing the key cancels any reply in progress and drops the partial text. A cancelled request that has not started yet is never sent.
- **Storage.** One file per entry at `conversations/[ENTRY-UUID].md` inside the journal folder: a `# Talk` title, then `## You · yyyy-MM-dd HH:mm:ss` and `## Dear Diary · …` headings, each followed by the text. It is plain markdown and can be edited or deleted by hand. Deleting an entry deletes its conversation.
- **Declined replies.** Talk requests set `retryIfDeclined`, which makes `AnthropicProvider` send `fallbacks: "default"` with the header `anthropic-beta: server-side-fallback-2026-07-01`; Anthropic then retries a declined request on a model it chooses. If a model rejects that option (HTTP 400), the provider asks again without it and remembers for the rest of the run. If the reply is still declined, the column shows `Prompts.talkDeclinedNotice`, which repeats the PRD's support options.
- **Failure is quiet.** Errors appear as one plain sentence in the column, with a "Try again" word. They never interrupt the page.

Performance notes:

- `ContentView` observes `TalkController`, which only publishes `isAvailable` and `isOn`. The fast-changing state lives in `TalkTranscript`, which only `TalkColumn` observes, so a streaming reply does not redraw the page.
- `TalkView` hands the page text to the controller through `onChange` without redrawing the conversation.

Changes in `ContentView.swift` (all marked with a "Dear Diary" comment):

1. One `@StateObject` line for `TalkController`.
2. The backspace check also asks `BackspaceLockScope.applies(to:)`, so "Backspace is Off" still locks the page but no longer blocks deleting in the talk box or in Settings fields.
3. An `if`/`else` around the "Chat" button. **The Chat code inside the `else` is deliberately not re-indented**, so it still matches upstream freewrite line for line. Do not reformat it.
4. The talk column, placed between the page and the history sidebar (340pt wide).
5. One line in `deleteEntry` so the entry's conversation is deleted too.

Tests added: `ConversationStoreTests`, `TalkControllerTests` (with `TalkPromptTests` and `BackspaceLockScopeTests`), more `AnthropicProviderTests`, and two picture tests, `TalkSnapshotTests` and `PageSnapshotTests`. `FakeProvider` in `freewriteTests/TalkTestSupport.swift` is a pretend AI that answers from a script. To look at the pictures after a test run:

```bash
xcodebuild test -project freewrite.xcodeproj -scheme freewrite -only-testing:freewriteTests -resultBundlePath /tmp/deardiary.xcresult
xcrun xcresulttool export attachments --path /tmp/deardiary.xcresult --output-path /tmp/deardiary-pictures
```

Under test, `AISettings.shared` is a throwaway copy, so tests never read the real preferences or key.

### M3: memory engine

Memory is a folder of small notes the AI writes about what the user writes. It is off by default, separate from talk, and nothing is sent unless AI is on, memory is on and a key is saved.

On disk, inside the journal folder:

```text
memory/
  profile.md              a short running picture, rewritten as things change
  thoughts/<id>.md        one readable note per thought; <id> is a readable name such as saying-yes-under-pressure
  entries/<UUID>.json     one digest per entry: summary, thoughts touched, open loops, a fingerprint of the text
  pins.json               the user's manual fixes, made on the map (see M6); the AI must obey them
```

`graph.json` (the graph as last drawn, with where each dot sits) is written by the map; see M5. Thought notes link to each other with `[[wikilinks]]`, so the folder opens as an Obsidian vault. The exact note format is described at the top of `freewrite/Memory/ThoughtNote.swift`.

New files, all in `freewrite/Memory/`:

- `MemoryModel.swift`: the plain data (`Thought`, `Evidence`, `TimelineNote`, `ThoughtLink`, `EntryDigest`, `Pins`, `MemorySnapshot`) and name helpers.
- `ThoughtNote.swift`: turns a thought into its markdown note and back.
- `MemoryStore.swift`: the only code that reads or writes the memory folder.
- `DigestResult.swift`: the shape of the AI's reply, the strict parser, and the same shape as a JSON schema for Claude. The parser and the schema must stay in step; a test checks this.
- `QuoteMatcher.swift`: finds a quote in an entry. It forgives spacing and quote-mark or dash style, nothing else, and returns the entry's own text.
- `MemoryApplier.swift`: decides what from a digest is allowed into memory. It works on data in hand and touches no files.
- `JournalReader.swift`: lists and reads entry files for the engine. It never writes.
- `MemoryEngine.swift`: the background engine (an `actor`), its limits, and `MemoryStatus` for Settings.

How a digest goes in (keep these rules when changing the code):

1. **Settled entries only.** An entry is digested when it has not been edited for 10 minutes, or a newer entry exists, or the day has changed, or talk was just switched on. An entry edited in the last minute is never digested, whatever else is true.
2. **One request per entry.** The request carries the profile, an index of existing thoughts (`Prompts.digestIndexLine`) and the entry, with `Prompts.digestSystem` as instructions and `DigestSchema` as the required reply shape (`output_config.format` on the API).
3. **Strict parse.** `DigestParser` refuses anything that is not exactly the expected object. Such an entry is marked `failed` in its digest file and left alone until its text changes or memory is rebuilt, so a bad answer is never asked for in a loop.
4. **No invented evidence.** Every new thought, update, timeline note and link needs a quote that `QuoteMatcher` finds in the entry. What is stored is the text cut from the entry, never the model's copy. Items without one are refused and listed under `rejected` in the digest file.
5. **The user's fixes win.** Anything that conflicts with `pins.json` is refused: deleted thoughts cannot come back or be added to, merged-away ids are redirected, renamed labels are kept, removed links are not put back.
6. **Reuse before create.** A "new" thought whose label, other name or file name matches one in memory is attached to the existing thought.
7. **Idempotent.** Applying an entry first removes everything that entry contributed before, so an edited entry never leaves duplicates. A thought left with no evidence is removed. Deleting an entry removes its lines from memory.
8. **Unchanged entries are skipped.** The digest file stores a SHA-256 fingerprint of the entry text.

Other behaviour:

- Switching memory on does not send older entries: only entries edited after that moment are digested. "Rebuild memory" in Settings digests everything, after showing the count.
- A rebuild clears what the AI built and keeps `pins.json` and any note that cannot be read (it may be a hand edit). Notes that cannot be read are never overwritten and their file names are never reused.
- Background work stops at 40 requests a day (`MemoryLimits.dailyRequests`); a rebuild is not held back by this. Token counts are saved in each digest file.
- Failures are quiet: one plain line in Settings, then another try after five minutes. A declined or cut-off reply marks that entry as failed and the rest carry on.
- "Forget everything the AI has learned" deletes the memory folder (fixes included) and switches memory off, after a second confirming click.
- The engine skips video entries, empty entries and freewrite's bundled welcome guide.
- Talk conversations do not feed memory; only entries do.

Wiring:

- `ContentView.swift` is not touched by M3. The engine looks at the journal folder itself, once a minute; while memory is off each check returns at once without reading or sending anything.
- `freewriteApp.swift` gains one line that starts the engine at launch.
- `TalkController` nudges the engine when talk is switched on.
- `AnthropicProvider` now fetches every reply as a stream, including whole replies, so a long answer cannot time out. It can ask for a required JSON shape and reports token counts. A reply that ends without its closing event is treated as cut off. A model that rejects the optional features (the retry on decline, the JSON shape) is asked again without them and remembered for the rest of the run.
- `AISettings` has the memory switch (`ai.memoryEnabled`) and when it was last switched on (`ai.memoryEnabledAt`).

Agents: never run the engine against the owner's real journal. Tests use `MemorySandbox` (a throwaway folder and a clock the test controls) and `MemoryWeek` (a made-up week of entries with scripted replies) from `freewriteTests/MemoryTestSupport.swift`. `MemorySampleTests` builds a whole memory folder from that week and attaches the files to the test results, which is the easiest way to see the format.

### M4: memory in talk

When memory is on, talk is given the relevant notes from memory with each message, and is told to name the day when it draws on the past. Nothing on screen changed and `ContentView.swift` was not touched.

- `freewrite/Memory/ContextBuilder.swift` picks what is sent, on the Mac, with no AI call. It always sends the profile. It sends the thoughts whose label or other names appear (as whole words, ignoring a leading "the", "a", "an" or "my") in the open entry or in the last few things said in the column, the thoughts the open entry's digest already touched, and the thoughts linked to those, one step away. Each comes with its description, its most recent quoted lines and timeline notes with their days, and its links to other thoughts being sent. The summaries of the entries behind those lines are added.
- **Only the past is sent.** Lines that came from the open entry are left out, because talk already has the entry itself. A thought known only from the open entry is not sent.
- **Limits** (`ContextBuilder.Limits`): six named thoughts, six neighbours, three quotes and two timeline notes each, six day summaries, and about 9,000 characters in all. When over the size limit, neighbours are dropped first, then day summaries, and named thoughts last.
- `Prompts.swift`: the talk instructions are now built from parts. `talkManner` and `talkSafety` are always sent. Between them goes `talkKnowsTheEntryOnly` (memory off or empty; this is exactly what M2 sent) or `talkKnowsMemory` (use the notes only when they help, state nothing about the past that is not in them, name the day, never recite the profile). `talkMemoryNotes` lays the notes out between `<memory>` markers, with days written in full ("Monday 2 November 2026").
- `TalkController` reads the memory folder off the main thread before each reply, and only when `AISettings.memoryAllowed()` is true (AI on, memory on, a key saved). With memory off, nothing from the memory folder is read or sent by talk.
- Talk does not wait for the open entry to be digested; it uses memory as it stands.
- The rule against stating things that are not in the notes is an instruction to the model, not something the app can check.

`MemorySampleTests.testWhatTalkIsSentFromMemoryForANewEntry` attaches the full instructions talk would be sent for a sample entry, which is the easiest way to read exactly what leaves the Mac with a talk message.

### M5: the map

A full-window view of memory as dots and thin lines, opened from the "Map" word in the bottom bar. It reads the memory folder and makes no AI call of its own (opening it nudges the memory engine, as switching talk on does).

New files, all in `freewrite/Map/`:

- `MemoryGraph.swift`: `GraphNode`, `GraphEdge`, `MemoryGraph`; `GraphBuilder`, which builds the graph from the thought notes; the `memory/graph.json` file; and `MapPalette`, the colour for each kind of thought.
- `GraphLayout.swift`: where the dots sit.
- `MapModel.swift`: loading, panning and zooming, what is under the pointer, moving a dot, which names are shown, and what the detail panel shows.
- `MapView.swift`: `MapView` (what `ContentView` hosts), `MapScreen` (the canvas, the words along the bottom, the legend) and `MapWordButton` (the bottom-bar word).
- `MapDetailView.swift`: the panel on the right for a selected thought or link.

How it works (keep these when changing it):

- **The notes are the source of truth.** The graph is rebuilt from the thought notes every time the map opens. One dot per thought, sized by how many different entries touched it; one line per linked pair, however many entries show the link.
- **Only positions are remembered.** `memory/graph.json` holds the graph as last drawn, but only each dot's position is read back. The file survives "Rebuild memory" and is removed by "Forget everything".
- **The map settles once and stays still.** `GraphLayout.settle` places only the thoughts that have no remembered position, near what they are linked to, and never moves a dot that already has a place. The same input always gives the same picture; nothing is random. It runs off the main thread.
- **Colour is for dots only.** `MapPalette` holds the only colours in the app: seven, one per kind, stepped separately for the white and the black background. They are a tested set (neighbours in the list can be told apart, including with the common forms of colour blindness), but seven scattered colours cannot all be told apart by everyone, so the kind is always in words too: in the legend, above a dot on hover, and in the panel. Text on the map never takes a dot's colour.
- **Names.** With 40 thoughts or fewer every name shows. With more, names are placed in order of importance (under the pointer or selected, then most recurring) and a name is skipped if it would cover another name or another dot; the ten most recurring are always named. Zooming in makes room for more.
- **Pointer.** Drag empty space to move the map; drag a dot to move it (saved when let go); pinch to zoom; a trackpad scroll moves the map and a mouse wheel zooms it. Hovering a dot makes it and its links stand out. Clicking a dot or a line opens the panel; clicking empty space closes it. "Fit" brings everything into view. "Close" or Esc returns to the page.
- **The panel.** For a thought: its description, how it has shifted, the quoted lines grouped by day, and what it is linked to. For a link: the reasons and the lines that show it. Clicking a day closes the map and opens that entry.
- **Empty and error states** are one plain line each, in the map.

Changes in `ContentView.swift` (all marked with a "Dear Diary" comment):

1. One `@State` line, `showingMap`.
2. The "Map" word in the bottom bar after Talk, shown when `talk.isAvailable` (AI on and a key saved).
3. A second `.overlay` that hosts `MapView` over the whole window, the way the video recorder is shown. Its `onOpenEntry` saves the open entry, then selects and loads the chosen one, as a click in History does.

Rename, merge, delete and link editing were added in M6, below.

Tests: `MapTests.swift` (graph building, layout, `graph.json`, the model, the panel's content) and `MapSnapshotTests.swift` (pictures of the map with the made-up week, a thought and a link selected, a crowd of 300 thoughts, and the empty state). `MapFixtures.crowd` in `freewriteTests/MapTestSupport.swift` makes a repeatable crowd of thoughts. Never draw the real `ContentView` with the map open against real memory in a test.

### M6: fixes and the weekly tidy

Two things were added: the user can correct memory from the map, and about once a week the AI looks across all of memory. `ContentView.swift` was not touched.

**The user's fixes**

- `freewrite/Memory/MemoryFixes.swift`: `MemoryFix` (rename, merge, delete, add a link, remove a link) and `MemoryFixes`. `apply` makes one fix on memory in hand and records it in the fixes; `enforce` puts every recorded fix back on memory and is the last step of every digest and every tidy.
- `MemoryModel.swift`: the shape of `pins.json` (`Pins`), plus `UserLink` and `Thought.userLinks` for links the user made by hand.
- `ThoughtNote.swift`: a note with hand-made links gets a `## Linked by you` section (`- [[other-thought]] · reason`). Notes without any are written exactly as before.
- `MemoryEngine.fix(_:)` is the only way a fix is made. It runs inside the engine, so it cannot collide with a digest being written. It saves `pins.json` first and the notes second, needs no AI, and works with memory off.
- The map: `MapPending` (a fix that is part-way through), `MapModel.perform`, and the fix words in `MapDetailView`.

`pins.json`:

```json
{
  "renames":       [{"id": "saying-yes-under-pressure", "label": "Agreeing too fast", "names": ["Saying yes under pressure"]}],
  "merges":        [{"from": "people-pleasing", "into": "saying-yes-under-pressure", "names": ["People pleasing"], "into_label": "Agreeing too fast"}],
  "deletions":     [{"id": "running", "label": "Running", "names": []}],
  "links_added":   [{"from": "running", "to": "trouble-sleeping", "reason": "helps with"}],
  "links_removed": [{"from": "meera", "to": "the-pricing-page"}]
}
```

The file is removed when it holds no fixes. Rules (keep these when changing the code):

1. **A fix is matched by name as well as by file name.** Each fix records what the thought was called at the time (`names`, `into_label`). After a rebuild the AI may name a thought a little differently, so a renamed thought is found again by its old names and keeps its file name, a merged thought is sent to the thought it was folded into, and a deleted thought stays deleted under any of its names.
2. **A link is the pair, in either order.** Removing a link removes every line of evidence for it both ways, and the AI cannot add it back in either direction.
3. **A hand-made link has no quoted line**, and the panel says so ("Linked by you. There is no quoted line behind this."). It is drawn like any other link.
4. **Deleting or merging moves the user's own links** with the thought, or drops them if they no longer make sense.
5. **Memory is read fresh before anything is written.** After each AI reply, the engine reloads the notes and `pins.json` from disk before applying it, so a fix made on the map while a digest or a tidy was with the AI is obeyed.

On the map, the fix words sit along the bottom of the panel, always in view: Rename, Merge into…, Link to…, Delete for a thought; Remove link for a link.

- Rename: type the new name, Return or Save.
- Merge and link: click the word, then click the other thought on the map. While picking, no dot is faded. A click on empty space, Cancel, or Esc backs out. Merge then asks for a second click; link asks for a few words on how the two are linked.
- Delete and Remove link ask for a second click in the panel. Nothing uses an alert window.
- Selecting something else drops a fix that was part-way through. Esc backs out of a fix first and closes the map second.

**The weekly tidy**

One request that looks across all of memory, which a single entry's digest cannot do.

- `freewrite/Memory/TidyResult.swift`: the shape of the reply (`TidyResult`), the strict parser (`TidyParser`) and the same shape as a JSON schema (`TidySchema`). As with digests, the parser and the schema must stay in step; a test checks this.
- `freewrite/Memory/MemoryTidier.swift`: decides what from a tidy is allowed to change memory. It works on data in hand and touches no files.
- `Prompts.tidySystem` and `Prompts.tidyMessage`: the instructions, and the material sent (the profile, every thought with its last six quoted lines and its links, and the summaries of the last 40 entries).
- `MemoryEngine.tidy(force:)` and the limits in `MemoryLimits` (`tidyEvery`, `tidyMinimumThoughts`, `tidyAfterRebuild`, `oneOffAfterDays`).

When it runs:

- By itself: at the end of the engine's once-a-minute check, when memory is on, memory holds at least eight thoughts, and seven days have passed since the last tidy. The first time, it only starts the week. It counts toward the daily limit of 40 requests.
- At the end of "Rebuild memory" (not held back by the daily limit).
- From "Tidy memory now" in Settings.

What it may do, and the checks (keep these when changing the code):

1. **Merge duplicates.** Both thoughts must exist. A thought the user renamed or linked by hand is never folded away.
2. **Retire one-offs.** The model only suggests. The app's rule decides: the thought appears in exactly one entry, that entry is more than three weeks old, and the user has not renamed or linked it. A retired thought is not recorded as a fix, so it can come back if the topic returns.
3. **Add patterns and links that show across weeks.** Each needs quoted lines from at least two different entries, every quote checked against the entry it cites with `QuoteMatcher`. What is stored is the entry's own text. A pattern that already has a thought adds to it instead of making another.
4. **Refresh the profile.**
5. **The user's fixes have the last word**, exactly as in a digest.

An answer that cannot be read changes nothing and is not asked for again until the next tidy is due. Network trouble shows one plain line in Settings and leaves the tidy due. Settings shows what the last tidy did, for example "Tidied on Monday 30 November 2026: merged 1, retired 2, 1 pattern across weeks." The time and that line are kept in UserDefaults (`memory.tidy.at`, `memory.tidy.line`) and are cleared by "Forget everything".

Tests: `MemoryFixesTests.swift` (each fix, and `FixesSurviveARebuildTests`, which rebuilds memory after each kind of fix), `MemoryTidyTests.swift` (the parser and schema, `MemoryTidier`, and when the tidy runs), `MapFixTests.swift` (the fix steps on the map through the real engine, and pictures of the panel in each state). `MemorySandbox.quietLimits` switches off the tidy after a rebuild for tests that are not about it. `FakeProvider.onRequest` lets a test change memory while a request is "with the AI".

### M7: versions and polish

**Versions.** Each entry can keep timed copies of itself, so an earlier state can be read and brought back. Versions have their own switch in Settings ("Versions are On"), off by default. They have nothing to do with AI: nothing is sent anywhere and they work with AI on or off. With the switch off nothing is saved and nothing is shown, so the app is freewrite.

On disk, inside the journal folder: `versions/[ENTRY-UUID]/[yyyy-MM-dd-HH-mm-ss].md`. Each file is the entry's text exactly as it was at that time.

New files, all in `freewrite/Versions/`:

- `SnapshotStore.swift`: the only code that reads or writes the versions folder (`EntryVersion`, `SnapshotStore`).
- `VersionSettings.swift`: the switch, `versions.enabled` in UserDefaults. Under test, `VersionSettings.shared` is a throwaway copy and off.
- `SnapshotKeeper.swift`: the background keeper (an `actor`), with `VersionLimits`, `VersionEnvironment` and `VersionIndex` (what the sidebar and Settings observe).
- `VersionsView.swift`: `VersionsModel`, `VersionsView` (what `ContentView` hosts), `VersionsScreen`, `VersionsIconButton` (the icon in a History row) and `VersionText`.

Rules the code follows (keep them when changing it):

1. **The keeper only reads entries.** Like the memory engine it looks at the journal folder itself, once a minute, off the main thread, and reads the files freewrite has already saved. It never writes an entry file and typing never waits for it.
2. **When a version is saved.** When the entry's text differs from its newest version and five minutes have passed since that version (for an entry with no version yet, since the entry was started). So a long writing session leaves a copy every five minutes, and the state an entry was left in becomes a copy within five minutes.
3. **Entries that already exist get one copy** on the first check after versions are switched on, so the first later edit to an old entry can be undone.
4. **Skipped:** empty entries, video entries and freewrite's welcome guide. Text that has not changed is never copied twice.
5. **The newest 50 versions** of each entry are kept (`VersionLimits.keep`).
6. **The History icon shows only when there is something earlier to see:** the entry has more than one version, or one version and an edit since. With versions off the index is empty, so the sidebar is freewrite's own.
7. **A restore can always be undone.** Before a restore, the entry as it reads now is saved as a version, whatever the time. If that fails, nothing is restored. The versions code never writes the entry itself: it hands the text to `ContentView`, which puts it on the page, and freewrite's own auto-save writes the file.
8. **Deleting an entry deletes its versions**, even while versions are off.
9. **Switching versions off** stops saving and hides the icons. Files already saved are left alone.
10. **Failure is quiet:** one plain line under "Versions are On" in Settings.

The versions screen covers the whole window, the way the map does. The chosen version is on the left in the page's font and size, read only. The list of times is on the right, styled like History (200pt wide). "Restore this version" and "Close" are words along the bottom; Esc closes. It opens on the newest version that differs from the entry. The version that matches the entry says "This is how the entry reads now" instead of offering a restore.

Changes in `ContentView.swift` (all marked with a "Dear Diary" comment; these four are outside the PRD's list and were approved by the owner):

1. One `@State` line, `versionsEntryId`.
2. One line adding `VersionsIconButton` to the hover icons in a History row. The export and delete code beside it is not re-indented.
3. A third `.overlay` hosting `VersionsView`. Its `onRestore` opens that entry the way a click in History does, then sets the page text.
4. One line in `deleteEntry`.

`freewriteApp.swift` gains one line that starts the keeper at launch. `SettingsView` gains the versions section and `VersionActions`.

**Polish.**

- **Messages.** Every error line the fork shows is in one voice: short, plain, and saying what to do next when there is something to do. The full list, with the file each one lives in, is `docs/messages.md`. Update that list when wording changes.
- **Empty states.** Each is one or two plain lines. The empty map now says the right thing whether memory is on or off (`MapScreen.memoryIsOn`). The empty talk column stays blank on purpose, like the page.
- **Dark mode.** Every new screen is drawn in both modes by the picture tests. `AppearanceTests` measures each text colour against its background in both modes: body and strong text at 7 to 1 or better, the quiet grey words (freewrite's own bottom-bar grey) and secondary text at 3 to 1 or better. Dots on the map are at 3 to 1 or better on black; on white the amber for ideas is the weakest at a little over 2 to 1, which is one reason the kind is always in words too.

Tests: `VersionsTests.swift` (the store, the keeper with a clock the test controls, the screen's model, the switch), `VersionsSnapshotTests.swift` (pictures of the versions screen and the History icon) and `AppearanceTests.swift`.

### M8: any AI, and Settings that cannot be broken

M8 is the first milestone of the second round (see "Second round" in `docs/PRD.md`). The look stays freewrite's. `ContentView.swift`, the entitlements and the project file were not touched.

**Four services.** "Runs on" in Settings chooses between them (`AIProviderKind` in `AISettings.swift`): `local` ("On this Mac", a free open model through Ollama), `openai`, `claude` (the default, so nothing changes for an existing setup) and `other` (any address that speaks the OpenAI chat format). Each service keeps its own models and its own key.

New and changed files, all in `freewrite/AI/` unless noted:

- `AISettings.swift`: `AIProviderKind`, the chosen service (`ai.provider`), models per service (`ai.<service>.talkModel` and `ai.<service>.digestModel`; Claude keeps `ai.talkModel` and `ai.digestModel`), the address for "Other" (`ai.other.baseURL`), `setupGap` (what is still missing: a key, an address or a model), `isReady` and `readiness`. Only Claude has default models. The others have none, so nothing is ever sent to a model the user did not pick.
- `Keychain.swift`: one item per service. `sibling(named:)` gives OpenAI's and Other's items beside Claude's.
- `LLMProvider.swift`: `AIRouter` (sends each request to the chosen service, and refuses a request with no model), `LLMError.userMessage(for:)` (the same problem described in the name of the service in use), `AIModelChoice`, and `ThinkTagFilter` (drops private thinking that some open models mix into a reply as `<think>…</think>`).
- `OpenAICompatibleProvider.swift`: the OpenAI chat format over `URLSession`. `POST {base}/chat/completions`, streamed, ending with `data: [DONE]`. For OpenAI it sends `max_completion_tokens` and asks for token counts; for "Other" it sends the older `max_tokens`. A required JSON shape goes as `response_format` with a strict schema.
- `OllamaProvider.swift`: Ollama's own chat format. `POST http://localhost:11434/api/chat`, streamed as one JSON object per line. It always sends `options.num_ctx` (`AILimits.localContextTokens`, 16,384), because Ollama's default of about 4,000 tokens would silently cut off an entry and its memory. That is why it does not use Ollama's OpenAI-style address, which cannot set this. A required JSON shape goes as `format`.
- `AnthropicProvider.swift`: gains `models()` (`GET /v1/models?limit=100`).
- `ModelCatalog.swift`: the list of models the chosen service offers, for the pickers.
- `freewrite/Settings/SettingsView.swift`: the "Runs on" row, the key and address rows, `ModelPickerRow` and `ModelList` (a pop-up list in the style of freewrite's Chat pop-up).

Rules the code follows (keep them when changing it):

1. **Every client has a gate, checked before the network is touched.** Claude: `AISettings.access()`. OpenAI and Other: `AISettings.endpointAccess()`. Ollama: `AISettings.localAccess()`. Each is shut when AI is off and when another service is chosen. This replaces M1's rule that all networking goes through `AnthropicProvider`: `URLSession` may now appear in the three client files and nowhere else.
2. **The model list obeys the same gates.** `ModelCatalog` asks for nothing while AI is off or while a key or an address is missing. Opening Settings with AI off makes no network request, not even to this Mac.
3. **Models are picked from the service's own list.** The one exception is "Other" when the service has no list to give: then the name is typed, and Settings says why.
4. **On this Mac, the first model found is used** until the user picks another, and a model that has been removed from Ollama is replaced. For the other services no model is chosen on the user's behalf.
5. **Talk and Map show when the chosen service is ready** (`AISettings.isReady`: AI on, a key if the service needs one, an address for Other, a talk model). `TalkController` follows `AISettings.readiness`, which announces changes at once. Memory needs a memory model as well (`memoryAllowed()`).
6. **Optional parts are dropped, once, if a model rejects them.** A request refused with HTTP 400 is sent again without the required JSON shape (and, for the OpenAI format, without the ceiling on the reply), and that model is remembered for the rest of the run. The prompts already describe the shape and the parsers are strict, so a reply in the wrong shape is still refused.
7. **Only Claude gets the retry on a declined reply** (`retryIfDeclined`). The other clients ignore it.
8. **Model names still live only in `AISettings`**, and now only as Claude's two defaults.
9. **Old results do not linger in Settings.** The result of "Test connection" is cleared when AI, the service, its key or the talk model changes, and the word is switched off until the service is ready.

Plain HTTP to `localhost` works from the sandboxed app with the entitlement it already has; this was tried, and no change to the project was needed.

Messages: every line that used to say "Claude" now names the service in use. `docs/messages.md` lists them all.

Tests: `ProviderTests.swift` (the settings for each service, the gates, both new clients, Claude's model list, the router, the model catalogue, the thinking filter, messages per service) and more pictures in `SettingsSnapshotTests.swift` (every service and the states in between). `StubURLProtocol` can now keep canned replies apart by host (`install(forHost:)`), so the suites for different clients run side by side. `SettingsBox` in `ProviderTestSupport.swift` gives throwaway settings with their own Keychain items. Nothing has been tried against a real OpenAI or Ollama server.

## Product Vision & User Experience

### What is Freewrite?

Freewrite is a **distraction-free writing environment** for macOS designed around the concept of stream-of-consciousness writing and video journaling. The core philosophy is to remove barriers between thought and writing by creating a minimalist, opinionated interface that prioritizes the act of writing over formatting, organization, or editing.

### User Experience Philosophy

**Core Principles:**
1. **No Backspace (Optional)**: Users can disable the backspace key to encourage forward-thinking writing without self-editing
2. **Timed Sessions**: Built-in timer (default 15 minutes) creates focused writing sprints
3. **Auto-Everything**: Auto-save, auto-new-entry, auto-timestamp - the app manages logistics so users can focus on writing
4. **Local-First**: All data stays on the user's machine in plain markdown files they can access directly
5. **Minimal UI**: Most UI elements hide during timed sessions, leaving only the text

### Use Cases

**Primary Use Case - Stream of Consciousness Writing:**
- Users open the app and start writing immediately (no "New Document" dialog)
- The app creates a new entry automatically at the start of each day
- Writing is saved continuously with no manual save action
- Timer creates urgency and prevents over-editing
- Backspace disable forces forward momentum in thinking

**Secondary Use Case - Video Journaling:**
- Quick video capture for visual thoughts/ideas
- Video entries stored alongside text entries in chronological history
- One-click recording with built-in timer
- Local storage ensures privacy for personal video journals

**Tertiary Use Case - AI-Assisted Reflection:**
- "Chat" button sends writing to ChatGPT or Claude
- Prompts designed to help users reflect on and understand their writing
- AI provides feedback, questions, or analysis of stream-of-consciousness text

**Hidden Power Feature - Long-Form Writing:**
- Despite minimalist interface, supports full markdown
- Entries can be exported as PDFs
- Font and size customization for comfort during long sessions
- Dark mode for night writing

## Overview

Freewrite is a native macOS writing application built with SwiftUI that allows users to write text entries and record video entries. All data is stored locally in `~/Documents/Freewrite/`.

## Architecture

### Technology Stack
- **Framework**: SwiftUI (macOS)
- **Minimum macOS Version**: 14.0
- **Language**: Swift 5.0
- **Build System**: Xcode
- **Media**: AVFoundation for camera/video recording

### Project Structure

```
freewrite/
├── freewrite.xcodeproj/          # Xcode project file
├── freewrite/
│   ├── freewriteApp.swift        # App entry point
│   ├── ContentView.swift         # Main view (1400+ lines)
│   ├── VideoRecordingView.swift  # Video recording interface
│   ├── VideoPlayerView.swift     # Video playback interface
│   └── freewrite.entitlements    # App permissions
├── CLAUDE.md                     # This file
└── AGENTS.md                     # Duplicate of this file
```

## Data Model

### Entry Types

```swift
enum EntryType {
    case text
    case video
}

struct HumanEntry: Identifiable {
    let id: UUID
    let date: String              // Display format: "MMM d" (e.g., "Feb 20")
    let filename: String          // Format: [UUID]-[YYYY-MM-DD-HH-mm-ss].md
    var previewText: String       // First 30 chars or "Video Entry"
    var entryType: EntryType      // .text or .video
    var videoFilename: String?    // Format: [UUID]-[YYYY-MM-DD-HH-mm-ss].mov
}
```

### File Storage

**Location**: `~/Documents/Freewrite/`

**Text Entries**:
- Format: Markdown (.md)
- Naming: `[UUID]-[YYYY-MM-DD-HH-mm-ss].md`
- Content: Plain UTF-8 text
- Example: `[6910BBDE-75FC-415C-ABB9-C76644B037B2]-[2026-02-20-08-01-04].md`

**Video Entries**:
- Format: QuickTime Movie (.mov)
- Naming: `[UUID]-[YYYY-MM-DD-HH-mm-ss].mov`
- Metadata: Corresponding `.md` file with "Video Entry" text in `~/Documents/Freewrite/`
- Storage layout: `~/Documents/Freewrite/Videos/[UUID]-[YYYY-MM-DD-HH-mm-ss]/`
- Directory contents:
  - `[UUID]-[YYYY-MM-DD-HH-mm-ss].mov`
  - `thumbnail.jpg`
  - `transcript.md` (optional; speech transcript for that recording)
- Example directory: `~/Documents/Freewrite/Videos/[6910BBDE-75FC-415C-ABB9-C76644B037B2]-[2026-02-20-08-01-04]/`

## Key Components

### ContentView.swift

The main view containing all UI and business logic.

#### State Variables (Selection)

```swift
@State private var entries: [HumanEntry] = []           // All loaded entries
@State private var text: String = ""                    // Current text editor content
@State private var selectedEntryId: UUID? = nil         // Currently selected entry
@State private var showingVideoRecording = false        // Video recording overlay visibility
@State private var currentVideoURL: URL? = nil          // Video playback URL
@State private var showingSidebar = false               // History sidebar visibility
@State private var colorScheme: ColorScheme = .light    // Light/dark theme
@State private var fontSize: CGFloat = 18               // Text size (16-26px)
@State private var selectedFont: String = "Lato-Regular"// Current font
@State private var timerIsRunning = false               // Timer state
@State private var timeRemaining: Int = 900             // Timer (seconds)
@State private var backspaceDisabled = false            // Backspace lock
```

#### Core Functions

**Entry Management**:
- `loadExistingEntries()` - Loads all .md and .mov files from documents directory
- `createNewEntry()` - Creates new text entry
- `saveEntry(entry:)` - Saves text to .md file
- `loadEntry(entry:)` - Loads text or video for display
- `deleteEntry(entry:)` - Deletes entry and associated files
- `saveVideoEntry(from:)` - Saves recorded video and creates metadata

**Important**: When modifying the `entries` array from async contexts, wrap in `DispatchQueue.main.async` to prevent collection mutation crashes.

### VideoRecordingView.swift

Handles camera access and video recording.

#### CameraManager Class

```swift
class CameraManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var recordingTime: Int = 0
    @Published var permissionGranted = false

    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureMovieFileOutput?
    private var previewLayer: AVCaptureVideoPreviewLayer?
}
```

**Key Methods**:
- `setupCamera()` - Configures AVCaptureSession with video/audio inputs
- `startRecording(to:)` - Begins recording to temporary file
- `stopRecording()` - Stops recording and triggers completion handler
- `cleanup()` - Releases camera resources

**Critical**: Always use `beginConfiguration()` and `commitConfiguration()` when modifying AVCaptureSession to prevent crashes.
**UI Pattern**: The recorder is rendered as an immersive edge-to-edge overlay with a transparent bottom nav and a floating circular record control.

### VideoPlayerView.swift

Simple AVKit-based video player for playback.

```swift
struct VideoPlayerView: View {
    let videoURL: URL
    @State private var player: AVPlayer?
}
```

## UI Layout

### Main Interface

```
┌─────────────────────────────────────────────────────────┐
│                                                         │
│                    Text Editor Area                     │
│              (or Video Player if video)                 │
│                                                         │
├─────────────────────────────────────────────────────────┤
│  Bottom Nav Bar:                                        │
│  [16px] • [Lato] • [Arial] • [System] • [Serif] • ...  │
│  ... [15:00] • [🎥] • [Chat] • [Backspace] • [...]     │
└─────────────────────────────────────────────────────────┘
```

### Sidebar (History)

```
┌──────────────┐
│   History    │
├──────────────┤
│ 📹 Video...  │ ← Video entry with thumbnail
│ Feb 20       │
├──────────────┤
│ This is a... │ ← Text entry with preview
│ Feb 19       │
├──────────────┤
│ Another ...  │
│ Feb 18       │
└──────────────┘
```

## Navigation Bar Items

### Left Side (Font Controls)
- **Font Size**: Cycles through [16, 18, 20, 22, 24, 26]px
- **Font Selection**: Lato, Arial, System, Serif, Random
- Hover changes cursor to pointing hand
- **Video Mode Left Slot**: Replaced by `Copy Transcript` when viewing a video entry

### Right Side (Utilities)
- **Timer**: Shows time remaining, click to start/stop, double-click to reset
- **Video Camera (🎥)**: Opens immersive video recording overlay
- **Chat**: Opens AI chat menu (ChatGPT/Claude integration)
- **Backspace Toggle**: Enable/disable backspace key
- **Fullscreen**: Toggle fullscreen mode
- **New Entry**: Creates new text entry
- **Theme Toggle**: 🌙/☀️ for dark/light mode
- **History**: 🕐 Shows/hides sidebar

## Video Recording Flow

1. User clicks video camera icon (🎥)
2. Camera icon switches to a small spinner while preflight runs
3. App requests/validates **all required permissions**: camera + microphone + speech recognition
4. If any permission is missing, recorder is **not** presented; a compact popover above the camera icon explains what is missing and links to System Settings
5. Once camera session is fully ready (plus a short presentation delay), `VideoRecordingView` is rendered via `.overlay` on top of `ContentView` with animations disabled for open/close (plain swap, no transition)
6. Camera preview fills the entire window content area edge-to-edge
7. Transparent bottom nav appears over video with: `Close`, recording status, recording control text (`Start Recording` / `Stop Recording`), and timer
8. User clicks "Start Recording"
   - Recording begins to temp file
   - Timer starts counting up
   - Button changes to "Stop Recording"
9. User clicks "Stop Recording"
   - Recording stops
   - Speech transcript is finalized (spacing + sentence endings/capitalization)
   - `onRecordingComplete` closure called with temp URL + finalized transcript
10. `saveVideoEntry(from:transcript:)` called
   - Creates per-entry video directory in `~/Documents/Freewrite/Videos/[UUID]-[date]/`
   - Video copied from temp to `~/Documents/Freewrite/Videos/[UUID]-[date]/[UUID]-[date].mov`
   - Thumbnail generated once and saved to `~/Documents/Freewrite/Videos/[UUID]-[date]/thumbnail.jpg`
   - Transcript saved to `~/Documents/Freewrite/Videos/[UUID]-[date]/transcript.md` when available
   - Metadata file created: `[UUID]-[date].md` with "Video Entry"
   - Entry added to `entries` array (on main thread), selected immediately, and loaded into the main view
   - Playback starts automatically with audio enabled
   - Overlay dismissed
11. If user clicks `Close` while recording, the temp recording is discarded and no entry is created; recorder dismisses first, then camera cleanup runs on disappear

## Video Playback Flow

1. User clicks video entry in sidebar
2. `loadEntry(entry:)` checks `entry.entryType`
3. If `.video`:
   - Sets `currentVideoURL` to video file path
   - Clears `text`
4. Main view checks `if let videoURL = currentVideoURL`
5. Shows `VideoPlayerView(videoURL:)` instead of TextEditor
6. Video auto-plays muted with standard AVKit controls

## Entry Loading Logic

On app launch (`onAppear`):

1. `loadExistingEntries()` called
2. Reads all files from `~/Documents/Freewrite/`
3. Filters for canonical `.md` entries and derives expected `.mov` name from each `.md`
4. For each `.md` file:
   - Extracts UUID and date from filename via regex
   - Checks for corresponding `.mov` in this order:
     - `~/Documents/Freewrite/Videos/[entry-base]/[entry].mov` (current layout)
     - `~/Documents/Freewrite/Videos/[entry].mov` (legacy flat layout)
     - `~/Documents/Freewrite/[entry].mov` (oldest legacy layout)
   - Creates `HumanEntry` with appropriate type
5. Sorts entries by date (newest first)
6. Applies launch selection rules in order:
   - If newest entry is a video entry: create a new text entry and select it (never open directly into video on app launch)
   - Else if no entries: create welcome entry
   - Else if no empty entry exists for today (and app is not in the single-welcome-entry state): create a new empty entry
   - Else select the most recent empty entry from today (or the welcome entry if it's the only entry)

## Auto-Save Behavior

Text is auto-saved on every change:

```swift
.onChange(of: text) { _ in
    if let currentId = selectedEntryId,
       let currentEntry = entries.first(where: { $0.id == currentId }) {
        saveEntry(entry: currentEntry)
    }
}
```

## Permissions

Required entitlements in `freewrite.entitlements`:

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
<key>com.apple.security.device.camera</key>
<true/>
<key>com.apple.security.device.audio-input</key>
<true/>
<key>com.apple.security.personal-information.speech-recognition</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
```

Privacy usage descriptions (in Xcode project build settings):

```
INFOPLIST_KEY_NSCameraUsageDescription = "Dear Diary needs camera access to record video entries."
INFOPLIST_KEY_NSMicrophoneUsageDescription = "Dear Diary needs microphone access to record audio with your video entries."
INFOPLIST_KEY_NSSpeechRecognitionUsageDescription = "Dear Diary uses speech recognition to show live captions while recording."
```

## Technical Nuances & Implementation Details

### Threading Model

The app uses a **hybrid threading approach**:

1. **Main Thread**: All UI updates and `@State` mutations
2. **Global Queue**: File I/O operations (reading/writing markdown files)
3. **AVFoundation Queue**: Camera setup and video capture

**Critical Threading Issue**:
SwiftUI's `ForEach` creates an enumerator over the `entries` array. If you modify this array (insert, remove, replace) while the enumerator is active, you get `NSGenericException: Collection was mutated while being enumerated`.

**Solution Pattern**:
```swift
// When in async context (camera completion handler, DispatchQueue callback):
DispatchQueue.main.async {
    self.entries.insert(newEntry, at: 0)  // Safe
}

// When in loadExistingEntries:
let loadedEntries = mdFiles.compactMap { ... }  // Work on local copy
entries = loadedEntries  // Assign once to @State
// Now safe to check entries.contains, entries.first, etc.
```

### File System Architecture

**Why UUID + Timestamp Naming?**

The filename format `[UUID]-[YYYY-MM-DD-HH-mm-ss].md` serves multiple purposes:

1. **UUID**: Ensures global uniqueness even if multiple devices sync to same folder
2. **Timestamp**: Human-readable sorting in Finder without opening files
3. **Brackets**: Makes regex extraction reliable: `\\[(.*?)\\]` and `\\[(\\d{4}-\\d{2}-\\d{2}-\\d{2}-\\d{2}-\\d{2})\\]`

**File Loading Algorithm**:

```swift
// 1. Get all files
let fileURLs = try fileManager.contentsOfDirectory(at: documentsDirectory, ...)
let mdFiles = fileURLs.filter { $0.pathExtension == "md" }

// 2. Parse each .md file
let entriesWithDates = mdFiles.compactMap { fileURL -> (entry, date, content)? in
    // Extract UUID from filename using regex
    let uuidMatch = filename.range(of: "\\[(.*?)\\]", options: .regularExpression)
    let uuid = UUID(uuidString: String(filename[uuidMatch].dropFirst().dropLast()))

    // Extract timestamp
    let dateMatch = filename.range(of: "\\[(\\d{4}-\\d{2}-\\d{2}-\\d{2}-\\d{2}-\\d{2})\\]", ...)
    let dateString = String(filename[dateMatch].dropFirst().dropLast())

    // Parse date for sorting
    dateFormatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
    let fileDate = dateFormatter.date(from: dateString)

    // Check for corresponding video
    let videoFilename = filename.replacingOccurrences(of: ".md", with: ".mov")
    let hasVideo = hasVideoAsset(for: videoFilename) // checks current + legacy locations

    // Read content for preview
    let content = try String(contentsOf: fileURL, encoding: .utf8)
    let preview = content.replacingOccurrences(of: "\n", with: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
    let truncated = preview.isEmpty ? "" : String(preview.prefix(30)) + "..."

    return (entry: HumanEntry(...), date: fileDate, content: content)
}

// 3. Sort by actual date (not display date)
entries = entriesWithDates
    .sorted { $0.date > $1.date }  // Newest first
    .map { $0.entry }
```

**Why separate .md and .mov files instead of embedding?**

- User can open .md files in any text editor
- Video files can be played in QuickTime independently
- Easier to backup/sync text separately from large video files
- Transparent file format for user ownership
- Per-entry video directories keep each recording's media + thumbnail together

### Auto-Save State Machine

The app implements **continuous auto-save** with debouncing:

```swift
.onChange(of: text) { _ in
    if let currentId = selectedEntryId,
       let currentEntry = entries.first(where: { $0.id == currentId }) {
        saveEntry(entry: currentEntry)
    }
}
```

**State Transitions**:
1. User types character → `text` state updates
2. `.onChange` fires immediately
3. `saveEntry()` writes to disk synchronously (fast on SSD)
4. No loading spinner needed (happens in <10ms)

**Edge Case**: What if user switches entries before save completes?

```swift
Button(action: {
    if selectedEntryId != entry.id {
        // Save current entry BEFORE switching
        if let currentId = selectedEntryId,
           let currentEntry = entries.first(where: { $0.id == currentId }) {
            saveEntry(entry: currentEntry)
        }

        selectedEntryId = entry.id
        loadEntry(entry: entry)
    }
})
```

This ensures no data loss on rapid entry switching.

### Timer Implementation Details

The timer is **not a countdown** - it's a visual focus tool:

```swift
@State private var timeRemaining: Int = 900  // 15 minutes default
@State private var timerIsRunning = false

let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

.onReceive(timer) { _ in
    if timerIsRunning && timeRemaining > 0 {
        timeRemaining -= 1
    } else if timeRemaining == 0 {
        timerIsRunning = false
        // Show bottom nav again when timer expires
        bottomNavOpacity = 1.0
    }
}
```

**UI Behavior During Timer**:
- When timer starts: Bottom nav fades out after 1 second
- While running: Nav only appears on hover
- When timer ends: Nav fades back in

This creates **immersion** - the UI disappears, leaving only text and timer.

**Timer Adjustment**:
- Scroll wheel over timer: Adjust in 5-minute increments
- Click: Start/pause
- Double-click: Reset to 15 minutes

```swift
NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
    if isHoveringTimer {
        let scrollBuffer = event.deltaY * 0.25
        if abs(scrollBuffer) >= 0.1 {
            let currentMinutes = timeRemaining / 60
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, ...)
            let direction = -scrollBuffer > 0 ? 5 : -5
            let newMinutes = currentMinutes + direction
            let roundedMinutes = (newMinutes / 5) * 5
            timeRemaining = roundedMinutes * 60
        }
    }
    return event
}
```

### Backspace Disable Mechanism

**Implementation**:
```swift
@State private var backspaceDisabled = false

NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
    if backspaceDisabled && (event.keyCode == 51 || event.keyCode == 117) {
        return nil  // Swallow the event
    }
    return event
}
```

**macOS Key Codes**:
- 51: Delete/Backspace key
- 117: Forward delete (fn+delete)

**Why this matters**: Forces users to write without editing, embracing imperfection and maintaining flow state.

### Video Recording Architecture

**AVFoundation Setup Sequence**:

```swift
// 1. Create session
captureSession = AVCaptureSession()

// 2. Get devices
let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
let audioDevice = AVCaptureDevice.default(for: .audio)

// 3. Create inputs
let videoInput = try AVCaptureDeviceInput(device: videoDevice)
let audioInput = try AVCaptureDeviceInput(device: audioDevice)

// 4. CRITICAL: Begin configuration
captureSession?.beginConfiguration()

// 5. Configure session
captureSession?.sessionPreset = .high
captureSession?.addInput(videoInput)
captureSession?.addInput(audioInput)

// 6. Add output
videoOutput = AVCaptureMovieFileOutput()
captureSession?.addOutput(videoOutput!)
audioDataOutput = AVCaptureAudioDataOutput()
audioDataOutput?.setSampleBufferDelegate(self, queue: speechQueue)
captureSession?.addOutput(audioDataOutput!)

// 7. CRITICAL: Commit configuration
captureSession?.commitConfiguration()

// 8. Start running on background thread
DispatchQueue.global(qos: .userInitiated).async {
    self.captureSession?.startRunning()
}
```

**Startup/Teardown Safety Rule**:
- Trigger camera setup from a single lifecycle path (avoid duplicate `checkPermissions()` calls for the same view presentation).
- Call `startRunning()` only once per configured session startup path.
- Guard setup with a dedicated in-flight flag (e.g. `isSettingUpSession`) so repeated permission callbacks/onAppear events cannot run parallel setup work.
- Attach/bind `AVCaptureVideoPreviewLayer` only after `startRunning()` completes to avoid concurrent session mutations during startup.
- During teardown, prefer `stopRunning()` + releasing references over removing inputs/outputs while the session may still be transitioning states.

**Why `beginConfiguration()` / `commitConfiguration()`?**

AVCaptureSession maintains internal arrays of inputs/outputs. When you call `addInput()` or `addOutput()`, it mutates these arrays. If the session is actively running or if another thread is enumerating these arrays (for validation, etc.), you get collection mutation crash.

`beginConfiguration()` tells the session: "I'm about to make multiple changes, don't validate or enumerate until I'm done."

`commitConfiguration()` tells the session: "I'm done, now validate everything and update internal state."

**Recording Flow**:

```swift
// Start recording
videoOutput.startRecording(to: tempURL, recordingDelegate: self)

// Delegate callback when done
func fileOutput(_ output: AVCaptureFileOutput,
                didFinishRecordingTo outputFileURL: URL,
                from connections: [AVCaptureConnection],
                error: Error?) {
    DispatchQueue.main.async {
        self.onRecordingComplete?(outputFileURL)
    }
}
```

**Temporary File Strategy**:
- Record to temp directory: `FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")`
- On completion: Copy to permanent location
- Why? If recording fails, temp file is auto-cleaned by OS

### Speech Transcription (Speech Framework)

Speech transcription in `VideoRecordingView` is implemented with Apple's `Speech` framework and runs in the background during recording:

1. Request speech auth with `SFSpeechRecognizer.requestAuthorization`.
2. Keep camera/video recording on `AVCaptureMovieFileOutput`.
3. Add `AVCaptureAudioDataOutput` to the same capture session and stream sample buffers to speech recognition.
4. Feed sample buffers into `SFSpeechAudioBufferRecognitionRequest` (`appendAudioSampleBuffer`).
5. Build partial + committed transcript text while recording (no live caption overlay rendered).
6. Finalize transcript on stop and persist it as `transcript.md` in that entry's video directory.

Key details:
- Camera, microphone, and speech recognition permissions are all required before opening the recorder.
- If any permission is denied, the app keeps the user in the writing view and shows a compact camera-icon popover with the missing permission(s).
- Transcription is started on recording start and stopped on recording stop.
- Final transcript formatting is applied at stop to improve readability before saving/copying.
- Video playback nav exposes `Copy Transcript` for saved video entries with a transcript file.
- App sandbox requires `com.apple.security.personal-information.speech-recognition` entitlement plus `NSSpeechRecognitionUsageDescription`.

### Video Thumbnail Generation Nuances

```swift
func generateVideoThumbnail(from url: URL) -> NSImage? {
    let asset = AVAsset(url: url)
    let imageGenerator = AVAssetImageGenerator(asset: asset)
    imageGenerator.appliesPreferredTrackTransform = true  // CRITICAL

    let cgImage = try imageGenerator.copyCGImage(at: CMTime(seconds: 0, preferredTimescale: 1), ...)
    return NSImage(cgImage: cgImage, size: NSSize(...))
}
```

**`appliesPreferredTrackTransform = true`**:

Videos recorded on front-facing camera are often rotated 90°. The video file contains a transform matrix that says "rotate this video when playing." Without `appliesPreferredTrackTransform`, the thumbnail would be sideways.

**Performance Note**: Thumbnails are generated once when a recording is saved and persisted as `thumbnail.jpg` in each entry's video directory. Sidebar rows load precomputed image files instead of extracting frames from `.mov` during render. For older entries without thumbnails, the app lazily generates once and saves for subsequent loads.

### Text Editor Header Behavior

Every entry starts with `\n\n` (two newlines):

```swift
TextEditor(text: Binding(
    get: { text },
    set: { newValue in
        if !newValue.hasPrefix("\n\n") {
            text = "\n\n" + newValue.trimmingCharacters(in: .newlines)
        } else {
            text = newValue
        }
    }
))
```

**Why?** Creates visual breathing room at top of page. All entries look like they start mid-page, not cramped at the top edge.

### Entry Creation Logic

**Complex Decision Tree**:

```swift
if entries.isEmpty {
    // First time user → create welcome entry
    createNewEntry()
} else if !hasEmptyEntryToday && !hasOnlyWelcomeEntry {
    // No empty entry for today → create new entry
    createNewEntry()
} else {
    // Select most recent empty entry from today
    if let todayEntry = entries.first(where: { isFromTodayAndEmpty }) {
        selectedEntryId = todayEntry.id
        loadEntry(entry: todayEntry)
    } else if hasOnlyWelcomeEntry {
        // Only have welcome entry → select it
        selectedEntryId = entries[0].id
        loadEntry(entry: entries[0])
    }
}
```

**Date Comparison Complexity**:

Display dates are "MMM d" (e.g., "Feb 20") without year. To check "is this from today?":

```swift
let dateFormatter = DateFormatter()
dateFormatter.dateFormat = "MMM d"
if let entryDate = dateFormatter.date(from: entry.date) {
    // entryDate is now "Feb 20" in year 1 (default year)
    // Need to add current year to compare
    var components = calendar.dateComponents([.year, .month, .day], from: entryDate)
    components.year = calendar.component(.year, from: Date())

    if let entryDateWithYear = calendar.date(from: components) {
        let entryDayStart = calendar.startOfDay(for: entryDateWithYear)
        let todayStart = calendar.startOfDay(for: Date())
        return calendar.isDate(entryDayStart, inSameDayAs: todayStart)
    }
}
```

This handles edge cases like February 29th on non-leap years.

### Font System

**Available Fonts**:
```swift
let standardFonts = ["Lato-Regular", "Arial", ".AppleSystemUIFont", "Times New Roman"]
let availableFonts = NSFontManager.shared.availableFontFamilies
```

**Random Font Button**:
- Picks random font from `availableFonts` (excludes standardFonts)
- Shows current random font in button: "Random [FontName]"
- Clicking again picks new random font

**Font Rendering**:
```swift
.font(.custom(selectedFont, size: fontSize))
```

`.custom()` falls back to system font if font not found, so app is resilient to missing fonts.

### Line Spacing Calculation

```swift
var lineHeight: CGFloat {
    let font = NSFont(name: selectedFont, size: fontSize) ?? .systemFont(ofSize: fontSize)
    let defaultLineHeight = getLineHeight(font: font)
    return (fontSize * 1.5) - defaultLineHeight
}

func getLineHeight(font: NSFont) -> CGFloat {
    let layoutManager = NSLayoutManager()
    return layoutManager.defaultLineHeight(for: font)
}
```

**Formula**: Target line height is 1.5× font size. Subtract natural line height to get spacing to add.

Example: 18px font → target 27px line height → natural 21px → add 6px spacing

This creates **generous vertical rhythm** for readability during long writing sessions.

### Chat Integration

**Prompts**:
```swift
let aiChatPrompt = "You are a writing coach. Help me understand what I wrote below and ask me questions about it:\n\n"
let claudePrompt = "You are a thoughtful writing partner. Read what I wrote and help me explore the ideas further:\n\n"
```

**URL Encoding**:
```swift
let fullText = aiChatPrompt + "\n\n" + trimmedText
if let encodedText = fullText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
   let url = URL(string: "https://chat.openai.com/?prompt=" + encodedText) {
    NSWorkspace.shared.open(url)
}
```

**Length Handling**:
- URLs >6000 chars fail in some browsers
- If too long, shows "Copy Prompt" button instead
- Copies to clipboard for manual paste

### PDF Export Implementation

```swift
func exportEntryAsPDF(entry: HumanEntry) {
    let savePanel = NSSavePanel()
    savePanel.title = extractTitleFromContent(content, date: entry.date)
    savePanel.allowedContentTypes = [.pdf]

    if savePanel.runModal() == .OK {
        let pdfData = createPDF(from: content)
        try pdfData.write(to: savePanel.url!)
    }
}
```

**Title Extraction**:
- Takes first 4 words of content
- Removes punctuation
- Falls back to "Entry [date]" if content empty

### Theme System

```swift
@State private var colorScheme: ColorScheme = .light

// Apply to entire window
.preferredColorScheme(colorScheme)

// Persisted to UserDefaults
UserDefaults.standard.set(colorScheme == .light ? "light" : "dark", forKey: "colorScheme")
```

**Colors**:
- Light mode text: `Color(red: 0.20, green: 0.20, blue: 0.20)` (dark gray, not black, easier on eyes)
- Dark mode text: `Color(red: 0.9, green: 0.9, blue: 0.9)` (off-white, not pure white)

## Common Pitfalls

### Collection Mutation Crashes

**Problem**: Modifying `entries` array while SwiftUI is enumerating it.

**Solution**:
```swift
// BAD
entries.insert(newEntry, at: 0)

// GOOD (from async context)
DispatchQueue.main.async {
    self.entries.insert(newEntry, at: 0)
}
```

### AVCaptureSession Crashes

**Problem**: Session internals can crash with `Collection ... was mutated while being enumerated` when session startup/teardown overlaps (for example duplicate setup/start calls or mutating inputs/outputs during active transitions).

**Solution**:
```swift
captureSession?.beginConfiguration()
// Add/remove inputs and outputs here
captureSession?.sessionPreset = .high
captureSession?.addInput(videoInput)
captureSession?.commitConfiguration()
```

Also:
```swift
// Avoid duplicate startup paths for the same presentation
// and avoid repeated startRunning() calls on the same setup cycle.

if session.isRunning {
    session.stopRunning()
}
// Release session/output references without input/output removal churn.
```

### File Path Issues

Always use absolute paths:
```swift
let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("Freewrite")
let fileURL = documentsDirectory.appendingPathComponent(filename)
```

## Build Configuration

**Scheme**: freewrite
**Configuration**: Debug or Release
**Build Command**:
```bash
xcodebuild -project freewrite.xcodeproj -scheme freewrite -configuration Debug build
```

**Clean Build**:
```bash
xcodebuild -project freewrite.xcodeproj -scheme freewrite -configuration Debug clean build
```

## Testing Video Feature

1. Build and run app
2. Grant camera/microphone permissions when prompted
3. Click video camera icon in bottom nav
4. Click "Start Recording" (turns red)
5. Record for a few seconds
6. Click "Stop Recording"
7. Recorder overlay closes, new video entry is selected, and video opens immediately playing muted
8. Click video entry to play it

## Video Thumbnail Generation

```swift
func generateVideoThumbnail(from url: URL) -> NSImage? {
    let asset = AVAsset(url: url)
    let imageGenerator = AVAssetImageGenerator(asset: asset)
    imageGenerator.appliesPreferredTrackTransform = true

    let cgImage = try imageGenerator.copyCGImage(at: CMTime(seconds: 0, preferredTimescale: 1), actualTime: nil)
    return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
}
```

Generated at save time and stored in the per-entry video directory; sidebar loads this cached image file.

## Feature Flags / Settings

Stored in `UserDefaults`:
- `colorScheme`: "light" or "dark"

Other settings are session-only (not persisted):
- Font size, font family, timer duration, backspace state

## Future Development Notes

### Adding New Entry Types

1. Add case to `EntryType` enum
2. Update `HumanEntry` with relevant properties
3. Modify `loadExistingEntries()` to detect new file type
4. Update `loadEntry()` to handle new type
5. Add UI in main view for new entry type
6. Update `deleteEntry()` to clean up new file types

### Adding New Navigation Items

Add to bottom nav in ContentView.swift around line 500-950:

```swift
Text("•")
    .foregroundColor(.gray)

Button(action: {
    // Your action
}) {
    Image(systemName: "icon.name") // or Text("Label")
        .foregroundColor(isHovering ? textHoverColor : textColor)
}
.buttonStyle(.plain)
.onHover { hovering in
    isHovering = hovering
    isHoveringBottomNav = hovering
    if hovering {
        NSCursor.pointingHand.push()
    } else {
        NSCursor.pop()
    }
}
```

## Debugging

Enable console output in Xcode to see:
- File loading: "Processing: [filename]"
- Entry creation: "Successfully created video entry"
- Errors: "Error saving video entry: ..."

Check `~/Documents/Freewrite/` in Finder to verify files are being created.

## Code Organization

- **Lines 1-130**: Imports, models, state variables
- **Lines 130-430**: Computed properties and helpers
- **Lines 430-1200**: Main view body and UI
- **Lines 1200-1400**: Helper functions (save, load, delete, etc.)

## Key SwiftUI Patterns Used

- `@State` for local view state
- `@StateObject` for CameraManager
- `.overlay { if showingVideoRecording { ... } }` for immersive video recording
- `.onChange(of:)` for auto-save
- `.onAppear` for initialization
- `ForEach(entries)` with `Identifiable` for list rendering
- Conditional views: `if currentVideoURL != nil { VideoPlayerView } else { TextEditor }`

## Summary

Freewrite is a straightforward macOS writing app with video recording capabilities. All data is local, no backend required. The main complexity is in:

1. Proper file management and UUID-based naming
2. Thread-safe array mutations for entries
3. AVFoundation camera setup with proper configuration blocks
4. Conditional rendering between text and video content

When making changes, always:
- Test with actual video recording
- Check for collection mutation crashes
- Verify files are created in correct location
- Ensure privacy permissions are properly configured
