//
//  CareNet.swift
//  Dear Diary
//
//  The app's own net for words that may mean someone is in danger.
//
//  Talk asks the model to notice danger and answer with care, and usually it
//  does. But it is a model: in testing, a local one read "I hurt myself again
//  last night" and answered with an ordinary reflective question. So the app
//  looks too, with a short list of plain phrases, and when it finds one it
//  shows its own help line (`Prompts.talkCareLine`) and tells the model, for
//  that one reply, to follow the danger rule.
//
//  This is a net under the model, not a judge of anything. It is short and
//  literal on purpose. It will miss indirect wording, which is why the model
//  is still asked to notice, and why a reply the model marks as care shows the
//  help line as well. It will sometimes catch a figure of speech it does not
//  know; the cost of that is one quiet line and a question. It never
//  diagnoses, scores or records anything.
//
//  Nothing is sent anywhere by this file. It looks at text that is already on
//  the Mac and answers yes or no.
//

import Foundation

enum CareNet {
    /// Phrases about dying, ending things or hurting oneself, in English and in Hindi
    /// written in Latin letters. Each is matched as whole words, in lower case, with
    /// punctuation other than apostrophes read as a space (so "self-harm" is "self harm").
    static let phrases = [
        "kill myself", "killing myself", "end my life", "ending my life", "end it all", "ending it all",
        "take my own life", "taking my own life", "suicide", "suicidal",
        "want to die", "wanted to die", "wish i was dead", "wish i were dead", "rather be dead",
        "better off without me", "better off dead",
        "don't want to be here anymore", "dont want to be here anymore",
        "don't want to be here any more", "dont want to be here any more",
        "don't want to be alive", "dont want to be alive", "don't want to live", "dont want to live",
        "no reason to live", "not worth living",
        "hurt myself", "hurting myself", "harm myself", "harming myself", "self harm", "self harmed", "self harming",
        "cut myself", "cutting myself",
        "want to overdose", "going to overdose", "overdose on my", "overdosed on my",
        "marna chahta", "marna chahti", "mar jana chahta", "mar jana chahti",
        "jeena nahi chahta", "jeena nahi chahti", "khudkushi", "aatmahatya", "atmahatya",
    ]

    /// Wording that needs a pattern: other people being "better off" if the writer were not there.
    /// "I would be better off if I slept more" is not this.
    static let patterns = [
        #"\b(everyone|everybody|they|he|she|you|people|family|world|kids)('d| would| will| might)( all| just)? be better off if i\b"#,
    ]

    /// Ordinary sayings that contain one of the phrases above.
    static let figuresOfSpeech = [
        "die of embarrassment", "died of embarrassment", "die of laughter", "died of laughter",
        "die of shame", "died of shame", "die laughing", "died laughing", "kill myself laughing",
        "cut myself some slack", "cutting myself some slack", "cut myself a break", "cutting myself a break",
        "cut myself off", "cutting myself off", "cut myself shaving", "cut myself cooking", "cut myself chopping",
        "hurt myself at the gym", "hurt myself running", "hurt myself lifting", "hurt myself playing",
        "hurt myself working out", "hurt myself falling",
        "career suicide", "social suicide", "suicide mission", "suicide squad",
    ]

    /// True if the text has words that may mean the writer is in danger.
    static func mayBeInDanger(_ text: String) -> Bool {
        var plain = " " + words(text) + " "
        for saying in figuresOfSpeech {
            plain = plain.replacingOccurrences(of: " " + saying + " ", with: " . ")
        }
        if phrases.contains(where: { plain.contains(" " + $0 + " ") }) {
            return true
        }
        return patterns.contains { plain.range(of: $0, options: .regularExpression) != nil }
    }

    /// The text in lower case as plain words with single spaces between them. Apostrophes
    /// are kept, curly or straight; every other mark becomes a space.
    static func words(_ text: String) -> String {
        let lowered = text.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
        let kept = lowered.map { character -> Character in
            character.isLetter || character.isNumber || character == "'" ? character : " "
        }
        return String(kept).split(separator: " ").joined(separator: " ")
    }
}
