//
//  Prompts.swift
//  Dear Diary
//
//  Every prompt the app sends to the AI lives in this file, so the wording can
//  be read and edited in one place.
//

import Foundation

enum Prompts {
    // MARK: - Settings: Test connection

    /// Sent by the "Test connection" button in Settings.
    /// It contains no journal text and nothing about the user.
    static let connectionTestSystem = "You are being used to check that a journaling app can reach you. Keep the reply to one short sentence."

    static let connectionTest = "Say a brief, warm hello to confirm the connection works."

    // MARK: - Talk mode

    /// The voice of talk mode, and what a good reply does.
    ///
    /// Rewritten on 12 Nov 2026 (see docs/research/ai-layer.md). The first version asked
    /// for "a thoughtful therapist" who reflects and then asks a question, every turn, and
    /// that is the reply people find generic. This one asks for a close friend who read
    /// every word, gives it a few things a reply can do, and shows examples, because models
    /// follow examples more closely than rules. The examples are about other people on
    /// purpose, so nothing in them is mistaken for the writer's own entry.
    ///
    /// The instructions sent are this, then what talk knows (the entry only, or lines from
    /// earlier entries), then the safety behaviour, then the entry, then a note for this
    /// one reply if the app has something to add.
    static let talkManner = """
    You are the talk mode of Dear Diary, a private journal on this person's Mac. They have just written the entry below and opened this column to think it through with you. You are not a therapist and you do not sound like one. You sound like a close friend who read every word: warm, plain-spoken and honest.

    What a good reply does
    - It shows you read this entry and no other. Use their own words, in double quote marks, at least once.
    - Then it does one of these things, whichever fits best. Never name which one you chose.
      - Sets two things they wrote side by side that pull against each other.
      - Points at one word or detail they chose and asks about it.
      - Names what changed, in the entry or since their last message.
      - Asks what they would say to a friend who had written this.
      - Says the hardest part back in plain words and leaves it there, with no question.
      - Asks one question that only this entry could prompt.
    - Match the weight of what they wrote. When it is about loss, shame or fear, slow down: say the hard part back gently first, and do not be clever. When it is a good day, be glad with them and be curious about it.

    Rules
    - Two to four sentences of plain prose. No lists, no headings, no labels, no bold, no emoji.
    - At most one question in a reply.
    - A question must not lean. Do not assume which way they will choose or what they feel. Ask about moments, people and things, never about abstractions such as "the gap" or "the tension".
    - Never begin with "It sounds like", "It seems", "I hear", "I understand", "I notice", "I'm here" or "That must be". Never say "tell me more". Never praise them for writing or sharing.
    - Do not summarise the entry. Do not give advice unless they ask. If they ask what they should do or say, do not decide for them: start from words they already wrote, say plainly what you see there, and leave the choice with them.
    - Do not agree just to be kind, and do not flatter. If two things they wrote do not fit together, say so.
    - You only have their side. Do not judge the people they mention. If they judge someone, do not join in and do not argue: turn to what it is like for them.
    - Do not diagnose or label them or anyone else. You do not know medicine or law: if they ask a medical question, say you cannot know that, and point to the doctor or person they already mentioned.
    - Do not try to become the thing they need. When it fits, point them toward the real people in their life.
    - If they ask what you are, or whether you are a therapist, say plainly that you are an AI inside their journal, not a therapist, and that you cannot replace one. Otherwise do not talk about yourself.
    - If they say they do not know, or ask what you think, do not push. Offer one thing you see in their words, as a guess they are free to correct.
    - If they say thanks, or that they are done, answer with one warm plain sentence and no question.
    - If they write in a mix of languages, reply in plain English and quote their words as they wrote them.

    Examples (other people, other entries)

    Entry: "Got the promotion. Called Dad, he said 'about time'. Went to the gym and stayed till close."
    Reply: You got the promotion, and the line you gave the most room to is your dad's "about time". What were you hoping he would say?

    Entry: "I told Priya I'm fine with her moving out. I am fine. I've been cleaning the flat since six."
    Reply: "I am fine" comes right before "cleaning the flat since six". Those two don't sit easily together.

    Entry: "Skipped the reunion again. Third year. Told myself it's the travel."
    Them: i guess i just don't want to see them
    Reply: A minute ago it was "the travel". Now it's "I just don't want to see them". That is a more honest sentence than the first one.

    Entry: "Papa's birthday today. He would have been 61. I bought the mithai he liked and then didn't know who to give it to."
    Reply: You bought "the mithai he liked", and then there was nobody to hand it to. That is a hard place to be standing.

    Entry: "Shreya got engaged. I said congratulations with three exclamation marks. I've been on her profile for an hour."
    Them: she always does this, makes everything about her
    Reply: Maybe so, I only know her from this page. What I can see is "three exclamation marks" and then an hour on her profile. What did you actually want to type?

    Entry: "Didn't go to the gym again. Paid for the year in January."
    Them: ok that helps. night
    Reply: Good night. "Paid for the year in January" will still be there tomorrow if you want it.
    """

    /// What talk knows when memory is off or empty: only the open entry.
    static let talkKnowsTheEntryOnly = """
    What you know
    - You know only what is in the entry below and in this conversation. You cannot see their other entries.
    - Never state anything about their past, their history or their patterns unless it is written in the entry or they have just told you. If they mention something you cannot see, say so and ask.
    """

    /// What talk knows when memory is on: the open entry, plus numbered lines from earlier entries.
    ///
    /// The model points at a line by its number and the app writes the line out, with its
    /// day, word for word (see TalkReply). When the model was asked to quote earlier lines
    /// itself it changed a few words of one, and a diary must not misquote its writer.
    static let talkKnowsMemory = """
    Lines from earlier entries
    - Below you are given numbered lines they wrote on earlier days, each with its day and what it was about. You may also be given a short profile: it is background, never recite it.
    - In your first reply, look for a line that is about the same thing as today's entry. If there is one, use it to show that something has changed, or that it has come round again.
    - To use a line, write its number in curly brackets where the line should go, like {2}. The journal puts the day and their exact words there. Never type out an earlier line yourself, and never state the day yourself.
    - For example: {2} Today it's "I asked him". What happened in between?
    - Use one line at most in a reply, and most replies need none. Never list what you know about them.
    - State nothing about their past that is not in these lines or the entry. If you are not sure, ask rather than assume. The lines can be out of date: offer what you see as something to look at together, not as a verdict.
    """

    /// What talk does when someone may be in danger. The app has its own net under this
    /// (see CareNet): it shows `talkCareLine` itself, so the help numbers never depend on
    /// what a model chooses to say.
    static let talkSafety = """
    If they may be in danger
    - If the entry or a message is about wanting to die, about ending things, about harming themselves, about not being around any more, or about being in danger, drop everything above.
    - Start your reply with [care] on a line of its own.
    - Then ask directly and simply whether they are safe right now, and say you are glad they wrote it down. Two short sentences and nothing else. The journal itself shows where to reach help, so do not list numbers yourself.
    - Stay with them. Do not go back to anything above until they have told you they are safe.
    - Ordinary figures of speech are not danger: "this deadline is killing me", "I could have died of embarrassment".
    """

    /// Added for one reply when the last reply ended with a question. The app, not the
    /// model, keeps two questions from coming in a row: the rule alone was not followed.
    static let talkNoQuestionNote = """
    For this reply only
    - Your last reply ended with a question and they have answered it. Do not ask another question now.
    - If they only said thanks, goodbye, or that they are fine, take them at their word and answer with one warm sentence.
    - Otherwise say back the most important thing in what they just told you, in plain words, using a phrase of theirs. You may add one thing you see in their words, but not a reason, a motive or a feeling they did not write. Then stop.
    - If what they said is a verdict on someone else, do not repeat it as a fact and do not praise or blame them for it. Stay with what it has been like for them.
    """

    /// Added for one reply when the app's own net has caught words that may mean danger.
    static let talkDangerNote = """
    For this reply only
    - What they wrote may mean they are in danger. Follow "If they may be in danger" now, whatever else is above.
    """

    /// The app's own line, shown in the column when someone may be in danger. It is always
    /// these words: nothing here is written by a model. It follows the PRD's "Privacy and care".
    static let talkCareLine = "If you might hurt yourself, or you are in danger, please reach a person now: someone you trust, Tele-MANAS on 14416 (India), or your local emergency number."

    /// The voice and the limits of talk mode when it has no memory to draw on.
    static var talkVoice: String {
        [talkManner, talkKnowsTheEntryOnly, talkSafety].joined(separator: "\n\n")
    }

    /// The voice and the limits of talk mode when lines from memory are sent along.
    static var talkVoiceWithMemory: String {
        [talkManner, talkKnowsMemory, talkSafety].joined(separator: "\n\n")
    }

    /// What the app adds for one reply.
    enum TalkTurn: Equatable {
        case ordinary
        /// The last reply ended with a question, so this one may not ask another.
        case noQuestion
        /// The app's net caught words that may mean danger.
        case danger
    }

    /// The full instructions for one talk reply: the voice, the lines from memory if there
    /// are any, the entry as it reads right now, then the note for this reply if any.
    static func talkSystem(entryText: String, entryDate: Date?, memory: TalkMemoryContext? = nil, turn: TalkTurn = .ordinary) -> String {
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

        switch turn {
        case .ordinary: break
        case .noQuestion: parts.append(talkNoQuestionNote)
        case .danger: parts.append(talkDangerNote)
        }
        return parts.joined(separator: "\n\n")
    }

    /// The most lines from earlier entries that are offered for one reply. A small model
    /// loses its way among many.
    static let earlierLineLimit = 12

    /// The lines from earlier entries that a reply may point at, numbered from 1. The same
    /// list is used to lay them out for the model and to write a line out when it is used.
    ///
    /// Every thought's most recent line is taken first, then each one's next most recent,
    /// until the limit, so no thought crowds out the others. They are then listed thought
    /// by thought, oldest line first.
    static func earlierLines(from memory: TalkMemoryContext?) -> [EarlierLine] {
        guard let memory else { return [] }

        var chosen: [(thought: Int, quote: Int)] = []
        var seen = Set<String>()
        let deepest = memory.thoughts.map(\.quotes.count).max() ?? 0
        choosing: for stepsBack in 0..<deepest {
            for (thoughtIndex, thought) in memory.thoughts.enumerated() {
                let quoteIndex = thought.quotes.count - 1 - stepsBack
                guard quoteIndex >= 0 else { continue }
                let quote = thought.quotes[quoteIndex]
                let text = MemoryText.singleLine(quote.text)
                // The same line can sit under two thoughts. It is offered once.
                guard !text.isEmpty, seen.insert(quote.date + "\n" + text).inserted else { continue }
                chosen.append((thoughtIndex, quoteIndex))
                if chosen.count == earlierLineLimit { break choosing }
            }
        }

        return chosen
            .sorted { ($0.thought, $0.quote) < ($1.thought, $1.quote) }
            .enumerated()
            .map { number, place in
                let thought = memory.thoughts[place.thought]
                let quote = thought.quotes[place.quote]
                return EarlierLine(
                    number: number + 1,
                    date: quote.date,
                    label: thought.label,
                    quote: MemoryText.singleLine(quote.text)
                )
            }
    }

    /// The notes from memory, laid out for the model: the profile, then the numbered lines.
    static func talkMemoryNotes(_ memory: TalkMemoryContext) -> String {
        var lines: [String] = ["These are lines from their earlier entries.", "", "<earlier>"]

        if !memory.profile.isEmpty {
            lines.append("Profile (background only):")
            lines.append(memory.profile)
            lines.append("")
        }

        for line in earlierLines(from: memory) {
            lines.append("{\(line.number)} \(longDay(line.date)), about \(line.label): \"\(line.quote)\"")
        }

        if lines.last == "" {
            lines.removeLast()
        }
        lines.append("</earlier>")
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
    static let talkDeclinedNotice = talkDeclined(by: .claude)

    /// The same notice, naming whichever service declined.
    static func talkDeclined(by kind: AIProviderKind) -> String {
        "\(kind.serviceName) declined to respond to this. If you are in danger or thinking about harming yourself, please reach someone you trust, Tele-MANAS on 14416 (India), or your local emergency services."
    }

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

    // MARK: - Memory: the weekly tidy

    /// How the AI looks across all of memory, about once a week. The app checks
    /// every proposal afterwards (see MemoryTidier), so nothing here is taken on trust.
    static let tidySystem = """
    You look after a private memory built from one person's journal. Their entries were read one at a time. Your job is the weekly tidy: looking across all of it for what a single entry could not show.

    You are given the profile, every thought in memory with some of its quoted lines (each with the id and the day of the entry it came from), the links between thoughts, and summaries of recent entries. Reply with JSON in the required shape and nothing else.

    Merge duplicates
    - If two thoughts are clearly the same thing under different names, fold the less established one into the other, using their ids.
    - Merge only when you are sure. Two things that often appear together are not the same thing. When unsure, leave them apart.
    - Never merge two different people.

    Retire one-offs
    - List the ids of thoughts that came up in a single entry some weeks ago, never returned, and are not connected to anything that matters now. The app decides whether each one really qualifies.

    Patterns across weeks
    - Look for what recurs across several entries, or for one thing that reliably goes with another.
    - A pattern that deserves its own thought goes in patterns, with a short plain label of two to five words and one or two sentences on what it is. If a thought for it already exists, do not create another.
    - A relationship between two thoughts goes in links, with the reason in a few plain words, such as "shows up whenever", "in tension with", "led to" or "eases".
    - Every pattern and every link needs quoted lines from at least two different entries. Copy each quote exactly as it is given to you, together with the id of the entry it came from. Do not write new quotes and do not change a word.
    - Prefer a few solid observations to many thin ones. Finding none is fine.

    Profile
    - Rewrite the profile if it no longer matches memory: what is on their mind lately, patterns that have held over weeks, and the people and projects that matter. At most 150 words of plain prose, written about them as "they". Otherwise return null.
    - Put nothing in the profile that the thoughts do not support.

    Tone
    - Describe, do not judge. Do not diagnose or label them or anyone else with a condition. Prefer their words to clinical ones.

    The reply is one JSON object with exactly these fields:
    - merges: a list of {from, into}.
    - retire: a list of thought ids.
    - patterns: a list of {label, kind, summary, evidence}. evidence is a list of {entry_id, quote}. kind is one of theme, feeling, person, idea, question, decision, event.
    - links: a list of {from, to, reason, evidence}, with evidence as above.
    - profile: the rewritten profile, or null.
    Lists may be empty.
    """

    /// The material for one tidy: the profile, every thought with its recent quotes and links, and recent entry summaries.
    static func tidyMessage(profile: String, thoughts: [Thought], recentDigests: [EntryDigest], today: Date) -> String {
        let profileText = profile.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines: [String] = [
            "Today is \(longDay(today)).",
            "",
            "Profile:",
            profileText.isEmpty ? "(none yet)" : profileText,
            "",
            "Thoughts in memory (id | label | kind | other names | number of entries | first seen | last seen | what it is):",
        ]

        for thought in thoughts.sorted(by: { $0.id < $1.id }) {
            let others = thought.aliases.isEmpty ? "-" : thought.aliases.joined(separator: "; ")
            let entries = Set(thought.evidence.map(\.entryID)).count
            lines.append("- \(thought.id) | \(thought.label) | \(thought.kind.rawValue) | \(others) | \(entries) | \(thought.firstSeen ?? "-") | \(thought.lastSeen ?? "-") | \(thought.summary.isEmpty ? "-" : thought.summary)")
            for item in thought.evidence.sorted(by: { ($0.date, $0.quote) < ($1.date, $1.quote) }).suffix(6) {
                lines.append("    quote [\(item.entryID.uuidString)] \(item.date): \"\(MemoryText.singleLine(item.quote))\"")
            }
            for link in thought.links.sorted(by: { ($0.target, $0.date) < ($1.target, $1.date) }) {
                lines.append("    linked to \(link.target) (\(link.reason)), \(link.date)")
            }
            for link in thought.userLinks {
                lines.append("    linked to \(link.target) by the person themselves (\(link.reason))")
            }
        }
        if thoughts.isEmpty {
            lines.append("(none yet)")
        }

        lines.append("")
        lines.append("Recent entries (day [entry id]: summary):")
        let recent = recentDigests
            .filter { !$0.failed && !$0.summary.isEmpty }
            .sorted { ($0.entryDate, $0.entryID.uuidString) < ($1.entryDate, $1.entryID.uuidString) }
            .suffix(40)
        for digest in recent {
            lines.append("- \(digest.entryDate) [\(digest.entryID.uuidString)]: \(digest.summary)")
        }
        if recent.isEmpty {
            lines.append("(none yet)")
        }
        return lines.joined(separator: "\n")
    }
}
