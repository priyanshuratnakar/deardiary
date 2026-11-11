# A prototype of the app's own safety net: plain phrases that mean someone may be in danger.
# Short and literal on purpose. It is a net under the model, not a judge of anything.
import re
PHRASES = [
    "kill myself", "killing myself", "end my life", "ending my life", "end it all", "ending it all", "take my own life",
    "suicide", "suicidal", "want to die", "wanted to die", "wish i was dead", "wish i were dead", "better off without me",
    "better off if i", "don't want to be here anymore", "dont want to be here anymore", "no reason to live",
    "hurt myself", "hurting myself", "harm myself", "harming myself", "self harm", "self-harm", "cut myself", "cutting myself", "overdose",
    "marna chahta", "marna chahti", "mar jana chahta", "mar jana chahti", "jeena nahi chahta", "jeena nahi chahti", "khudkushi", "aatmahatya",
]
NOT_DANGER = ["die of embarrassment", "died of embarrassment", "die of laughter", "kill myself laughing"]
def may_be_in_danger(text):
    t = re.sub(r"\s+", " ", text.lower().replace("’", "'"))
    for harmless in NOT_DANGER:
        t = t.replace(harmless, " ")
    return any(p in t for p in PHRASES)
if __name__ == "__main__":
    tests = [
        ("I'm so tired of all of it. Lately I keep thinking everyone would be better off if I just wasn't around.", True),
        ("sometimes i think about just ending it all", True),
        ("I hurt myself again last night. I don't want to talk about why.", True),
        ("kabhi kabhi lagta hai jeena nahi chahti", True),
        ("This deadline is killing me. I could have died of embarrassment in standup.", False),
        ("I wanted to die of embarrassment when my screen share showed my tabs.", False),
        ("Slept badly. Too much coffee.", False),
        ("My plant is dying and I feel like a failure.", False),
        ("He said the project is dead. We killed it in the meeting.", False),
        ("I want this week to end.", False),
    ]
    for text, wanted in tests:
        got = may_be_in_danger(text)
        print("%-5s %s  %s" % ("ok" if got == wanted else "WRONG", "net: %-5s" % got, text[:86]))
