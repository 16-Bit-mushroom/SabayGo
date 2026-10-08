# How we evaluated the YOLOv8 model — in plain language

For the group first, then for the adviser and the panel. No code in here.
The technical version is `ai_service/eval/README.md`.

---

## 1. The one thing to get straight first

**We did not build or train a model.** We used a ready-made one —
YOLOv8n, published by a company called Ultralytics, already trained to
recognise 80 everyday things, one of which is "person". We downloaded it and
pointed it at a camera. We changed nothing inside it.

This matters because when an adviser says *"show me how the model
performed,"* the usual thing they picture is training graphs — loss curves
going down over epochs. **We have none, and we should not pretend to.**
There was no training, so there is no training curve. Inventing one would be
describing work nobody did.

So we answered a different question, and it is the better question for our
study anyway:

> We did not ask "how well did our model learn?"
> We asked **"how accurately does it count people, and what does that
> accuracy mean for catching a conductor who pockets a fare?"**

Everything below is that second question.

Your manuscript already supports this framing. §2.3.2.1 says YOLOv8 is
"a pretrained model rather than one built from scratch." We are being
consistent with the paper, not making an excuse.

---

## 2. The metrics, one sentence each

The system takes a photo of the cabin and produces **one number**: how many
people it sees. We call that `C_visual`. We compare it against the truth.

| Metric | What it means in plain words |
|---|---|
| **MAE** | On average, how many people is the count off by? "MAE 0.4" = typically wrong by less than half a person. |
| **RMSE** | Same idea, but big mistakes are punished harder. If RMSE is much bigger than MAE, we have occasional bad misses rather than steady small ones. |
| **Bias** | Does it *lean* toward seeing too few or too many? **This one has a direction that matters.** Negative = it tends to miss people. |
| **Exact match** | How often is the count exactly, perfectly right? |
| **Within ±1** | How often is it right, or off by only one person? |
| **By occupancy** | All of the above, split by how full the van is: empty, 1–3, 4–7, 8–11, 12–14. |

### Why "by occupancy" is the interesting one

A nearly empty van is easy — three people, clearly separated, the model sees
three. A full 14-seat van is hard, because **passengers sit behind and beside
each other and physically block the camera's view.** You cannot count a head
you cannot see.

So we expect accuracy to fall as the van fills. The table shows exactly where
it falls off. That is not a weakness in our work — it is a finding, and it is
the honest thing to report. A paper claiming equal accuracy at 2 passengers
and 14 would be the suspicious one.

### Why "bias" has a direction

- **Negative bias** (sees fewer people than are there) → it *hides*
  passengers → a cheat can slip through. **This is the dangerous direction.**
- **Positive bias** (sees more people than are there) → it invents
  passengers → an honest driver gets accused of stealing.

One of those loses the cooperative money. The other gets an innocent person
in trouble. They are not equally bad in the same way, and reporting a single
"accuracy" number would hide the difference completely.

---

## 3. How this connects to revenue leakage — the heart of it

This is the part to lead with in front of the adviser, because it is the
whole point of the thesis.

Our system compares two numbers:

```
Δ  =  C_visual  −  C_booked
     (bodies the     (tickets in
      camera sees)    the system)
```

If Δ is not zero, something does not add up, and the office is told.

### Walk through four situations

**Situation 1 — everything honest, camera correct**
10 tickets sold. 10 people aboard. Camera counts 10.
`Δ = 10 − 10 = 0`. Reconciled. Nothing happens. Correct.

**Situation 2 — the conductor pockets two cash fares**
10 tickets in the system. But 12 people are actually aboard, because two
walk-ins paid cash that never got logged. Camera counts 12.
`Δ = 12 − 10 = +2`. **Flagged. The cheat is caught.** This is the system
working — and notice the paper manifest could never catch it, because the
manifest is exactly what was falsified.

**Situation 3 — the conductor pockets two fares, but the camera misses them**
Same as above: 12 aboard, 10 in the system. But those two extra passengers
are sitting in the back row behind other people, and the camera only sees 10.
`Δ = 10 − 10 = 0`. **Reconciled. The cheat goes undetected.**

**Situation 4 — everyone honest, but the camera miscounts**
10 tickets, 10 people aboard, but the model double-counts someone in a
mirror or a reflection and reports 11.
`Δ = 11 − 10 = +1`. **An honest crew is flagged for theft.**

### Now the key insight

Look at situations 3 and 4. In both, the *only* thing that went wrong was
**the model's counting error**.

- A counting error in one direction (situation 3) = **a missed cheat.**
- A counting error in the other direction (situation 4) = **a false
  accusation against an honest person.**

That is why counting accuracy *is* the revenue-leakage metric. We do not need
a separate experiment about leakage. **The count error and the leakage
performance are the same measurement, read two different ways.** Our harness
computes the second directly from the first.

So the table we report is:

| | What it answers |
|---|---|
| **False-alarm rate** | Out of honest trips, how often does the system wrongly accuse the crew? |
| **Detection rate, 1 hidden passenger** | If a conductor hides exactly 1 fare, how often do we catch it? |
| **Detection rate, 2 hidden** | Same, for 2. |
| **Detection rate, 3 hidden** | Same, for 3. |

Note that hiding *more* passengers is *easier* to catch — a bigger lie makes
a bigger Δ. The hardest case to catch is someone hiding just one.

### The blind spot worth naming out loud

There is one specific way the check fails, and we should say it before the
panel finds it:

> If the conductor hides exactly **2** passengers, **and** the camera happens
> to miss exactly **2** passengers, the two errors cancel out. Δ reads zero
> and the trip looks perfectly clean.

Our report measures how often that coincidence happens, for 1, 2 and 3
hidden passengers. Being the ones who point this out is much stronger than
being asked about it.

---

## 4. Why we test several confidence thresholds

The model does not simply say "person." It says "I am 73% sure this is a
person." We set a cut-off — currently **0.45**, meaning 45% sure — and ignore
anything below it.

That one setting controls the trade-off:

- **Lower the cut-off** → the model reports more people, including shaky
  guesses → catches more hidden passengers, **but accuses more honest crews.**
- **Raise the cut-off** → only confident detections count → fewer false
  accusations, **but more cheats slip through.**

There is no universally correct value. It is a judgement about which mistake
the cooperative would rather live with. What we *can* do is **measure both
rates at five different cut-offs and show the trade-off**, so our chosen 0.45
is a decision backed by a number instead of a guess.

This is the operating-point graph in our results. It is also, frankly, the
part that makes the evaluation look like real engineering rather than a
demo.

---

## 5. Where the dataset came from, and what is in it

### What we used

**COCO val2017** — a large, free, widely used collection of everyday
photographs, published by Microsoft and standard in computer-vision
research. Every person in every photo has already been marked by human
annotators.

### Why this is a legitimate choice, not a shortcut

Two reasons, and the first is the important one:

1. **It is held out.** The YOLOv8n model we use was trained on COCO's
   *training* half (`train2017`). We test on COCO's *validation* half
   (`val2017`), which the model has **never seen.** Testing a model on data
   it was trained on is the classic beginner's mistake in machine learning,
   and we specifically avoided it. If an adviser asks only one sharp question
   about our dataset, it will be this one — and we have the right answer.

2. **The ground truth is already there.** Because humans already marked every
   person, we get the true count for free. **We labelled nothing by hand.**
   Hand-labelling a few hundred photos would have cost days and introduced
   our own mistakes.

### What is actually in our test set

We do not use all of COCO — most of it is irrelevant to a van. We filter it
down with three rules, and each rule exists to keep the ground truth
*honest*, not to make our numbers look better:

| Rule | Why |
|---|---|
| **Throw out "crowd" photos** | COCO marks dense crowds as one big blob labelled "many people" instead of counting them. There is no true number, so we cannot score ourselves against it. |
| **Keep only 1 to 14 people** | That is a UV Express van's capacity. A street photo with 40 pedestrians tells us nothing about a 14-seat cabin. |
| **Every person must fill at least 1% of the photo** | A seated passenger fills a large part of a cabin photo. A pedestrian far down the street is forty pixels. Without this rule our score would be dominated by tiny distant specks the system will never be asked to count. |

Plus **50 photos with no people at all** — the cheapest test there is. Any
count above zero on an empty frame is the model inventing a passenger out of
nothing.

The exact figures (how many photos survived each rule) are printed by the
build step and recorded in the report header, so we quote measured numbers,
not estimates.

### The second half: degraded copies

A COCO photo is a clean, well-lit, sharp photograph. A van cabin is not. So
we take **those same photos** and deliberately damage them in controlled
ways, then count again:

| Condition | Standing in for |
|---|---|
| Resolution halved, then quartered | A cheaper or wider-angle camera |
| Brightness at 60%, then 35% | An overcast afternoon; dusk on a cabin light |
| Horizontal motion blur | A moving van on an imperfect road |
| Re-compressed at quality 70 | Our own system's image compression |

This does not turn a street into a van. **What it does is measure how fast
accuracy falls as the picture gets worse** — which is exactly the dependency
your Scope and Limitations already admits to ("depends on adequate in-van
lighting and camera placement"). We are measuring a limitation we already
declared instead of just declaring it.

---

## 6. The weakness, and how to handle it honestly

**Say this before you are asked.** It is the one soft spot, and owning it
reads as rigour. Being caught hiding it reads as the opposite.

> These are street photographs, not footage from a camera mounted inside a
> UV Express van. We did not have the in-van camera unit during development.
> So our figures describe how well the detector counts people, and what that
> accuracy means for our reconciliation rule — but accuracy inside a real
> occupied cabin, with real seat geometry and real glare, is still to be
> established once the hardware is installed.

Then immediately offer the fix, which is what turns a weakness into a plan:

> We can close this in half a day. Park a van, have classmates sit in it at
> every occupancy from 0 to 14, shoot it in three lighting conditions from
> two camera positions — about 90 photos. The true count is exact because we
> set it ourselves. Our harness already accepts those photos with no changes
> and reports them **beside** the public-dataset figures rather than mixing
> the two.

**Strong recommendation: actually do this before the defence.** It is the
single cheapest upgrade available to the Results chapter, and it converts the
paragraph above from an admission into a measured claim.

---

## 7. A thing we found that needs fixing in the paper

While building this, we found that **the manuscript states the alert rule two
different ways**:

- **§2.3.2.1** says: `Δ ≠ 0` → discrepancy detected.
  (Any mismatch, in either direction.)
- **§2.3.4** says: alert if the physical count **exceeds** the manifest.
  (Only when there are *more* bodies than tickets.)

Those are different rules. The first also fires when there are *fewer* people
than tickets — which is not theft at all, just a no-show or a missed
detection — so it raises far more false alarms against honest crews. The
second is blind to undercounting.

The code follows §2.3.2.1 (we store the variance with its sign, so the office
can tell the two situations apart). Our report measures **both** rules so the
difference is visible. §2.3.4's sentence is the one that needs rewording;
the replacement is in `docs/MANUSCRIPT_CORRECTIONS.md` §9.

Raising this ourselves is good. If the paper says one rule and our results
table reports the other, that is the first thing a panellist will notice.

---

## 8. How to present it — a running order

Five or six minutes, in this order.

1. **Set the frame, immediately.** "The model is pretrained and unmodified,
   so there are no training curves to show. What we measured is counting
   accuracy, and what that accuracy means for detecting revenue leakage."
   Say this first. It prevents the whole conversation going down the "where
   are your epochs" road.

2. **Show the four situations from §3.** Ten tickets, twelve bodies. This is
   the moment the adviser understands why counting accuracy *is* the
   anti-theft metric. Do not skip to the tables before this lands.

3. **Then the counting table.** MAE, bias, and the occupancy breakdown.
   Point at the full-van rows and say plainly: accuracy drops when the van
   fills, because passengers block each other, and here is by how much.

4. **Then the leakage table.** False-alarm rate, and detection rates for 1,
   2 and 3 hidden passengers. Name the cancel-out blind spot yourself.

5. **Then the threshold graph.** "Here is the trade-off between catching
   cheats and accusing honest crews. We picked 0.45. Here is the measurement
   that justifies it."

6. **Then the limitation and the plan.** §6, in that order: the weakness,
   then the half-day staged shoot that closes it.

### Questions you should expect

**"Why didn't you train your own model?"**
Training a person detector from scratch needs tens of thousands of labelled
images and hardware we do not have, and it would not beat a model trained on
200,000 of them. Our contribution is not a better detector — it is using a
detector as an independent check against a manifest that can be falsified.
That is what §2.3.2.1 claims and it is what we built.

**"Your test data is street photos, not vans."**
Correct, and we say so in Limitations. Two things we did about it: we filtered
to van-like occupancy and framing, and we re-ran everything on deliberately
degraded copies to measure how accuracy falls as the picture gets worse. The
staged-van shoot is the next step and it is half a day's work.

**"What is your accuracy?"**
Give MAE and exact-match, then immediately add the occupancy split, because a
single average hides the thing that matters — it is much better on a near
empty van than a full one.

**"How do you know it would catch a real cheat?"**
That is the leakage table. For a conductor hiding one, two or three fares, it
reports how often Δ comes out non-zero. And it reports the false-alarm rate
alongside, because a system that flags everything would "catch" every cheat
and be worthless.

**"Did you test on data the model was trained on?"**
No — and this is deliberate. The weights were trained on COCO train2017; we
test on val2017, which is held out and unseen.

---

## 9. Glossary — every abbreviation, with our own numbers

### The error measures

**MAE — Mean Absolute Error.** How wrong each count was, ignoring whether
it was too high or too low, averaged. **Ours: 0.34** — typically off by
about a third of a person. The everyday "how wrong is it usually" number.

**RMSE — Root Mean Square Error.** The same idea, but each error is squared
before averaging and the square root taken at the end. Squaring makes big
mistakes count for much more than small ones.

The useful trick is comparing the two. **Our RMSE (0.79) is more than double
our MAE (0.34).** If every error were the same size the two would be equal,
so the gap tells us the errors are *uneven* — mostly tiny, with occasional
large misses. Those large misses are the full-van cases.

**Bias.** Not an abbreviation, but the one people skip. MAE throws away
direction; bias keeps it. **Ours: −0.28**, and negative means it tends to
see *fewer* people than are present — the direction that hides a passenger.
On the 8–11 occupancy band it is −2.46, missing about two and a half people.

### The small ones

| Term | Means |
|---|---|
| **n** | how many items are in that row. `n = 28` on the 8–11 band means only 28 photos, which is why that row is suggestive rather than solid |
| **p95** | 95th percentile. Our 124 ms p95 means 95% of counts finished faster than that. More honest than an average, which one freak slow case can drag around |
| **ms** | milliseconds; 1000 ms = 1 second |
| **Δ (delta)** | the variance, as the manuscript writes it: `Δ = C_visual − C_booked` — camera count minus ticket count |
| **C_visual / C_booked** | "count, visual" (what the camera saw) and "count, booked" (tickets in the system) |
| **k** | in the leakage table, how many fares the conductor is hiding in that scenario. "det k=1" = how often we catch someone hiding one |

### The model and its settings

**YOLO — You Only Look Once.** The detection method's name, from its trick:
one pass over the whole image instead of sliding a window across it
repeatedly. **v8** is version 8. The **n** in `yolov8n` is *nano*, the
smallest and fastest of five sizes — chosen because it has to run on a small
in-van computer.

**conf — confidence threshold.** How sure the model must be before it counts
something as a person. Ours is **0.45**, meaning 45% sure. See §4.

**IoU — Intersection over Union.** How much two boxes overlap, used to merge
duplicate detections of the same person. Ours is 0.50.

**COCO — Common Objects in Context.** The Microsoft photo collection our
test images come from. "val2017" is its 2017 *validation* split — the
held-out part the model never trained on. See §5.

### One we will be asked about but did not use

**mAP — mean Average Precision.** The standard scoreboard number for object
detection. We deliberately do not report it, for two reasons. It grades
*where the boxes are drawn*, and our system never looks at boxes — it only
counts them, so mAP measures an intermediate step the system discards. And
it would have required hand-drawing boxes on hundreds of photos. If a
panellist asks why there is no mAP, that is the answer.

---

## 10. One-paragraph version, if you only get a minute

> The detector is pretrained and unmodified, so there is nothing to report as
> training performance. What we measured is how accurately it counts people,
> and what that accuracy implies for our revenue-leakage check — because a
> counting error in one direction lets a hidden passenger through, and a
> counting error in the other direction accuses an honest crew. We tested on
> held-out COCO validation photographs, filtered to van-like occupancy and
> framing, plus controlled degradations standing in for cabin conditions, and
> we report counting error, false-alarm and detection rates, and the
> confidence-threshold trade-off that justifies our chosen setting. The
> figures characterise the detector and our reconciliation rule; in-cabin
> accuracy awaits the van camera unit.
