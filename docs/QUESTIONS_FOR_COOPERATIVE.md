# Questions for the Cooperative

*For any dispatcher or conductor at the terminal. Four questions, about a
minute each. No IT knowledge needed.*

*Para sa dispatcher o konduktor sa terminal. Upat ka pangutana, mga usa ka
minuto matag usa.*

---

### 1. Paying the conductor

**English:** When passengers pay the conductor on the van, do some of them
pay through GCash instead of cash? If yes, how does the conductor turn that
over to the office at the end of the day — counted together with the cash,
or separately?

**Tagalog:** Kapag nagbabayad ang mga pasahero sa konduktor sa loob ng van,
may nagbabayad ba sa pamamagitan ng GCash imbes na cash? Kung oo, paano ito
ibinibigay ng konduktor sa opisina sa katapusan ng araw — sinasama ba sa
cash, o hiwalay ang bilang?

**Bisaya:** Kung mobayad ang mga pasahero sa konduktor sulod sa van, naa bay
mobayad pinaagi sa GCash imbes nga cash? Kung naa, unsaon pag-turnover sa
konduktor niini sa opisina sa pagkahuman sa adlaw — iapil ba sa cash, o lahi
ang pag-ihap?

*Why we ask:* the system tracks how much each conductor hands over. If GCash
money goes straight to the conductor's phone, the office needs to see it as
a separate line, otherwise the totals won't match.

Answer: ______________________________________________________________

---

### 2. Cancelling a booking

**English:** If a passenger books a seat and then changes their mind, until
what time before the van leaves should they still be allowed to cancel? For
example, 1 hour before, 6 hours before, or the day before?

**Tagalog:** Kung nag-book ang pasahero ng upuan tapos nagbago ang isip
niya, hanggang anong oras bago umalis ang van pwede pa siyang mag-cancel?
Halimbawa, 1 oras bago, 6 na oras bago, o isang araw bago?

**Bisaya:** Kung nag-book ang pasahero og lingkuranan unya nausab ang iyang
hunahuna, hangtod unsang orasa sa dili pa mobiya ang van pwede pa siya
mo-cancel? Pananglitan, 1 ka oras sa dili pa, 6 ka oras sa dili pa, o usa ka
adlaw sa dili pa?

*Why we ask:* the app needs a cut-off time. After that time, the seat is
theirs whether they show up or not.

Answer: ______________________________________________________________

---

### 3. Knowing who has arrived

**English:** Before a van leaves, would it help you to see on a screen which
booked passengers are already at the terminal and which ones haven't shown
up yet? For example, so you could give away the seat of someone who isn't
coming?

**Tagalog:** Bago umalis ang van, makakatulong ba sa inyo kung makikita
ninyo sa screen kung sino sa mga nag-book na pasahero ang nasa terminal na
at sino ang hindi pa dumarating? Halimbawa, para maibigay ninyo sa iba ang
upuan ng hindi darating?

**Bisaya:** Sa dili pa mobiya ang van, makatabang ba ninyo kung makita ninyo
sa screen kinsa sa mga nag-book nga pasahero ang naa na sa terminal ug kinsa
ang wala pa moabot? Pananglitan, aron mahatag ninyo sa uban ang lingkuranan
sa dili na moabot?

*Why we ask:* the app can let passengers tap "I'm here" when they arrive.
We want to know if that's actually useful for dispatch, or if it's just
extra work for passengers.

Answer: ______________________________________________________________

---

### 4. Where passengers wait

**English:** When passengers are waiting for a van, where are they usually?
Only inside the terminal, or also nearby — the parking area, the stores
across the road, the mall? Roughly how far away might someone be while
still "waiting for the van"?

**Tagalog:** Kapag naghihintay ang mga pasahero ng van, saan sila
karaniwang nandoon? Sa loob lang ng terminal, o pati sa malapit — sa
parking, sa mga tindahan sa kabilang kalsada, sa mall? Mga gaano kalayo ang
maaaring kinaroroonan ng isang tao habang "naghihintay ng van" pa rin?

**Bisaya:** Kung maghulat ang mga pasahero og van, asa man sila kasagaran?
Sulod ra sa terminal, o apil sa duol — sa parking, sa mga tindahan sa pikas
dalan, sa mall? Mga unsa ka layo ang mahimong naa ang usa ka tawo samtang
"naghulat pa og van"?

*Why we ask:* the "I'm here" button only works when the phone is near the
terminal. If we make the area too small, honest passengers waiting across
the road get rejected. Too big, and someone at a mall a kilometre away
could press it.

Answer: ______________________________________________________________

---

*What the answers decide:* Q1 → how the revenue report separates cash from
GCash · Q2 → the cancellation cut-off (`cancel_cutoff_hours` policy) ·
Q3 → whether dispatch will actually use the "I'm here" heads-up ·
Q4 → the check-in geofence radius (`default_geofence_radius_m` policy).
