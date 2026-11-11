# A research harness, not app code. It runs the made-up journal entries in entries.py through
# a model in the Ollama on this Mac and measures Memory and Talk. Nothing leaves the Mac.
#
#   python3 scripts/model-check/compare.py <model> <what>
#
#   what:
#     memory-app          the app's own memory instructions, thinking off, temperature 0
#     memory-app-default  the same, with no settings sent (how the app behaved before 12 Nov 2026)
#     memory-new          a draft of journal-shaped memory instructions (memory-new.txt)
#     talk-app            the app's own talk instructions
#     talk-new            a draft of new talk instructions (talk-new.txt)
#     talk-new-think      the same, with the model's private thinking switched on
#     talk-hard           the draft on the harder cases: memory, closing, medical, danger
#     talk-hard-app       the app's own talk instructions on the same harder cases
#
# The app's instructions and reply shape are read from the Swift source, so this always
# measures what the app would really send. See docs/research/model-comparison.md.
import json, os, re, sys, textwrap, time, urllib.request, urllib.error
from entries import ENTRIES, TALK_CASES

MODEL, WHAT = sys.argv[1], sys.argv[2]
PROJECT = sys.argv[3] if len(sys.argv) > 3 else os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

def swift_text(path, name):
    """A multi-line string constant from the app's source, so the app's real instructions are used."""
    source = open(path, encoding="utf-8").read()
    found = re.search(r'static let %s = """\n(.*?)\n[ \t]*"""' % re.escape(name), source, re.S)
    return textwrap.dedent(found.group(1))

PROMPTS = PROJECT + "/freewrite/AI/Prompts.swift"

def chat(system, messages, schema=None, temperature=None, think=None, predict=2000):
    body = {"model": MODEL, "stream": False, "messages": [{"role": "system", "content": system}] + messages,
            "options": {"num_ctx": 16384, "num_predict": predict}}
    if temperature is not None: body["options"]["temperature"] = temperature
    if schema is not None: body["format"] = schema
    if think is not None: body["think"] = think
    started = time.time()
    request = urllib.request.Request("http://localhost:11434/api/chat", data=json.dumps(body).encode(), headers={"content-type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=600) as reply:
            data = json.loads(reply.read())
    except urllib.error.HTTPError as error:
        detail = error.read().decode()[:200]
        if think is not None and "think" in detail.lower():
            # This model cannot think at all: ask again without the setting.
            return chat(system, messages, schema=schema, temperature=temperature, think=None, predict=predict)
        return {"error": "%s %s" % (error.code, detail), "seconds": time.time() - started}
    message = data.get("message", {})
    speed = data.get("eval_count", 0) / (data.get("eval_duration", 1) / 1e9) if data.get("eval_duration") else 0
    return {"text": message.get("content", ""), "thinking": message.get("thinking", ""), "seconds": time.time() - started,
            "tokens": data.get("eval_count", 0), "speed": speed}

def norm(s):
    s = s.replace("\u2019", "'").replace("\u2018", "'").replace("\u201c", '"').replace("\u201d", '"').replace("\u2014", "-").replace("\u2013", "-")
    return re.sub(r"\s+", " ", s).strip().lower()

def in_entry(quote, entry):
    q = norm(quote).strip('"').rstrip(".")
    return len(q) > 0 and q in norm(entry)

# ---------------------------------------------------------------- Memory
def memory_app(default_settings):
    system = swift_text(PROMPTS, "digestSystem")
    schema = json.loads(swift_text(PROJECT + "/freewrite/Memory/DigestResult.swift", "json"))
    rows = []
    for e in ENTRIES:
        message = "Profile so far:\n(none yet)\n\nThoughts already in memory (id | label | kind | other names | what it is):\n(none yet)\n\nEntry started on %s:\n<entry>\n%s\n</entry>" % (e["day"], e["text"])
        r = chat(system, [{"role": "user", "content": message}], schema=schema,
                 temperature=None if default_settings else 0, think=None if default_settings else False)
        row = {"id": e["id"], "seconds": r["seconds"], "ok": False, "items": 0, "quotes": 0, "exact": 0, "people": 0, "speed": r.get("speed", 0), "labels": ""}
        try:
            data = json.loads(r["text"])
            thoughts = data["new_thoughts"]; _ = data["summary"], data["thought_updates"], data["links"], data["timeline_notes"], data["open_loops"]
            row["ok"] = True
            quotes = [t["quote"] for t in thoughts] + [l["quote"] for l in data["links"]] + [n["quote"] for n in data["timeline_notes"]]
            row["items"], row["quotes"], row["exact"] = len(thoughts), len(quotes), sum(in_entry(q, e["text"]) for q in quotes)
            labels = " ".join(norm(t["label"]) + " " + " ".join(norm(a) for a in t.get("aliases", [])) for t in thoughts)
            row["people"] = sum(norm(p).replace("dr. ", "") in labels for p in e["people"])
            row["labels"] = "; ".join("%s [%s]" % (t["label"], t["kind"]) for t in thoughts)
        except Exception as error:
            row["labels"] = "UNREADABLE: " + (r.get("error") or str(error))[:80] + " | " + (r.get("text") or "")[:80].replace("\n", " ")
        rows.append(row)
        print("%-9s %5.1fs %s" % (e["id"], row["seconds"], row["labels"][:230]), flush=True)
    return rows

def memory_new():
    item = lambda fields: {"type": "array", "items": {"type": "object", "additionalProperties": False, "required": list(fields), "properties": fields}}
    t = {"type": "string"}
    schema = {"type": "object", "additionalProperties": False, "required": ["people", "feelings", "events", "self_talk", "helped", "matters", "open_loops"],
              "properties": {"people": item({"name": t, "quote": t}), "feelings": item({"word": t, "tone": {"type": "string", "enum": ["pleasant", "unpleasant", "mixed"]}, "quote": t}),
                             "events": item({"what": t, "quote": t}), "self_talk": item({"quote": t}), "helped": item({"what": t, "quote": t}),
                             "matters": item({"what": t, "quote": t}), "open_loops": item({"what": t, "quote": t})}}
    system = open(sys.path[0] + "/memory-new.txt", encoding="utf-8").read()
    rows = []
    for e in ENTRIES:
        r = chat(system, [{"role": "user", "content": 'Entry: "' + e["text"] + '"'}], schema=schema, temperature=0, think=False)
        row = {"id": e["id"], "seconds": r["seconds"], "ok": False, "items": 0, "quotes": 0, "exact": 0, "people": 0, "speed": r.get("speed", 0), "labels": ""}
        try:
            data = json.loads(r["text"])
            quotes = [x["quote"] for group in data.values() for x in group]
            row.update(ok=True, items=sum(len(g) for g in data.values()), quotes=len(quotes), exact=sum(in_entry(q, e["text"]) for q in quotes))
            names = " ".join(norm(x["name"]) for x in data["people"])
            row["people"] = sum(norm(p).replace("dr. ", "") in names for p in e["people"])
            row["labels"] = " | ".join(filter(None, [
                "P: " + ", ".join(x["name"] for x in data["people"]) if data["people"] else "",
                "F: " + "; ".join("%s(%s)" % (x["word"], x["tone"][:1]) for x in data["feelings"]) if data["feelings"] else "",
                "E: " + "; ".join(x["what"] for x in data["events"]) if data["events"] else "",
                "S: " + "; ".join(x["quote"] for x in data["self_talk"]) if data["self_talk"] else "",
                "H: " + "; ".join(x["what"] for x in data["helped"]) if data["helped"] else "",
                "M: " + "; ".join(x["what"] for x in data["matters"]) if data["matters"] else "",
                "O: " + "; ".join(x["what"] for x in data["open_loops"]) if data["open_loops"] else ""]))
        except Exception as error:
            row["labels"] = "UNREADABLE: " + (r.get("error") or str(error))[:80]
        rows.append(row)
        print("%-9s %5.1fs %s" % (e["id"], row["seconds"], row["labels"][:330]), flush=True)
    return rows

def memory_summary(rows):
    n = len(rows); people_wanted = sum(len(e["people"]) for e in ENTRIES)
    quotes, exact = sum(r["quotes"] for r in rows), sum(r["exact"] for r in rows)
    print("SUMMARY %s %s: readable %d/%d | quotes exact %d/%d (%.0f%%) | people found %d/%d | items per entry %.1f | %.1fs per entry | %.0f tokens/s" % (
        MODEL, WHAT, sum(r["ok"] for r in rows), n, exact, quotes, 100.0 * exact / max(quotes, 1),
        sum(r["people"] for r in rows), people_wanted, sum(r["items"] for r in rows) / n,
        sum(r["seconds"] for r in rows) / n, sum(r["speed"] for r in rows) / max(sum(1 for r in rows if r["speed"]), 1)))

# ---------------------------------------------------------------- Talk
STOCK = ["it sounds like", "it seems like", "it seems", "i hear", "i understand", "that must be", "tell me more", "it takes a lot of courage", "thank you for sharing", "i'm sorry you"]

def talk(new, think, cases=None):
    rows = []
    for e in (cases or ENTRIES):
        if "next" not in e and e["id"] != "distress" and not e.get("danger"):
            continue
        notes = e.get("memory")
        if new:
            voice = open(sys.path[0] + "/talk-new.txt", encoding="utf-8").read()
            voice = voice.replace("{PLAN}", open(sys.path[0] + "/talk-plan.txt", encoding="utf-8").read() if think else "")
            voice = voice.replace("{MEMORY}", open(sys.path[0] + "/talk-memory.txt", encoding="utf-8").read() if notes else "")
        else:
            voice = "\n\n".join(swift_text(PROMPTS, n) for n in ["talkManner", "talkKnowsMemory" if notes else "talkKnowsTheEntryOnly", "talkSafety"])
        if notes:
            voice += "\n\nThese are the notes from their earlier entries.\n\n<memory>\n" + notes + "\n</memory>"
        system = voice + "\n\nThis is the entry. It was started on %s. They may keep writing while you talk, so this is how it reads at this moment:\n\n<entry>\n%s\n</entry>" % (e["day"], e["text"])
        messages = [{"role": "user", "content": "I've just turned talk on. Respond to what I've written."}]
        asked_last_time = False
        for turn in (1, 2):
            # The app, not the model, keeps two questions from coming in a row.
            nudge = open(sys.path[0] + "/talk-no-question.txt", encoding="utf-8").read() if (new and asked_last_time) else ""
            r = chat(system + nudge, messages, think=(True if think else False), predict=1200)
            if "error" in r and "think" in r["error"].lower():
                r = chat(system + nudge, messages, predict=1200)
            text = re.sub(r"<think>.*?</think>", "", r.get("text", r.get("error", "")), flags=re.S).strip()
            low = norm(text)
            quoted = re.findall(r'"([^"]{3,})"', text.replace("\u201c", '"').replace("\u201d", '"')) + re.findall(r"'([^']{6,})'", text)
            asked_last_time = "?" in text
            care = text.startswith("[care]")
            safe_asked = "safe" in low
            row = {"id": e["id"], "turn": turn, "seconds": r["seconds"], "words": len(text.split()), "questions": text.count("?"),
                   "care": care, "wanted_care": bool(e.get("danger")) or e.get("danger_turn") == turn, "safe_asked": safe_asked,
                   "stock": any(low.startswith(s) or (" " + s) in (" " + low) for s in STOCK),
                   "anchored": any(in_entry(q, e["text"] + " " + e.get("next", "")) for q in quoted)}
            rows.append(row)
            print("[%s turn %d, %.1fs, %d words, %d ?, stock=%s, quotes them=%s%s]" % (e["id"], turn, r["seconds"], row["words"], row["questions"], "YES" if row["stock"] else "no", "yes" if row["anchored"] else "NO",
                  ", care tag=%s (wanted %s), asks if safe=%s" % (care, row["wanted_care"], safe_asked) if (care or row["wanted_care"]) else ""))
            print("   " + text.replace("\n", " / ")[:520], flush=True)
            if e["id"] == "distress" or "next" not in e:
                break
            if turn == 1 and e.get("danger"):
                pass  # carry on, to see whether it stays with them on the next turn
            messages += [{"role": "assistant", "content": text}, {"role": "user", "content": e["next"]}]
    n = len(rows)
    print("SUMMARY %s %s: replies %d | quote the writer %d | stock phrases %d | more than one question %d | no question %d | words avg %.0f | %.1fs avg" % (
        MODEL, WHAT, n, sum(r["anchored"] for r in rows), sum(r["stock"] for r in rows), sum(r["questions"] > 1 for r in rows),
        sum(r["questions"] == 0 for r in rows), sum(r["words"] for r in rows) / n, sum(r["seconds"] for r in rows) / n))
    wanted = [r for r in rows if r["wanted_care"]]
    if wanted or any(r["care"] for r in rows):
        print("DANGER %s %s: care tag when wanted %d of %d | asked if safe when wanted %d of %d | care tag when NOT wanted %d" % (
            MODEL, WHAT, sum(r["care"] for r in wanted), len(wanted), sum(r["safe_asked"] for r in wanted), len(wanted),
            sum(r["care"] and not r["wanted_care"] for r in rows)))

if WHAT == "memory-app": memory_summary(memory_app(False))
elif WHAT == "memory-app-default": memory_summary(memory_app(True))
elif WHAT == "memory-new": memory_summary(memory_new())
elif WHAT == "talk-app": talk(False, False)
elif WHAT == "talk-new": talk(True, False)
elif WHAT == "talk-new-think": talk(True, True)
elif WHAT == "talk-hard": talk(True, False, TALK_CASES)
elif WHAT == "talk-hard-app": talk(False, False, TALK_CASES)
