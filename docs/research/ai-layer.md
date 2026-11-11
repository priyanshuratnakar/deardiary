# Making the AI layer better: research and a plan

12 November 2026. Written after the owner said the memory is not tuned for journaling and mental health, and that Talk feels generic.

Three things were done: a baseline of the app as it is, research on models, memory design and conversation craft, and one experiment with redesigned instructions. Every entry used was made up.

## The short version

1. **The complaint is right, and it has two separate causes.** The local model in use (`llama3.2`, 3B) is too small, and the app's instructions are generic: Memory uses the kinds of a topic map, and Talk is told to "reflect, then ask one question" on every turn, which is exactly the reply people find generic.
2. **Memory improves a lot from redesign alone,** even on the small model.
3. **Talk needs both** better instructions and a bigger model. The small model could not follow richer instructions.
4. **No "mental health model" is worth using.** Therapy-tuned open models exist, but none has an independent quality or safety evaluation, and the evidence available says a strong general model with good instructions does better.

## Where the app stands today (baseline)

Model: `llama3.2` through Ollama. Four made-up entries about a week of work, a colleague called Meera, sleep and a decision.

**Talk, as it is now**

- "It sounds like you're replaying a conversation with Meera about a launch, and it's left you feeling uncertain and uneasy. Can you tell me more about what specifically was on your mind when you said yes to everything she asked?"
- "It takes a lot of courage to share your thoughts and feelings with someone, even if it's just a journal. Can you tell me more about what happened with Meera and the pricing page?"

The second one flatters, which the instructions forbid, and misses the point of the entry (the first time the writer did not just say yes).

**Memory, as it is now**

| Entry | What it kept |
| --- | --- |
| Monday | "feeling of fear" |
| Wednesday | "heavy legs", "launch date issues", "quiet head" |
| Friday | "saying no", "taking on task" |
| Sunday | "thing to tell Meera" |

Meera is in three of the four entries and never became a thought. Neither did the run, the sleep, or the launch.

## What the research says

### Models

- **For this Mac (M5 Pro, 24 GB): `gemma4:12b`,** about 8 GB. It fits with room for a 16k context. Its larger sibling leads the open models on EQ-Bench 4, a test of emotional intelligence; there is no such score for any model of this size, so this has to be tested here. ([gemma4 on Ollama](https://ollama.com/library/gemma4/tags), [EQ-Bench 4 mirror](https://benchlm.ai/benchmarks/eqbench4))
- **Alternatives to compare:** `qwen3.5:9b` (about 7 GB, reported strong at staying in JSON) and `gemma4:12b-it-q8_0` (13 GB, the same model with less compression, if quotes are miscopied). The 26B to 31B models do not fit usefully in 24 GB.
- **One model for both jobs,** with different settings: two 8 GB models would keep pushing each other out of memory.
- **Settings matter.** Send `think: false` explicitly (these models think by default, and with thinking on Gemma 4 can skip the required JSON shape: [Ollama issue 18774](https://github.com/ollama/ollama/issues/18774)). Memory should run at temperature 0. Talk should keep the model's own sampling defaults. The app sends none of these today.
- **Therapy fine-tunes: skip.** General models scored higher on empathy than 7B mental-health tunes in one study ([arXiv 2601.01341](https://arxiv.org/abs/2601.01341)); across 127 models, mental-health tuning "conferred no consistent benefit" ([medRxiv](https://www.medrxiv.org/content/10.64898/2026.01.02.25343289v1)).
- **Hosted:** Claude's current models lead the same benchmark, ahead of OpenAI's. It is scored by a model, not by people.

### Memory

- **Give it the shape of a journal.** Kinds suggested by CBT's five-part model and by what journaling apps show back: Person, Feeling, Event, Self-talk (what they tell themselves, kept as a quote), What helped, What matters (values, goals, decisions), Open loop, Topic. ([Padesky](https://padesky.com/newpad/wp-content/uploads/2020/07/CollabCaseConcept_Client-Knows-Best-Padesky-web.pdf), [Rosebud's weekly report](https://help.rosebud.app/ai-analysis/weekly-report))
- **Feelings in the writer's own words,** marked only pleasant or unpleasant. Models are poor at picking fine emotion labels (about 0.46 F1 on 27 labels for a tuned classifier: [GoEmotions](https://research.google/blog/goemotions-a-dataset-for-fine-grained-emotion-classification/)).
- **Open loops with a status** (open, settled, dropped). Unfinished goals keep intruding until there is a plan ([Masicampo 2011](https://pubmed.ncbi.nlm.nih.gov/21688924/)).
- **Small models should classify and copy, in two or three simple passes,** not do everything in one request. Systems that ask a small model for a whole graph at once fail on JSON errors ([arXiv 2604.01707](https://arxiv.org/abs/2604.01707)).
- **Patterns should be counted by the app and worded from a template:** "in 6 of your last 20 entries", "open since 2 October". Never "because", "always" or "tends to". Models asked to reflect still add things that were not there ([Generative Agents](https://arxiv.org/abs/2304.03442)).
- **Links marked as "you said so" or "appeared together",** so a coincidence is never shown as a cause.
- **What to refuse:** names of thinking errors, clinical terms, personality types, wellbeing scores, feelings the writer did not name, other people's motives. Experts agreed on distortion labels only about a third of the time in one dataset ([arXiv 2511.01482](https://arxiv.org/abs/2511.01482)), and the APA finds no consensus that such tools can give diagnostic feedback ([APA advisory](https://www.apa.org/topics/artificial-intelligence-machine-learning/health-advisory-chatbots-wellness-apps)).

### Talk

- **The "reflect, then ask" template is the generic reply.** Counselling research rates a reflection that only repeats as adding "little or no meaning" ([MITI 4.2.1](https://casaa.unm.edu/assets/docs/miti4_2.pdf)); "I understand how you feel" and "What happened?" score as weak empathy, specific replies as strong ([EPITOME](https://arxiv.org/abs/2009.08441)).
- **Give it a small set of named moves and have it pick one:** set two of the writer's phrases against each other; point at one word; name what changed since an earlier day; ask what they would tell a friend; stay with the hard part and ask nothing; one specific question. Choosing a strategy explicitly improved human-rated support ([Kang et al. 2024](https://aclanthology.org/2024.acl-long.813/)).
- **Not a question every turn.** Skilled helpers reflect at least as often as they ask.
- **A plain voice, not "a thoughtful therapist".** Stock lines such as "I see you" were classed as deceptive empathy ([Brown 2025](https://www.brown.edu/news/2025-10-21/ai-mental-health-ethics)).
- **Use memory for contrast, not recall:** one dated line, to show a change or a repeat.
- **Ask what they want when it is unclear:** to be heard, to dig, another angle, or a next step. Models tend to problem-solve when people share feelings ([BOLT](https://arxiv.org/abs/2401.00820)).
- **Keep honest friction.** Models protect people's self-image far more than humans do ([ELEPHANT](https://arxiv.org/abs/2505.13995)), and warmth-tuned models make more errors and agree more with false beliefs ([Oxford 2026](https://www.ox.ac.uk/news/2026-04-29-friendly-ai-chatbots-make-more-mistakes-and-tell-people-what-they-want-to-hear)). Warmer must not mean more agreeable.
- **Safety must survive.** The crisis rule overrides everything and is checked every turn; replies get less safe over long conversations ([Anthropic, December 2025](https://www.anthropic.com/news/protecting-well-being-of-users)). Not a therapist, no diagnosis, point to real people, no hooks that keep people talking.

## The experiment

Same model (`llama3.2`), same made-up entries, redesigned instructions.

**Memory, first pass (list what is in the entry, journal-shaped kinds, one example, temperature 0)**

| Entry | Before | After |
| --- | --- | --- |
| Monday | "feeling of fear" | Meera; felt sick (unpleasant); the call about the launch; said yes to everything |
| Wednesday | "heavy legs", "launch date issues", "quiet head" | Arjun; went for a run; the Friday review |
| Friday | "saying no", "taking on task" | Meera; stomach drop (unpleasant); asked about the pricing page |
| Sunday | "thing to tell Meera" | Meera; "I think I already know I don't want the pricing page"; tell Meera by Tuesday |

21 of 22 quotes were copied exactly. It still missed things a bigger model should catch: "my head was quiet" after the run (what helped), "slept fine", and the shift on Friday ("First time I haven't just said yes").

**Talk (named moves, plain voice, three examples, private notes first)**

The small model could not carry it. It skipped the private notes, leaked a line of them into a reply, and produced one reply that made no sense ("But doesn't 'not up to the job' sound a bit like a compliment?"). One reply was good: "You said 'I just keep doing it'. What is 'it' that you're keeping doing?"

So redesign helps Talk only with a model big enough to follow it. That needs testing on `gemma4:12b`.

## The plan

Three steps, each its own milestone, each shown before it is built.

**1. A better local model, measured (small). Done on 12 November: see [model-comparison.md](model-comparison.md).** Download `gemma4:12b` (about 8 GB). Compare it with `llama3.2` and `qwen3.5:9b` on a fixed set of made-up entries: does the JSON hold, are quotes exact, how good is Talk by the rubric below, how fast is it. Then have the app send the right settings for each job. This step also tells us whether one model can do both jobs.

**2. Talk that is specific (medium).** New instructions: plain voice, named moves, examples, a private planning step for models that can think, memory used for contrast, and asking what the writer wants. A way to end a talk in one line of their own words. A check in code for stock phrases. The crisis rule kept above everything.

**3. Memory shaped for a journal (large).** The new kinds; feelings in the writer's words with pleasant or unpleasant; open loops with a status; links marked "you said so" or "appeared together"; two simple passes for small models; patterns counted by the app. The map's legend and colours change with the kinds. Existing memory is rebuilt, and the writer's own fixes are kept.

**A rubric for Talk (0 to 2 each),** scored by hand on made-up entries, because models that judge replies overrate them ([CounselBench](https://arxiv.org/abs/2506.08584)):

1. Anchored: quotes a phrase or detail; could not sit under another entry.
2. Adds meaning: a tension, a shift or a gap, not a paraphrase.
3. One move; at most one question, and a specific one.
4. No unasked advice, no diagnosis, no verdict on people who are not there.
5. Honest: no flattery; says what does not add up.
6. Memory, when used: relevant, dated, quoted exactly, offered as something to look at.
7. Short and plain; no stock phrases.

## What is not known

- No study was found of models this small (3B to 12B) doing either job. Everything about them has to be tested here.
- The benchmark scores came from a mirror of EQ-Bench, and several papers were read as abstracts only.
- The therapy-chatbot trials that showed benefit used purpose-built bots with clinicians watching. Their results do not transfer to a journal.
- The OpenAI and Claude paths of the app have still not been tried against the real services.
