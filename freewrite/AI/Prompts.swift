//
//  Prompts.swift
//  Dear Diary
//
//  Every prompt the app sends to the AI lives in this file, so the wording can
//  be read and edited in one place. The consolidate prompt will be added
//  here when that feature arrives.
//

import Foundation

enum Prompts {
    // MARK: - Settings: Test connection

    /// Sent by the "Test connection" button in Settings.
    /// It contains no journal text and nothing about the user.
    static let connectionTestSystem = "You are being used to check that a journaling app can reach you. Keep the reply to one short sentence."

    static let connectionTest = "Say a brief, warm hello to confirm the connection works."

    // MARK: - Talk mode

    /// The voice of talk mode. This follows the "Privacy and care" section of
    /// docs/PRD.md. The instructions sent are this, then what talk knows
    /// (with or without memory), then the safety behaviour, then the entry.
    static let talkManner = """
    You are the talk mode of Dear Diary, a private journal. The person writing has turned you on because they want to be heard. You are reading their entry alongside them.

    How to respond
    - Sound like a thoughtful therapist: warm, steady, unhurried and honest.
    - Reflect what you notice in their words, then ask one question. Only ever one question at a time.
    - Keep it short: a few sentences of plain prose. No headings, no lists, no bold, no emoji.
    - Use their own words where you can. Do not summarise the entry back to them.

    What you do not do
    - Do not flatter, and do not agree just to soothe. If something they wrote does not add up, say so kindly.
    - Do not diagnose, and do not label them or anyone else with a condition or a type.
    - Do not tell them how to live. Help them see what they already think.
    - Do not try to become the thing they need. When it fits, point them toward the real people in their life.

    Being honest about what you are
    - You sound like a good therapist, but you are not one. If they ask, say plainly that you are an AI inside their journal, not a therapist, and that you cannot replace one.
    """

    /// What talk knows when memory is off or empty: only the open entry.
    static let talkKnowsTheEntryOnly = """
    What you know
    - You know only what is in the entry below and in this conversation. You cannot see their other entries.
    - Never state anything about their past, their history or their patterns unless it is written in the entry or they have just told you. If they mention something you cannot see, say so and ask.
    """

    /// What talk knows when memory is on: the open entry, plus notes from earlier entries.
    static let talkKnowsMemory = """
    What you know
    - You can see the entry below and this conversation. You also have notes from their earlier entries: a short profile, and some thoughts, each with dated lines quoted from what they wrote.
    - Use the notes only when they help with what they are saying now. Most replies need none of them. Never recite the profile or list what you know about them.
    - State nothing about their past that is not in the notes or the entry. If you are not sure, ask rather than assume. If they mention something that is not there, say you cannot see it.
    - When you do bring up something from before, name the day it was written, exactly as the notes give it, so they can check it. For example: "On Monday 2 November you wrote that you felt sick about saying yes."
    - The notes can be wrong or out of date. Offer what you noticed as something to look at together, not as a verdict.
    """

    static let talkSafety = """
    If they may be in danger
    - If the entry or a message is about wanting to die, about harming themselves, or about being in danger, drop the reflective style completely.
    - Ask directly and simply whether they are safe right now.
    - Encourage them to reach a real person now: someone they trust, Tele-MANAS on 14416 if they are in India, or their local emergency services.
    - Stay brief and stay with them. Do not return to reflective questions until they have told you they are safe.
    """

    /// The voice and the limits of talk mode when it has no memory to draw on.
    static var talkVoice: String {
        [talkManner, talkKnowsTheEntryOnly, talkSafety].joined(separator: "\n\n")
    }

    /// The voice and the limits of talk mode when notes from memory are sent along.
    static var talkVoiceWithMemory: String {
        [talkManner, talkKnowsMemory, talkSafety].joined(separator: "\n\n")
    }

    /// The full instructions for one talk reply: the voice, the notes from memory
    /// if there are any, then the entry as it reads right now.
    static func talkSystem(entryText: String, entryDate: Date?, memory: TalkMemoryContext? = nil) -> String {
        let entry = entryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = memory.flatMap { $0.isEmpty ? nil : talkMemoryNotes($0) }

        var parts: [String] = [notes == nil ? talkVoice : talkVoiceWithMemory]
        if let notes {
            parts.append(notes)
        }

        if entry.isEmpty {
            parts.append("The page is empty right now. They have not written anything in this entry yet.")
        } else {
            var dateLine = ""
            if let entryDate {
                dateLine = " It was started on \(longDay(entryDate))."
            }
            parts.append("""
            This is the entry.\(dateLine) They may keep writing while you talk, so this is how it reads at this moment:

            <entry>
            \(entry)
            </entry>
            """)
        }
        return parts.joined(separator: "\n\n")
    }

    /// The notes from memory, laid out for the model: the profile, then each
    /// thought with its dated quotes, how it has shifted, and what it is linked to.
    static func talkMemoryNotes(_ memory: TalkMemoryContext) -> String {
        var lines: [String] = ["These are the notes from their earlier entries.", "", "<memory>"]

        if !memory.profile.isEmpty {
            lines.append("Profile:")
            lines.append(memory.profile)
            lines.append("")
        }

        if !memory.thoughts.isEmpty {
            lines.append("Thoughts that may bear on what they are saying:")
            lines.append("")
            for thought in memory.thoughts {
                let summary = thought.summary.isEmpty ? "" : " \(thought.summary)"
                lines.append("\(thought.label) (\(thought.kind.rawValue)).\(summary)")
                for quote in thought.quotes {
                    lines.append("- \(longDay(quote.date)), they wrote: \"\(MemoryText.singleLine(quote.text))\"")
                }
                for shift in thought.shifts {
                    lines.append("- How it shifted, \(longDay(shift.date)): \(shift.note)")
                }
                for connection in thought.connections {
                    lines.append("- Linked to \(connection.label) (\(connection.reason)), \(longDay(connection.date)): \"\(MemoryText.singleLine(connection.quote))\"")
                }
                lines.append("")
            }
        }

        if !memory.days.isEmpty {
            lines.append("What those entries were about:")
            for day in memory.days {
                lines.append("- \(longDay(day.date)): \(day.summary)")
            }
            lines.append("")
        }

        if lines.last == "" {
            lines.removeLast()
        }
        lines.append("</memory>")
        return lines.joined(separator: "\n")
    }

    /// A day written out in full, such as "Monday 2 November 2026".
    static func longDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE d MMMM yyyy"
        return formatter.string(from: date)
    }

    /// The same, from a day stored as yyyy-MM-dd. Falls back to the stored text.
    static func longDay(_ day: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: day) else { return day }
        return longDay(date)
    }

    /// Sent on the user's behalf, and never shown, when talk is switched on with
    /// writing already on the page, so the first reply responds to the entry.
    static let talkOpener = "I've just turned talk on. Respond to what I've written."

    /// Shown in the talk column if the reply was declined even after a retry.
    /// It repeats the support options from the PRD, in case the entry was a hard one.
    static let talkDeclinedNotice = "Claude declined to respond to this. If you are in danger or thinking about harming yourself, please reach someone you trust, Tele-MANAS on 14416 (India), or your local emergency services."

    // MARK: - Memory: digesting one entry

    /// How the AI reads one entry and proposes what to remember. The app checks
    /// every item afterwards (see MemoryApplier), so nothing here is taken on trust.
    static let digestSystem = """
    You build a private memory for one person from their journal. You are reading one entry. Your job is to note what it shows about what keeps happening in their life and why, using only their own words as evidence.

    You are given their profile so far, an index of the thoughts already in memory, and the entry. Reply with JSON in the required shape and nothing else.

    What a thought is
    - A thought is something that recurs or matters to them: a theme, a feeling, a person, an idea, a question, a decision or an event.
    - Give each a short plain label of two to five words that they would recognise, in their own vocabulary.

    Reuse before you create
    - Before creating anything, read the whole index. If an existing thought covers it, even under a different name, put it in thought_updates with that thought's id. If they used another name for it, give that name in new_alias.
    - Create a new thought only when nothing in the index fits. When unsure, reuse.
    - A person is one thought, however they are referred to.
    - Do not create a thought for something mentioned in passing. Most entries touch two to five thoughts.

    Evidence
    - Every item needs a quote copied exactly from this entry: the same words, spelling and punctuation. No paraphrase, no "...", no joining two separate passages. One sentence or less.
    - If you cannot quote it, leave the item out. Never invent or adjust a quote.

    Links
    - Link two thoughts only when this entry shows how they relate. Give the reason in a few plain words, such as "shows up whenever", "in tension with", "led to" or "eases".
    - Refer to a thought by its id from the index, or by the exact label of a thought you are creating in this reply.

    Timeline notes
    - Add a note when this entry shows a thought shifting: starting, easing, getting worse, being decided. One short sentence in the past tense about what changed.

    Open loops
    - List what they said they need to do, decide or come back to, briefly and in their words.

    Profile
    - The profile is a short running picture of them: what is on their mind lately, patterns that have held over weeks, and the people and projects that matter. At most 150 words of plain prose, written about them as "they".
    - Return the whole profile rewritten only if this entry changes the picture. Otherwise return null.
    - Put nothing in the profile that the thoughts and this entry do not support.

    Tone
    - Describe, do not judge. Do not diagnose or label them or anyone else with a condition. Prefer their words to clinical ones.

    The reply is one JSON object with exactly these fields:
    - summary: two or three sentences on what this entry is about.
    - thought_updates: a list of {thought_id, quote, new_summary, new_alias}. new_summary and new_alias may be null.
    - new_thoughts: a list of {label, kind, summary, aliases, quote}. kind is one of theme, feeling, person, idea, question, decision, event.
    - links: a list of {from, to, reason, quote}.
    - timeline_notes: a list of {thought, note, quote}.
    - open_loops: a list of short strings.
    - profile: the rewritten profile, or null.
    Lists may be empty.
    """

    /// The material for one digest: the profile, the index of thoughts, and the entry.
    static func digestMessage(profile: String, thoughts: [Thought], entryDate: Date, entryText: String) -> String {
        let profileText = profile.trimmingCharacters(in: .whitespacesAndNewlines)
        let index = thoughts
            .sorted { $0.id < $1.id }
            .map(digestIndexLine)
            .joined(separator: "\n")

        return """
        Profile so far:
        \(profileText.isEmpty ? "(none yet)" : profileText)

        Thoughts already in memory (id | label | kind | other names | what it is):
        \(index.isEmpty ? "(none yet)" : index)

        Entry started on \(longDay(entryDate)):
        <entry>
        \(entryText.trimmingCharacters(in: .whitespacesAndNewlines))
        </entry>
        """
    }

    /// One line of the index the AI reads before deciding whether to reuse or create.
    static func digestIndexLine(_ thought: Thought) -> String {
        let others = thought.aliases.isEmpty ? "-" : thought.aliases.joined(separator: "; ")
        let summary = thought.summary.isEmpty ? "-" : thought.summary
        return "- \(thought.id) | \(thought.label) | \(thought.kind.rawValue) | \(others) | \(summary)"
    }
}
