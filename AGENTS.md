# Writing this site as an agent

This file is for any language model drafting or revising a page in this
repository. The specification, `system/specification.md`, is the design
authority and states where things go. This file adds what the
specification cannot: the ways generated prose gives itself away, and
how to use a style guide as a calibration rather than a cage. Build and
check commands are in the README.

## What good looks like

The standard is technical prose that a working astronomer or engineer
reads straight through once and comes away knowing what the thing is
and what to do. Precise and plain at the same time: the numbers, the
names and the conditions are all there, and the sentences carry the
reader from one to the next without effort. A page that satisfies every
rule in the writing design and still costs the reader effort at every
sentence has failed; the rules exist to make reading easy, not to make
writing safe.

Two sentences with the same technical content:

> Difference-image candidate extraction is performed subsequent to
> PSF-matched subtraction, whereupon detections exceeding the configured
> significance threshold are subjected to real/bogus classification
> prior to alert packet assembly.

> After the PSF-matched subtraction, the pipeline extracts candidates
> from the difference image. Each detection above the significance
> threshold goes to the real/bogus classifier, and the ones that pass
> become alerts.

The second is the site's register. It keeps every term, puts the steps
in the order they happen, uses ordinary verbs for ordinary actions, and
lets one sentence hand off to the next. What makes technical prose hard
going is rarely the technical content: it is nominalised verbs ("extraction is
performed"), passive chains with no actor, stacked qualifiers before the
main verb, and the connective tissue stripped out in the name of
concision. A "because", a short example, or one sentence of orientation
before a dense one is not padding; it is what lets the reader keep
going.

## Purpose before rules

A page exists to answer one reader's question. Before drafting, state
that question and who is asking, and read two neighbouring pages of the
same kind; they are the exemplars, and they teach the style faster than
this file or the writing design does. The writing design is a design
document, complete because it has to be; it is not a checklist to write
against. Read it once, hold its intent, and write.

## The tells

Generated prose is recognised by pattern, not by any single word. The
patterns below are documented in Wikipedia's "Signs of AI writing"
guidance and in corpus studies of published abstracts (Kobak et al.
2025), and reviewers of this site look for them.

- **Em dashes.** None, anywhere on the site, in any register, as the
  writing design says. A comma, parentheses, a colon, or a second
  sentence does the work.
- **Negative parallelism.** "Not X but Y", "not only X but also Y",
  "it is not a question of X; it is Y". State Y.
- **The rule of three.** Three adjectives, three benefits, three
  closing points where the content has two or five. Count what is there.
- **Excess vocabulary.** The words the corpus study found in excess:
  delve, showcase, underscore, crucial, comprehensive, notably,
  insights, enhancing, particularly, additionally. Use the plain word
  or none.
- **Significance padding.** A sentence that says a thing is important,
  notable, or has implications, instead of saying the thing.
- **Puffery.** Adjectives of enthusiasm about RAPID or Roman. The site
  describes; the mandate line on the home page is the only
  self-description.
- **Throat-clearing and sign-off.** Openers that announce what the text
  will do, closers that restate what it did, acknowledgments, offers.
  Start with the fact; stop when the content stops.
- **Uniform formatting.** A wall of short bullets, bold inside sentences,
  a heading over every paragraph. The writing design says when a list
  or a table earns its place; otherwise prose.

## Rhythm

Machine prose is flat: sentences of one length, one shape, one opening.
Human prose varies, and the variation carries meaning. A short sentence
after two long ones lands. A paragraph of one sentence marks a turn. The
signal is real enough that early detectors measured it as burstiness,
though the detectors have moved on and the point is not to fool them.
The point is that rhythm follows thought: a definition is short, a
mechanism with three conditions is long, a warning is one line. Vary
because the content varies, never as ornament, and never at the cost of
the one-idea-per-sentence default.

## Rules as calibration

The writing design has many rules because a design document has to be
complete. A drafting agent does not apply them as a checklist while
writing; that produces stilted prose that satisfies every rule and reads
as generated, a failure as real as the one the rules were written to
prevent. The evidence on instruction density says the same about
prompts: adherence falls as the number of simultaneous rules rises,
earlier rules win over later ones, contradictory rules waste the
model's effort reconciling them, a few positive rules and a good
exemplar outperform a long list of prohibitions, and a prohibition
primes the very thing it forbids (Jaroslawicz et al. 2025; the OpenAI
GPT-5 and GPT-5.1 guides; Castricato et al. 2024). So:

- Hold three things while drafting: the reader's question, the register
  of the page (reference, procedure, or post), and the two exemplar
  pages. Everything else is for the review pass.
- Prefer the positive form of a rule. "Prose paragraphs" rather than "no
  bullets"; "the thing is the subject" rather than "do not address the
  reader".
- Do a separate pass for the tells above and for the writing design's
  mechanical rules after the draft says what it needs to say.
- Where a rule and the content conflict, the content wins and the pull
  request names the rule set aside. A rule that keeps losing is wrong
  and goes to the writing design's review.
- Do not write a new rule into this file or the writing design because
  one draft went wrong; note it in the pull request. Rules accrete
  faster than they are pruned, and the pruning is what keeps the model
  writing well.

## Sources

Primary sources, all read 2026-09-12, with the finding each one
supplies. This list is the evidence for the file; nothing above rests
on anything outside it.

- **Wikipedia, "Signs of AI writing"**, the WikiProject AI Cleanup
  guidance page, live and edited continuously.
  https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing
  The tells by category: superficial significance claims, promotional
  tone, formulaic closings, excess vocabulary, negative parallelism
  ("not X but Y", "not only X but Y"), the rule of three, overuse of em
  dashes as its own heading.
- **Kobak, González-Márquez, Horvát and Lause, "Delving into
  LLM-assisted writing in biomedical publications through excess
  vocabulary"**, Science Advances, 2025-07-02; arXiv:2406.07016.
  https://arxiv.org/abs/2406.07016
  Fifteen million PubMed abstracts, 2010 to 2024; at least 13.5% of 2024
  abstracts show LLM processing by excess style words. Strongest markers
  delves, showcasing, underscores; frequent ones across, additionally,
  comprehensive, crucial, enhancing, exhibited, insights, notably,
  particularly, within. Vocabulary only; nothing on punctuation.
- **Sam Altman, post on X, 2025-11-14.**
  https://x.com/sama/status/1989193813043069219
  "If you tell ChatGPT not to use em-dashes in your custom instructions,
  it finally does what it's supposed to do." Confirms the em dash as a
  known default of the models and a known target of instructions.
- **GPTZero, "What is perplexity and burstiness for AI detection?"**,
  2023-03-01. https://gptzero.me/news/perplexity-and-burstiness-what-is-it/
  Burstiness is how much writing patterns vary across a document, with
  human prose varying more. The same page says GPTZero dropped the
  method in autumn 2023. The rhythm section above uses the
  observation, not the detector.
- **Jaroslawicz, Whiting, Shah and Maamari, "How many instructions can
  LLMs follow at once?"**, 2025-07-15; arXiv:2507.11538.
  https://arxiv.org/abs/2507.11538
  IFScale: 500 simultaneous constraints on one report; the best of 20
  frontier models reaches 68% adherence at full density; three decay
  shapes by model family; a bias toward earlier instructions.
- **Castricato, Lile, Anand, Schoelkopf, Verma and Biderman,
  "Suppressing Pink Elephants with Direct Principle Feedback"**, 2024-02;
  arXiv:2402.07896. https://arxiv.org/abs/2402.07896
  Names the problem that instructing a model to avoid a thing primes the
  thing. The paper's fix is training, not prompting; the prompting
  counter is the positive form of the rule.
- **Anthropic, "Prompting best practices"**, living document.
  https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices
  "Tell Claude what to do instead of what not to do", with the example
  "smoothly flowing prose paragraphs" in place of "do not use markdown";
  examples as the most reliable way to steer format and tone; newer
  models follow instructions literally, so remove over-prompting and
  emphatic "CRITICAL: you MUST" language.
- **OpenAI, GPT-5 and GPT-5.1 prompting guides**, OpenAI Cookbook, 2025.
  https://developers.openai.com/cookbook/examples/gpt-5/gpt-5_prompting_guide
  https://developers.openai.com/cookbook/examples/gpt-5/gpt-5-1_prompting_guide
  The model follows instructions "with surgical precision", so
  "contradictory or vague instructions can be more damaging" than on
  earlier models; a worked example of conflicting rules failing, fixed
  by removing lines rather than adding them; no stock acknowledgments,
  lead with what was done.
- **Google, "Using large language models in technical writing"**, part
  of Google's technical writing courses.
  https://developers.google.com/tech-writing/two/llms
  Prompt with a named style guide and with sample texts to match; check
  every response; when a response is very good, edit it rather than keep
  refining the prompt.
- **Michael Bleigh, "Rules for Rules"**, 2025-06-23.
  https://mbleigh.dev/posts/rules-for-rules/
  A practitioner's rules for writing agent instruction files: positive
  examples over negative ones, options shown in examples rather than
  reference lists restated, several small files over one kitchen sink.
