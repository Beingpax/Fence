# Shift and the science of distraction

*Research review, 26 Nov 2026. How Shift's design lines up with current research on habits,
cravings and digital distraction, and what to build next.*

> **Decisions, 26 Nov 2026.** Built: the reach journal (SQLite, every pause), a Journal page
> with the two-week trend and one card per day, and a required 20-word reason once a feeling
> is picked at the pause. Rejected by the user: idea 1 ("Back to work") and idea 3 (if-then
> plans). The other ideas are still open.

---

## The short version

Shift's core loop is unusually well grounded. The parts that matter most are already right:
it catches the reach **before the feed pays out**, it makes **turning back the easy default**,
it adds a **breath-length delay that grows with repeats**, it asks the person to **name the
feeling** behind the reach, and it does all of it **without shame**. The strongest field
evidence in this area (the one sec trials, 280 and 1,039 users) supports almost exactly this design.

The gaps are on the other side of the habit:

1. **Shift forgets everything.** The feeling someone names at the pause is the most valuable
   thing the app learns, and it is thrown away. The activity log lives in memory (40 entries)
   and only a lifetime trigger count is saved. Self-monitoring is one of the best-supported
   techniques in behaviour change (d = 0.40 across 138 trials), and Shift does none.
2. **Shift rewards stopping, but never builds the replacement.** Habit science says you don't
   delete a cue-response link, you overwrite it. There is no "when I feel the pull, I'll…"
   plan, which is the best-evidenced planning tool there is.
3. **Shift doesn't help you get back to work.** After "Close it" the person lands on whatever
   tab was behind it. Refocusing after an interruption takes around 25 minutes, and a
   one-line "where was I" plan measurably reduces attention residue.
4. **Progress is invisible.** The real sign that a habit is breaking is *fewer reaches over
   weeks*. Shift counts reaches but never shows the trend.

The rest of this document is the evidence, a principle-by-principle scorecard, and ten ranked
ideas.

---

## 1. What the research says

Evidence strength: **Strong** = meta-analysis or large field trial. **Moderate** = one or two
controlled studies. **Weak** = practitioner books, company data or theory.

### 1.1 Habits are cue → response links, and willpower barely touches them (Strong)

Wendy Wood's work (*Good Habits, Bad Habits*, 2019) is the backbone: a behaviour repeated in a
stable context gets triggered by that context automatically, without a decision. Willpower
doesn't change habits well because people often can't see their own cues, and when tired or
stressed they fall back on habits, good and bad. What works is changing the environment:
**adding friction** to the bad behaviour and removing it from the good one.
([Wharton](https://magazine.wharton.upenn.edu/digital/how-to-form-good-habits-and-break-bad-ones/),
[Behavioral Scientist](https://behavioralscientist.org/good-habits-bad-habits-a-conversation-with-wendy-wood/))

The "limited willpower" idea (ego depletion) failed a 23-lab preregistered replication
(N = 2,141, d = 0.04). Don't build copy or features around "saving your willpower".
([Hagger et al. 2016](https://pmc.ncbi.nlm.nih.gov/articles/PMC4987495))

### 1.2 Short friction at the moment of reaching works, and the way out matters most (Strong)

- **one sec, PNAS 2023** (Grüning et al.): a 10-second delay before a target app opens cut
  openings by **57% over six weeks** (280 people), and users were *more* satisfied. A separate
  experiment (N = 500) split the parts: **the option to dismiss had the biggest effect**, the
  delay helped too, and **the reflective message alone did nothing.**
  ([PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC9974409),
  [one sec](https://one-sec.app/max-planck-study))
- **Haliburton et al., CHI 2024**: logs from 1,039 real users confirmed fewer attempts and more
  intentional openings over time, and found people **rebound quickly after taking breaks from
  the tool**. ([LMU](https://www.medien.ifi.lmu.de/pubdb/publications/pub/haliburton2024chi/haliburton2024chi.pdf))
- A field study of a **breathing pause** before opening Instagram cut use and raised perceived
  control without notable frustration. (Cited in the reactance literature below.)
- Caveat: one sec's lead scientist co-authored the studies and the samples are opt-in.

### 1.3 The real trigger is usually a feeling, not the site (Moderate to Weak)

- Gloria Mark (UC Irvine) measured screen attention falling from about 2.5 minutes (2003) to
  about **47 seconds** (2016–2020), and found people **interrupt themselves about as often as
  others interrupt them**. When external interruptions drop, self-interruption rises to fill
  the gap. ([UC](https://www.universityofcalifornia.edu/news/how-sharpen-your-attention-and-meet-your-goals-2024),
  [TED transcript](https://www.ted.com/podcasts/why-a-digital-detox-wont-reset-your-attention-span-with-gloria-mark-transcript))
- Nir Eyal (*Indistractable*) frames all distraction as escape from an uncomfortable internal
  state: boredom, loneliness, anxiety, difficulty. ([notes](https://notes.andymatuschak.org/zUwEN3yEkMQvwRVDdXLYX5t))
- Judson Brewer (*Unwinding Anxiety*, *The Craving Mind*): habits weaken when **awareness
  updates the reward value**. Noticing what the behaviour actually gives you, with curiosity,
  makes it less rewarding. His trial claims come from his own apps, so treat them as promising,
  not proven. ([Psychology Today](https://www.psychologytoday.com/us/blog/the-craving-mind/201908/the-science-behind-bad-habits-and-how-to-break-them))
- Habit reversal training, the best-studied treatment for compulsive habits, has two essential
  parts: **awareness of each instance** and a **competing response used at that moment**.
  ([Habit reversal review](https://pubmed.ncbi.nlm.nih.gov/7593685/))
- Urge surfing (Bowen & Marlatt 2009) didn't reduce the urge itself but **reduced the
  behaviour**. The goal is riding the wave, not removing it.
  ([PubMed](https://pubmed.ncbi.nlm.nih.gov/20025372/))

### 1.4 If-then plans are the most reliable planning tool (Strong, smaller for breaking habits)

Gollwitzer & Sheeran's meta-analysis of 94 studies (8,000+ people): "If X happens, I will do
Y" plans add **d = 0.65** over intentions alone. For *reducing* an unwanted behaviour the effect
is smaller (d ≈ 0.3), and it only works when the person actually wants the goal.
([NCI summary](https://cancercontrol.cancer.gov/brp/research/constructs/implementation-intentions))

### 1.5 Tracking progress helps, especially when it's written down (Strong)

Harkin et al. 2016, 138 randomised studies (N = 19,951): prompting people to monitor progress
improved goal attainment, **d = 0.40**. Effects were larger when the record was **physical or
written** and when it was **shared**. Monitoring the *behaviour* changes the behaviour; monitoring
the *outcome* changes the outcome. ([APA](https://www.apa.org/news/press/releases/2015/10/progress-goals),
[paper](https://eprints.whiterose.ac.uk/id/eprint/87431/))

### 1.6 Reward the return, not the streak (Moderate)

- **Milkman's megastudy** (*Nature* 2021, 61,000 gym members, 54 interventions): the best one
  gave a tiny bonus for **coming back right after a missed workout**, +27%. Experts could not
  predict which ideas would win. ([Wharton](https://knowledge.wharton.upenn.edu/podcast/knowledge-at-wharton-podcast/how-science-can-help-you-keep-your-fitness-goal/))
- **Streaks cut both ways**: people who break a streak are more likely to quit the activity
  entirely. ([INSEAD](https://knowledge.insead.edu/marketing/consumer-streaks-are-motivating-key-keeping-them-alive))
- **Fresh start effect** (Dai, Milkman & Riis 2014): motivation spikes after temporal landmarks
  such as Mondays, month starts and birthdays, because people feel separated from past
  failures. ([paper](https://faculty.wharton.upenn.edu/wp-content/uploads/2014/06/Dai_Fresh_Start_2014_Mgmt_Sci.pdf))

### 1.7 Praise should inform, not control (Strong for the general principle)

Deci, Koestner & Ryan's meta-analysis of 128 experiments: tangible, contingent rewards can
undermine intrinsic motivation. Verbal feedback that conveys **competence** helps, but praise
that feels **evaluative or controlling** shifts the reason for acting outside the person.
([meta-analysis](https://pubmed.ncbi.nlm.nih.gov/10589297/))
In practice, "You caught it in two seconds" is informational. "Proud of you" is evaluative.

### 1.8 Autonomy decides whether people keep the tool (Moderate)

- Strong enforcement works, but it provokes **reactance**, and reactance predicts abandonment.
  Recent work recommends autonomy-supportive designs: user-set parameters, honest escape
  hatches, and tools that adapt to how ready the person is to change.
  ([Lukoff, Lyngs & Alberts](https://lize-alberts.github.io/publication/preprint-work),
  [JMIR 2026](https://formative.jmir.org/2026/1/e85349))
- Health and wellbeing apps lose a median **70% of users within 100 days**.
  ([scoping review](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC11694054/))
- **Allcott, Gentzkow & Song** (*AER* 2022, ~2,000 adults): self-control problems account for
  about **31% of social media use**, people **pay to keep** commitment tools, and temporary
  reductions **persist**, which is direct evidence that the habit can be broken.
  ([NBER](https://www.nber.org/papers/w28936))

### 1.9 The feed is the problem, not the site (Moderate)

- Lukoff et al. (CHI 2021): on YouTube, **recommendations and autoplay reduce sense of agency;
  search and playlists support it**. A search-first mode raised agency in a three-week field
  study. ([arXiv](https://ar5iv.labs.arxiv.org/html/2101.11778))
- Lyngs et al. (CHI 2020): **removing the Facebook news feed** gave shorter visits and less
  scrolling, and goal reminders helped but were often annoying.
  ([arXiv](https://arxiv.org/abs/2001.04180v2))

### 1.10 Getting back to work is its own problem (Moderate)

- Leroy & Glomb (*Organization Science* 2018): switching away leaves **attention residue**. A
  **ready-to-resume plan**, a short note of where you were and what's next, reduces it.
  ([UW](https://www.washington.edu/news/2018/01/16/task-interrupted-a-plan-for-returning-helps-you-move-on/))
- Mark: returning to a task after an interruption takes about **25 minutes**.
- Mark, Iqbal & Czerwinski (UbiComp 2017, 32 information workers): blocking distractions raised
  self-rated productivity and focus, and **helped most the people most pulled by social media**.
  ([Microsoft Research](https://www.microsoft.com/en-us/research/?p=452322))

### 1.11 Context: the audience

Shift's buyers are professionals on Macs: developers, founders, designers, writers. Microsoft's
2025 Work Trend Index found Microsoft 365 users are interrupted **every 2 minutes** during core
hours (275 a day including after-hours).
([Microsoft](https://www.microsoft.com/en-us/worklab/work-trend-index/breaking-down-infinite-workday))
For this group the reach is rarely boredom alone. It is often **escape from hard work** ("this
is hard") and **checking loops** (X, HN, Reddit, news, YouTube). They also need many of these
sites for work, so they have a low tolerance for false blocks and for being talked down to.

### 1.12 How long it takes (Strong, with wide variance)

Lally et al. 2010: median **66 days** to automaticity, range 18 to 254. A 2024 meta-analysis
found medians of 59–66 days and means of 106–154.
([PubMed](https://pubmed.ncbi.nlm.nih.gov/39685110/))
Breaking a habit follows a similar arc: the cue keeps firing for weeks, with fewer reaches
over time.

---

## 2. Scorecard: Shift against the evidence

| Principle | Shift today | Verdict |
|---|---|---|
| Catch the cue before the reward (1.1, 1.2) | Accessibility notifications wake detection about 0.1 s after Return | **Strong match.** Few competitors are this fast on desktop. |
| Easy way out as the main action (1.2) | Every answer leads to "Close it" | **Strong match.** This was one sec's most effective ingredient. |
| Short, growing delay (1.2) | 10 s, then 20 s, then 30 s, per target, per hour | **Good.** In line with one sec and GoalKeeper's escalating lockout. |
| Breath, not text, during the delay (1.2) | Constellation breath, no countdown digits, no instructions | **Good.** The deliberation message alone was ineffective. Keep text minimal. |
| Name the internal trigger (1.3) | Six feeling chips after the breath | **Strong match** with Eyal, Brewer and the awareness step of habit reversal. |
| A better response at the moment (1.3) | A line suggesting what would meet the feeling better | **Partial.** Generic advice from Shift, not the person's own plan. |
| If-then plans (1.4) | None | **Gap.** |
| Self-monitoring over time (1.5) | Lifetime "Paused N times"; reasons and outcomes are discarded | **Gap.** The biggest one. |
| Immediate reward for turning back (1.6, 1.7) | Happy mascot, chime, rotating praise | **Good, with a tone issue.** Some lines are evaluative ("Proud of you", "Respect. Not everyone can…") or invent numbers ("Ten minutes of your life, saved"). |
| Reward the return after a lapse (1.6) | Nothing after a break ends or a lapse | **Gap.** |
| No streaks, no scores (1.6) | No tally on the pause, no streaks anywhere | **Correct.** Keep it that way. |
| Autonomy and no shame (1.8) | Friend's voice, breaks, honesty clause, user-chosen locks | **Strong match.** |
| Commitment devices (1.8) | Five lock types | **Strong match.** Allcott: people value and pay for these. |
| Target the feed, not the site (1.9) | Path rules exist; presets cover Shorts, LinkedIn feed and a few more | **Good, under-used.** Most presets still block whole sites. |
| Help resuming work (1.10) | Closes the tab; the person lands on whatever was behind it | **Gap.** |
| Set expectations on timescale (1.12) | None | **Gap.** Easy fix. |

---

## 3. What to build, ranked

Ranked by evidence times expected impact, divided by effort. None of these brings back focus
goals or AI intent checks, and none adds anything to the pause beyond what's already there,
except where noted.

### 1. "Back to work": return to where you were after Close it
**Evidence:** Leroy & Glomb (attention residue), Mark (25 minutes to refocus), Wood (make the
good behaviour the easiest one).
**In Shift:** `AppModel` already sees every context through `handle`; it only needs to remember
the last one that wasn't blocked (today it keeps just `lastContext`). After the tab closes, the reward card gets one action, "Back to Xcode", which activates that app. Optionally,
the first time each day, the card offers a one-line "Where were you?" note that's shown back
next time.
**Why first:** this is the moment of highest risk. Cmd-W in a browser drops the person onto
the next tab, often another feed. Two seconds to the real work closes that gap. It is small
to build.

### 2. A private reach journal, and a "Your pulls" view
**Evidence:** Harkin (d = 0.40, larger when recorded), habit reversal awareness training,
Brewer (awareness updates reward value), Mark (self-interruption is invisible to the person).
**In Shift:** persist every reach locally: time, block, target, the feeling named, and the
outcome (closed, break, left the pause). Show a weekly section on the Dashboard:
- **Reaches per day, this week against your first week.** This is the habit breaking, made
  visible. It's the one number worth showing.
- **When the pull hits:** "Most reaches are between 3 and 5 pm."
- **What it's usually about:** "Mostly *This is hard*, on X."

**Guardrails:** never on the pause (the no-tally rule stands), no grades, no red numbers, and
it stays on the Mac. Show reaches as information about the habit, not as failures. Fewer
reaches is good news, and so is any reach that ended in a close.

### 3. "When I feel the pull, I'll…" in the person's own words
**Evidence:** implementation intentions (d = 0.65 overall, about 0.3 for breaking habits),
habit reversal's competing response, Wood on replacing rather than resisting.
**In Shift:** set once, optionally, in onboarding or Settings, per feeling: *When I'm stuck, I'll
write the next line badly.* *When I'm drained, I'll get water.* At the pause, choosing that
feeling shows **their own sentence** instead of one of Shift's general lines. Self-generated
plans beat good advice from someone else.
**Watch out:** you said no in-app timers or forms for the cravings, so this must stay a
one-time setup that's never asked for at the pause. Shift's own lines remain the fallback.

### 4. Turn false blocks into better rules
**Evidence:** reactance and abandonment (1.8), PRD trust target (under 1 false block per 10
hours), Lukoff and Lyngs (feeds, not sites).
**In Shift:** the "I need it" path already asks what for. When someone repeatedly takes a break
on the same site for work, suggest narrowing the rule outside the pause, on the Dashboard: "You
needed YouTube for work three times this week. Block just Shorts and the home page instead?"
For professionals, a blocker that blocks their work gets uninstalled. Rule tuning from real use
keeps the tool and the trust.

### 5. Make feed-only the default for work sites
**Evidence:** Lukoff (recommendations reduce agency, search supports it), Lyngs (feed removal
shortens visits).
**In Shift:** onboarding offers "just the feed" as the first option for YouTube, X, LinkedIn,
Reddit and Facebook (for example `x.com/home`, `reddit.com/r/popular`, `instagram.com/reels`,
YouTube's home page and Shorts), with whole-site blocking one tap away. This may need an
exact-path rule type (the YouTube home page is the root path) on top of today's prefix
matching.

### 6. Reward the comeback, never the streak
**Evidence:** Milkman's megastudy (+27% for returning after a miss), streak-break quitting,
fresh-start effect.
**In Shift:** when a break ends and the person doesn't go back, or on the first close after a
day with many reaches, use a specific comeback line ("Back after a rough afternoon. That's the
part that counts."). On Monday mornings and the first of the month, the Dashboard's greeting can
use a fresh-start line. No streak counter, ever.

### 7. Thin the praise, and make it informational
**Evidence:** operant learning (continuous reward to build a response, intermittent to keep
it), Deci et al. on controlling praise, the audience (1.11).
**In Shift:**
- Keep the chime and the mascot's happy face on **every** close: that's the fast,
  wordless reward.
- After the first two weeks or so, show words on some closes rather than all. A message every
  time becomes wallpaper, which is why `CopyDeck` exists.
- Lean the copy towards **what they did** ("Caught it in under a second", "Third close today,
  all on the first pause") and away from **judging them** ("Proud of you", "That's character",
  "Respect. Not everyone can…").
- Drop lines that invent facts: "Ten minutes of your life, saved", "Not long ago, that might
  have been an hour". Professionals notice made-up numbers, and they undercut the honesty that
  sets Shift apart.

### 8. Planned indulgence: "When do you want to enjoy it?"
**Evidence:** Eyal (schedule time for distraction), Mark (rote attention is fine with a limit),
autonomy and reactance (1.8), micro-breaks (Albulescu 2022: small gains in vigor and fatigue,
d ≈ 0.35).
**In Shift:** schedules can already express this. The change is framing: onboarding asks
"When is Reddit fine?" and leaves lunch or evenings open. A ban with a sanctioned window
provokes far less reactance than a total ban, and makes the pause during work hours feel fair.

### 9. Set expectations about time
**Evidence:** Lally (median 66 days, range 18–254), Haliburton (people rebound after taking
breaks from the tool).
**In Shift:** one line in onboarding: "The pull fades over weeks, not days. Most people need
about two months." The trend from idea 2 then becomes the proof. Fewer people will quit in week
two thinking it isn't working.

### 10. Optional accountability (later)
**Evidence:** Harkin (monitoring works better when shared), relatedness in self-determination
theory, PRD P4 "accountability partner unlock codes".
**In Shift:** a weekly summary the person can share themselves (a share sheet, nothing sent by
Shift), or a partner-held unlock code as a lock type. This touches the local-only promise, so
it should always be explicit and user-initiated.

---

## 4. What not to do

- **No streaks, levels, gems, leaderboards or focus scores.** Opal does gems, streaks and a
  focus score. Streak breaks drive quitting, loss-aversion mechanics are extrinsic, and a score
  turns the pause back into a machine keeping score, which is what you already removed.
- **Don't add reflection text to the pause.** one sec's data says the message alone did nothing;
  the delay and the easy exit do the work. The pause is already at its limit of one thing at a
  time.
- **Don't punish lapses.** No "you broke your block" messages, no red days. The abstinence
  violation pattern (one slip becomes a binge) is well documented in addiction research.
- **Don't frame anything as willpower.** Ego depletion didn't replicate, and Wood's point is
  that habits sit beneath willpower anyway.
- **Don't lengthen the delays much further.** Escalation is useful, but long lockouts on
  professionals who sometimes need the site for real are the fastest route to uninstalling.
  The "I need it" path and idea 4 are the release valve.
- **Don't invent statistics in copy.** See idea 7.

---

## 5. Books worth knowing, and how much to trust them

| Book | Core idea for Shift | Evidence base |
|---|---|---|
| Wendy Wood, *Good Habits, Bad Habits* (2019) | Habits are context-cued. Change friction and context, not willpower. | Strong, peer-reviewed research behind it |
| Gloria Mark, *Attention Span* (2023) | Self-interruption is habitual. Attention has rhythms. Rote breaks are fine with limits. | Strong, decades of field data |
| Nir Eyal, *Indistractable* (2019) | Distraction is escape from internal triggers. Pacts. 10-minute rule. Schedule distraction. | Practitioner synthesis |
| Judson Brewer, *Unwinding Anxiety* / *The Craving Mind* | Curiosity and awareness update reward value. | Some trials, author has a financial stake in the apps |
| Katy Milkman, *How to Change* (2021) | Fresh starts, temptation bundling, the comeback bonus, megastudies. | Strong |
| BJ Fogg, *Tiny Habits* (2019) | Celebrate immediately; emotions wire habits. | Mostly the author's coaching data |
| James Clear, *Atomic Habits* (2018) | Make it invisible, difficult, unsatisfying; identity votes. | Popular synthesis, little direct testing |
| Cal Newport, *Digital Minimalism* / *Deep Work* | Schedule internet use; deep work blocks; 30-day declutter. | Argument and anecdote |
| Johann Hari, *Stolen Focus* (2022) | The environment is designed against attention. | Journalism; some claims contested |
| Anna Lembke, *Dopamine Nation* (2021) | Abstinence periods reset the reward balance. | Clinical experience; the neuroscience framing is simplified |

---

## 6. Limits of this review

- Most of the strongest friction evidence is from **phones**, not Macs. The mechanisms
  (cue → response, friction, dismiss option) transfer, but desktop-specific field trials are
  few (Mark et al. 2017 is the main one, with 32 people and self-reported outcomes).
- Several sources were read as abstracts and summaries rather than full papers; effect sizes
  are quoted from those.
- one sec, Brewer and Fogg all have commercial interests in their own findings.
- No study tests Shift's exact combination. The cheapest way to learn more is to measure
  Shift's own reach trend once the journal (idea 2) exists.
