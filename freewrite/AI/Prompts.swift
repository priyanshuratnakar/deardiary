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
    - Below you are given numbered lines they wrote on earlier days, each with its day and what it is: a line about a person or topic, or something they felt, told themselves or wanted on a day they wrote about it. You may also be given a few counted lines as a profile: they are background, never recite them.
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
                // What the line is, in a few words for the model: a line about the thought,
                // or something they felt, told themselves or wanted on a day they wrote about it.
                let about: String
                switch thought.kind {
                case .feeling: about = "a day they named feeling \(thought.label)"
                case .open: about = "something they said was still open"
                case .helped: about = "something they wrote had helped (\(thought.label))"
                default: about = "about \(thought.label)"
                }
                return EarlierLine(
                    number: number + 1,
                    date: quote.date,
                    label: quote.about ?? about,
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
            lines.append("{\(line.number)} \(longDay(line.date)), \(line.label): \"\(line.quote)\"")
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

    // MARK: - Memory: reading one entry

    /// How the AI reads one entry: it lists what is in it, each item with a line copied
    /// from the entry. It names nothing and explains nothing. The app checks every item
    /// afterwards and decides what becomes a thought (see MemoryApplier), so nothing here
    /// is taken on trust.
    ///
    /// Rewritten for M14 (see docs/research/ai-layer.md). The first version asked for
    /// "what keeps happening in their life and why", with labels, descriptions and a
    /// profile, and got names such as "Health Anxiety" in the model's words. This one asks
    /// a small model to do what it does well: find and copy.
    static let digestSystem = """
    You are reading one entry from a private journal. List what is in it, using only the writer's own words as proof. Reply with JSON only.

    Find
    - people: every person named, or referred to by a family word (Ma, Papa, Nani) or a role (my boss). name is how the writer refers to them. If the person is already in memory, use that exact name.
    - topics: things the entry is about that could come up again: a project, a task, a place, a habit, an object (the launch, the pricing page, running, the novel, rent). name is two or three plain words, taken from the entry. If the topic is already in memory, use that exact name. Not feelings, not people, and not everyday things such as making tea, a meal or a show they watched.
    - feelings: feelings or body states the writer names about themselves, such as "felt sick", "couldn't sleep", "head was quiet", "felt nothing". word is their own word or short phrase. tone is pleasant, unpleasant or mixed. Not what someone else said about them. If it is the same feeling as one already in memory, use that exact word; if it is different, or the opposite, use their new words.
    - happened: things that happened or that they did. what is a short plain phrase.
    - self_talk: what they tell themselves, realise or admit about themselves ("First time I haven't just said yes.", "I think I'm the one who always makes the plan."). Not plain events.
    - helped: something they did or that happened, after which they say they felt better or things went better ("my head was quiet afterwards" after a run: what is "a run before work"). what is the thing that helped, in a few plain words. Only when the entry itself puts the two together.
    - matters: what they say they want, do not want, or have decided.
    - open_loops: things they say they still need to do or decide, with any deadline they give. what names who or what it is about ("tell Meera about the pricing page by Tuesday", not "tell her").

    Rules
    - quote: copy the words exactly from the entry, one sentence or less, in the language they wrote it in. If you cannot quote it, leave the item out.
    - Do not add feelings they did not name. Do not add causes they did not state. Do not judge anyone.
    - Empty lists are fine. An entry where nothing much happened has nearly empty lists.

    Example
    Entry: "Lunch with Kavya. She thinks I should apply for the Pune job. I laughed it off but I've been thinking about it all evening. Felt lighter after the walk back. Must update my CV this week."
    {"people":[{"name":"Kavya","quote":"Lunch with Kavya."}],"topics":[{"name":"the Pune job","quote":"She thinks I should apply for the Pune job."}],"feelings":[{"word":"lighter","tone":"pleasant","quote":"Felt lighter after the walk back."}],"happened":[{"what":"lunch with Kavya","quote":"Lunch with Kavya."},{"what":"laughed off the Pune job idea","quote":"I laughed it off"}],"self_talk":[{"quote":"I've been thinking about it all evening"}],"helped":[{"what":"the walk back","quote":"Felt lighter after the walk back."}],"matters":[],"open_loops":[{"what":"update my CV this week","quote":"Must update my CV this week."}]}
    """

    /// The material for one reading: the names already in memory, and the entry.
    static func digestMessage(index: MemoryIndex, entryDate: Date, entryText: String) -> String {
        func list(_ names: [String]) -> String {
            names.isEmpty ? "(none yet)" : names.joined(separator: ", ")
        }
        return """
        People already in memory: \(list(index.people))
        Topics already in memory: \(list(index.topics))
        Feelings already in memory: \(list(index.feelings))

        Entry written on \(longDay(entryDate)):
        <entry>
        \(entryText.trimmingCharacters(in: .whitespacesAndNewlines))
        </entry>
        """
    }

    // MARK: - Memory: the weekly tidy

    /// How the AI looks across all of memory, about once a week. The app checks
    /// every proposal afterwards (see MemoryTidier), so nothing here is taken on trust.
    ///
    /// Since M14 it does two things only: it points out thoughts that are the same thing
    /// under two names, and thoughts that came up once and never returned. It no longer
    /// names patterns or writes a profile: what recurs is counted by the app.
    static let tidySystem = """
    You look after a private memory built from one person's journal. Their entries were read one at a time, so the same person or topic may have ended up under two names. Your job is the weekly tidy.

    You are given every thought in memory with its kind, how many entries it is in, and some of its quoted lines. Reply with JSON in the required shape and nothing else.

    Merge duplicates
    - If two thoughts are clearly the same thing under different names ("Ma" and "my mother", "the pricing page" and "pricing"), fold the less established one into the other, using their ids.
    - Merge only when you are sure. Two things that often appear together are not the same thing. When unsure, leave them apart.
    - Never merge two different people. Never merge a person with a topic. Leave feelings and things marked "still open" alone.

    Retire one-offs
    - List the ids of people and topics that came up in a single entry some weeks ago and never returned. The app decides whether each one really qualifies.
    - Never list a feeling, something that helped, or something still open.

    The reply is one JSON object with exactly these fields:
    - merges: a list of {from, into}.
    - retire: a list of thought ids.
    Lists may be empty. Finding nothing to change is fine.
    """

    /// The material for one tidy: every thought with its kind, how often it is seen, and its recent quotes.
    static func tidyMessage(thoughts: [Thought], today: Date) -> String {
        var lines: [String] = [
            "Today is \(longDay(today)).",
            "",
            "Thoughts in memory (id | name | kind | other names | number of entries | first seen | last seen):",
        ]

        for thought in thoughts.sorted(by: { $0.id < $1.id }) {
            let others = thought.aliases.isEmpty ? "-" : thought.aliases.joined(separator: "; ")
            let entries = Set(thought.evidence.map(\.entryID)).count
            lines.append("- \(thought.id) | \(thought.label) | \(thought.kind.name) | \(others) | \(entries) | \(thought.firstSeen ?? "-") | \(thought.lastSeen ?? "-")")
            for item in thought.evidence.sorted(by: { ($0.date, $0.quote) < ($1.date, $1.quote) }).suffix(3) {
                lines.append("    \(item.date): \"\(MemoryText.singleLine(item.quote))\"")
            }
        }
        if thoughts.isEmpty {
            lines.append("(none yet)")
        }
        return lines.joined(separator: "\n")
    }
}
