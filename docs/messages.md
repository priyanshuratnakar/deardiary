# Every message Dear Diary can show

This is the copy the fork added: error lines, empty states and confirmations. Each one is a single plain line, says what happened, and says what to do next when there is something to do. Edit the wording in the file named beside each group, then update this list.

freewrite's own wording (the bottom bar, the welcome guide, the video recorder) is not listed here and was not changed.

## When Claude cannot answer

Shown in the talk column (with a "Try again" word), under "Test connection" in Settings, and as the memory line in Settings and under the map. File: `freewrite/AI/LLMProvider.swift`.

| When | Message |
| --- | --- |
| AI is switched off | AI is off. Turn it on in Settings to use this. |
| No key saved | No API key yet. Add one in Settings. |
| The key is wrong | Claude didn't accept that API key. Check it and save it again. |
| The account has no credit | There's a billing problem on your Anthropic account. Check your credits there. |
| The key is not allowed | Your API key isn't allowed to do that. Check your Anthropic account. |
| The model name is wrong | That model name wasn't found, or your account can't use it. Check the model in Settings. |
| Too many requests | You've reached a usage limit for now. Try again in a little while. |
| Claude is overloaded | Claude is busy right now. Try again in a moment. |
| No internet | Couldn't reach Claude. Check your internet connection. |
| Claude declined | Claude declined to respond to this. |
| The reply stopped early | The reply was cut off before it finished. Try again. |
| Claude rejected the request | Claude couldn't accept that request. (Claude's own reason is added when it gives one.) |
| A fault at Anthropic | Something went wrong on Claude's side. Try again in a moment. |
| Anything else | Something unexpected went wrong. Try again. |

## Talk

Files: `freewrite/AI/Prompts.swift` (`talkDeclinedNotice`), `freewrite/Talk/TalkController.swift`, `freewrite/Talk/TalkView.swift`.

| When | Message |
| --- | --- |
| Nothing said yet | The column is blank, with "Say what's on your mind" in the box. |
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
| After a tidy | Tidied on Monday 30 November 2026: merged 1, retired 2, 1 pattern across weeks. |
| A tidy with nothing to do | Tidied on Monday 30 November 2026: nothing needed changing. |
| The tidy's answer was unusable | The last tidy couldn't be used, so nothing was changed. |
| Before a rebuild | This sends 9 entries to Claude and replaces what it has learned. Your fixes are kept. |
| Before forgetting | This deletes the memory folder, including your fixes, and turns memory off. Your entries are not touched. |

## The map

Files: `freewrite/Map/MapView.swift`, `freewrite/Map/MapDetailView.swift`.

| When | Message |
| --- | --- |
| Empty, memory on | Nothing in memory yet. Thoughts appear here once an entry has settled, about ten minutes after you stop writing. |
| Empty, memory off | Nothing in memory yet. Turn memory on in Settings and thoughts will appear here as you write. |
| Picking a thought to merge into | Click the thought to fold this one into. |
| Before a merge | Fold “Arjun” into “Meera”? Its lines, links and names move over. This cannot be undone here. |
| Picking a thought to link to | Click the thought to link this one to. |
| Asking for a link's reason | How are “Running” and “Trouble sleeping” linked? |
| Before a delete | Delete “Running”? It is removed from memory and the AI will not bring it back. Your entries are not touched. |
| Before removing a link | Remove the link between “Meera” and “The pricing page”? The AI will not put it back. |
| A link made by hand | Linked by you. There is no quoted line behind this. |

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
