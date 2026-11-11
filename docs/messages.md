# Every message Dear Diary can show

This is the copy the fork added: error lines, empty states and confirmations. Each one is a single plain line, says what happened, and says what to do next when there is something to do. Edit the wording in the file named beside each group, then update this list.

freewrite's own wording (the bottom bar, the video recorder) is not listed here and was not changed. The welcome page a new journal opens on is Dear Diary's own since M10; its text is the file `freewrite/default.md`. Its last line is the one place the app credits freewrite. Earlier welcome pages are kept, unchanged, so journals that opened on them are still recognised: `freewrite/freewrite-welcome.md` (freewrite's guide) and `freewrite/dear-diary-welcome-1.md` (Dear Diary's first wording).

## When the AI cannot answer

Shown in the talk column (with a "Try again" word), under "Test connection" in Settings, and as the memory line in Settings and under the map. File: `freewrite/AI/LLMProvider.swift`.

Each line names the service in use. They are written here as they read with Claude; with another service "Claude" becomes "OpenAI", "Ollama" or "The AI service", and "Anthropic" becomes "OpenAI".

| When | Message |
| --- | --- |
| AI is switched off | AI is off. Turn it on in Settings to use this. |
| No key saved | No API key yet. Add one in Settings. |
| "Other" with no address | No address yet. Add one in Settings. |
| No model picked | No model chosen yet. Pick one in Settings. |
| The key is wrong | Claude didn't accept that API key. Check it and save it again. |
| The account has no credit | There's a billing problem on your Anthropic account. Check your credits there. |
| The key is not allowed | Your API key isn't allowed to do that. Check your Anthropic account. |
| The model name is wrong | That model name wasn't found, or your account can't use it. Check the model in Settings. |
| Too many requests | You've reached a usage limit for now. Try again in a little while. |
| Claude is overloaded | Claude is busy right now. Try again in a moment. |
| No internet | Couldn't reach Claude. Check your internet connection. |
| Ollama is not running | Couldn't reach Ollama. Open the Ollama app, then try again. |
| "Other" cannot be reached | Couldn't reach the AI service. Check the address in Settings and your connection. |
| A model was removed from Ollama | That model isn't on this Mac any more. Pick another in Settings. |
| A fault inside Ollama | Something went wrong in Ollama. Try again in a moment. |
| Claude declined | Claude declined to respond to this. |
| The reply stopped early | The reply was cut off before it finished. Try again. |
| Claude rejected the request | Claude couldn't accept that request. (Claude's own reason is added when it gives one.) |
| A fault at Anthropic | Something went wrong on Claude's side. Try again in a moment. |
| Anything else | Something unexpected went wrong. Try again. |

## Talk

Files: `freewrite/AI/Prompts.swift` (`talkDeclinedNotice`, `talkCareLine`), `freewrite/Talk/TalkController.swift`, `freewrite/Talk/TalkView.swift`.

| When | Message |
| --- | --- |
| Nothing said yet | The column is blank, with "Say what's on your mind" in the box. |
| What was written may mean danger (the app's own line, small, under a thin rule, saved in the conversation) | If you might hurt yourself, or you are in danger, please reach a person now: someone you trust, Tele-MANAS on 14416 (India), or your local emergency number. |
| Claude declined, even after a retry | Claude declined to respond to this. If you are in danger or thinking about harming yourself, please reach someone you trust, Tele-MANAS on 14416 (India), or your local emergency services. |
| The reply was empty | Claude answered with nothing. |

## Memory

Shown in Settings under "Memory is On", and under the map. File: `freewrite/Memory/MemoryEngine.swift`; the Settings lines are in `freewrite/Settings/SettingsView.swift`.

| When | Message |
| --- | --- |
| Nothing digested yet | Nothing in memory yet. |
| Working | Reading entry 2 of 9… |
| What memory holds | 14 thoughts from 9 entries. 1 entry waiting. |
| The memory folder cannot be written | Couldn't write to the memory folder. |
| The journal folder cannot be read | Couldn't read the journal folder. |
| The daily limit is reached | Today's limit of 40 memory requests has been reached. It carries on tomorrow. |
| After a tidy | Tidied on Monday 30 November 2026: merged 1, retired 2. |
| A tidy with nothing to do | Tidied on Monday 30 November 2026: nothing needed changing. |
| The tidy's answer was unusable | The last tidy couldn't be used, so nothing was changed. |
| Some entries were read before memory took the shape of a journal | Memory now keeps your own words in place of the AI's. Rebuild memory to bring earlier entries into the new shape. |
| Before a rebuild | This has the AI read 9 entries again and replaces what it has learned. Your fixes are kept. |
| Before forgetting | This deletes the memory folder, including your fixes, and turns memory off. Your entries are not touched. |

## The map

Files: `freewrite/Map/MapView.swift`, `freewrite/Map/MapDetailView.swift`.

| When | Message |
| --- | --- |
| Empty, no AI set up | Nothing in memory yet. Memory is built by an AI that reads each entry after you have finished with it. (Word: Set it up in Settings) |
| Empty, memory off | Nothing in memory yet. Turn memory on in Settings and thoughts will appear here as you write. (Word: Open Settings) |
| Empty, memory on | Nothing in memory yet. Thoughts appear here once an entry has settled, about ten minutes after you stop writing. |
| How much is on the map | 179 thoughts · 198 days |
| A thought held over another | Let go to link Running and Trouble sleeping |
| Find, before typing | A name |
| Find, with matches | 2 thoughts |
| Find, with none | No thought by that name |
| A day's panel | day · touched 4 thoughts; In your words; What it touched; Open this entry |
| A day that touched nothing lasting | day |
| The words before one of your lines | felt · told yourself · happened · wanted · helped · still open · done · not doing it |
| After a feeling | pleasant · unpleasant · mixed |
| The kinds, in the legend and on hover | Person · Topic · Feeling · What helped · Still open · Day (a memory from before M14 also shows Theme, Idea, Question, Decision, Event) |
| Picking a thought to merge into | Click the thought to fold this one into. |
| Before a merge | Fold “Arjun” into “Meera”? Its lines, links and names move over. This cannot be undone here. |
| Picking a thought to link to | Click the thought to link this one to. |
| Asking for a link's reason | How are “Running” and “Trouble sleeping” linked? |
| Before a delete | Delete “Running”? It is removed from memory and the AI will not bring it back. Your entries are not touched. |
| Before removing a link | Remove the link between “Meera” and “The pricing page”? The AI will not put it back. |
| A link made by hand | Linked by you. There is no quoted line behind this. |
| A link the app made | in the same sentence |
| Before marking something done | Mark this as done? It leaves the map. The line stays on its day, marked done. |
| Before dropping something | Not doing this after all? It leaves the map. The line stays on its day. |

### What the panel says by counting

Written by the app from fixed wording, never by a model. File: `freewrite/Memory/MemoryCounts.swift`. Keep "because", "always", "often" and "tends to" out of these; a test checks.

| When | Message |
| --- | --- |
| A person or topic, several days | In 4 entries, from Monday 2 November to Thursday 19 November 2026. |
| One day | In 1 entry, on Wednesday 4 November 2026. |
| Three or more of those days were read in your words | On 3 of those 4 days you also named an unpleasant feeling. |
| A feeling | Named on 2 days, both unpleasant. · Named on 3 days, all unpleasant. · Named on 3 days: 2 unpleasant, 1 pleasant. |
| Something that helped | You wrote that this helped on 1 day. |
| Something still open | Open since Sunday 8 November 2026. |
| The profile (given to Talk as background, and saved as `profile.md`) | Most written about in the last month: Meera (3 entries), the launch (2 entries). · Still open: 2 things, the oldest since Friday 6 November 2026. · They wrote that these helped: a run before work. |

## Versions

Files: `freewrite/Versions/VersionsView.swift`, `freewrite/Versions/SnapshotKeeper.swift`.

| When | Message |
| --- | --- |
| No versions of this entry | No earlier versions yet. A copy is kept every five minutes while an entry changes. |
| The chosen version matches the entry | This is how the entry reads now |
| The entry could not be kept before a restore | Couldn't keep the entry as it reads now, so nothing was restored. |
| Versions cannot be written (shown in Settings) | Couldn't save versions to the journal folder. |

## Settings

File: `freewrite/Settings/SettingsView.swift`.

| When | Message |
| --- | --- |
| The key could not be stored | Couldn't save the key to your Keychain. |
| The connection test came back empty | Claude answered with nothing. Try again. |
| A key is still needed | Add a key to use Talk and Memory. |
| "Other" still needs an address | Add an address to use Talk and Memory. |
| A model still has to be picked | Choose a model to use Talk and Memory. |
| Looking for Ollama | Looking for Ollama… |
| Ollama found | Ollama is running. 3 models found. |
| Ollama has no models | Ollama is running, but it has no models yet. Download one in the Ollama app, then check again. |
| In place of a model's name | Turn AI on first · Add a key first · Add an address first · Loading models… · Not available · No models found · Choose a model |
| "Other" has no model list | This service did not list its models, so type the model's name as the service writes it. |

What each service is, under "Runs on":

| Service | Line |
| --- | --- |
| On this Mac | A free open model that runs on this Mac through Ollama. Nothing you write leaves this Mac. |
| OpenAI | OpenAI, through your own API key. Entry text is sent to OpenAI when you talk or build memory. A ChatGPT plan does not include this. |
| Claude | Claude, through your own API key from Anthropic. Entry text is sent to Anthropic when you talk or build memory. |
| Other | Any service that speaks the OpenAI chat format, at an address you give. Entry text is sent to that address when you talk or build memory. |

## The page

Files: `freewrite/Page/OpeningLines.swift` (the opening lines) and `freewrite/ContentView.swift`, `freewrite/Page/BarIcon.swift` (the names of the marks).

The grey line on an empty page, one picked at random for each new entry:

- what's up, bbg
- how's the day, darling
- ok, tell me everything
- spill it
- hi you. what happened?
- what's the tea today
- so… how are we feeling
- go on, I'm all ears

The name shown when the pointer rests on a mark in the bar:

| Mark | Name |
| --- | --- |
| History | History |
| The number | Text size |
| Aa | Font: Lato (or Arial, System, Serif, or the surprise font's own name) |
| Camera | Record a video |
| Speech bubble | Talk, or Chat when AI is not set up |
| Joined dots | Memory |
| Backspace key | Backspace is On · Backspace is Off |
| Arrows | Fullscreen · Leave fullscreen |
| Pencil | New Entry |
| Moon or sun | Dark · Light |

## The lock

Files: `freewrite/Lock/LockScreen.swift` (the locked window), `freewrite/Lock/AppLock.swift` (the other lines) and `freewrite/Settings/SettingsView.swift` (the section).

| When | Message |
| --- | --- |
| On the locked window | for your eyes only |
| The word under it | Unlock |
| In the sheet macOS shows to open it | Dear Diary is trying to unlock your journal. |
| In the sheet macOS shows to turn the lock on | Dear Diary is trying to turn on the lock. |
| In the sheet macOS shows to turn the lock off | Dear Diary is trying to turn off the lock. |
| The check did not pass | Couldn't check that it's you. Try again. |
| This Mac has no password | The lock needs a password on this Mac. Set one in System Settings, then turn the lock on. |
| In Settings, under the switch | When the lock is on, Dear Diary opens locked and asks for Touch ID or your Mac password. It locks again when your Mac sleeps and when it has been in the background for a while. Turning it on or off asks once too. |
| In Settings, while the lock is on | Lock now · Lock after 5 minutes (each click: 15 minutes, 30 minutes, 1 minute, then 5 again) |
| In Settings, while the lock is on | The lock covers Dear Diary's windows. Your entries stay plain files in your journal folder, protected by your Mac's own login. |

## Bringing entries from freewrite

File: `freewrite/Settings/JournalImporter.swift` (the lines) and `freewrite/Settings/SettingsView.swift` (the section).

| When | Message |
| --- | --- |
| Always, under the word | If you used freewrite before, pick its folder and your entries are copied into Dear Diary. The originals are left where they are. |
| In the folder picker | Choose the folder freewrite keeps your entries in. It is usually called Freewrite. |
| Entries were found | Found 42 entries and 3 videos (310 MB). 2 are already here. |
| The words under it | Copy 40 entries · Cancel |
| Every entry found is here already | Found 2 entries. All of them are already here. (For one: Found 1 entry. It is already here.) |
| The folder holds no entries | No freewrite entries in that folder. The folder is usually called Freewrite. |
| While copying | Copying 12 of 40… (with the word Stop) |
| Copied | Copied 40 entries. They are in History now. (For one: Copied 1 entry. It is in History now.) |
| Stopped part-way | Copied 12 of 40 entries. They are in History now. |
| Some could not be copied | Copied 38 of 40 entries. They are in History now. 2 could not be copied. |
| None could be copied | Couldn't copy the entries. Nothing was changed. |
| Under "Copied" | The AI has not read them. To include them in memory, use Rebuild memory above; it shows the count first. |
