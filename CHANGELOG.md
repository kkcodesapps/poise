# Changelog

Every TestFlight build bumps the version; the section for it becomes the build's "What to Test" notes.

## 0.8.2 — 2026-09-27

- Amazon charges say what they were, in the feed. "Amazon · Shopping" becomes "Amazon · Naked Whey Isolate Protein", with no tap and no wait. An order of several names the first two and counts the rest.
- A check now reads what was in every order, not just the newest few, so the names are already there when you look. That's the slow half — Amazon has no bulk view of order contents, so it's a page load each — and it has its own progress: "Reading what was in them · 30 of 71 orders". The background wake still takes only a couple, having only seconds to work with.

## 0.8.1 — 2026-09-27

- An Amazon charge now shows what was in it. Open one and Poise reads that order's own page — the item, who sold it, what it cost, and the tax — so "$76.49 at Amazon" becomes a tub of whey protein. Names are cut back to the part a person would actually say rather than Amazon's full search title.
- When an order shipped in parts, the charge says so and gives the order's real total, instead of looking like it's missing money.
- Contents are read for the order you open, and for the newest few after a check, because Amazon has no bulk view of this and charges a page load per order. What's read is kept, so it's read once.

## 0.8.0 — 2026-09-27

- Amazon checks itself now. Pull down on Home and it reads alongside your banks and Wallet; iOS also wakes Poise a few times a day for a quick look, so new Amazon charges arrive with their order without you opening anything. Neither runs more often than Amazon will tolerate — a pull skips the check if one ran in the last quarter hour, and the background wake reads a single page.

## 0.7.10 — 2026-09-27

- A second check no longer appears to lose ground. Amazon throttles a quick run of page loads, so a check straight after another can read fewer pages — but order numbers already saved stay saved, so nothing is actually lost. A page that doesn't arrive now gets a second chance instead of ending the walk, and the figure shown is the deepest read rather than the most recent one.

## 0.7.9 — 2026-09-27

- A second check no longer looks like it found less. Amazon's payments page requires a sign-in from within the last hour, so a check run later in the day gets bounced to re-authenticate part way down — and Poise was reading that bounced page as simply another page with no orders on it, then reporting a smaller number. It now recognises it, keeps everything read up to that point, and says Amazon wants you to sign in again rather than quietly reporting a shorter read.

## 0.7.8 — 2026-09-27

- A progress bar while Amazon is being read, instead of a page number. It fills as the read walks backwards and says how far it has got — "Back to Aug 14 so far" — which is the honest measure, since Amazon never says how many pages it holds. The Amazon settings page shows the same bar while a check is running.

## 0.7.7 — 2026-09-27

- The Amazon read is the same every time now. Amazon fills its list in as the page renders, and Poise was reading the moment the page differed from the last one — so it sometimes caught a half-drawn list, and the same six pages came back as 48 orders one run and 62 the next. It now waits for a page to stop changing before reading it.

## 0.7.6 — 2026-09-26

- A failed save no longer takes the rest of the read with it. Order numbers are written a charge at a time, and the first version gave up the moment one row failed — so a single hiccup part way through left most of a read unsaved, which looked exactly like a matching failure. Each row now stands on its own, retries once, and the count reported is what actually saved.

## 0.7.5 — 2026-09-26

- A refunded Amazon order no longer loses its charge. Amazon lists the same order number twice when it refunds you — once for the charge, once for the money back — and Poise was treating the number as unique, so whichever line it saw first won and the other was discarded. Both sides now keep the order, and both open it.
- Charges authorised before Amazon shipped now match. A card authorises when you place the order and Amazon charges when it ships, so the two dates can sit days apart; Poise measured from only one of them and lost anything more than a day out. It now measures from both and takes the closer.
- Said plainly on the screen: Amazon's payments page only reaches back about three months, so older charges can't be matched from it. That's Amazon's limit, not a sync that hasn't finished.

## 0.7.4 — 2026-09-26

- A deep Amazon read no longer stops a few months in. After each page it waited eight seconds for the next one and gave up quietly if Amazon was slow — which it gets after a run of quick page loads — so the read looked finished when it had only reached June. It now waits properly, takes a beat between pages, and presses again if a page doesn't turn.
- The Amazon settings page says how far back the last read reached, so a gap in your history is visibly a gap in the read rather than a mystery.

## 0.7.3 — 2026-09-26

- The Amazon reader no longer depends on where Amazon's line breaks fall. It was reading the page as a strict run of lines — day, card, amount, order — and Amazon doesn't always render it that way, so on a layout that ran the fields together it found nothing at all. It now looks for the three things it needs wherever they sit on the page, and an order takes the amount nearest it without ever borrowing one from the charge next door.
- Poise now says what it read. The screen after a check reports how many orders it found and across how many pages, and the Amazon settings page keeps it — so "found nothing" and "found plenty but matched nothing" stop looking like the same failure.

## 0.7.2 — 2026-09-25

- Amazon now finds all of your orders, not five of them. Two things were wrong. Its "Next Page" button is a label sitting beside the real control, so pressing it did nothing and Poise silently read one page and stopped — about two weeks of charges. And a charge that was still pending when Poise looked got its order number written to the pending row, which your bank then replaced with a posted one, taking the order with it.
- The read now walks back to the oldest Amazon charge that still has no order, so it fills in your history in one pass and stops as soon as it's caught up. "Check now" does the same, so a connection that fell behind is one tap from whole — it shows which page it's on, since going back a year takes a minute.
- An order number now moves from the pending charge to the posted one when it settles, so nothing is lost the moment a charge clears.

## 0.7.1 — 2026-09-25

- Fixed the Amazon sign-in giving up half way. Amazon asks for the email on one page and the password on the next, and for a moment between them the page is blank — which Poise read as "signed in", went looking for the payments page, found a signed-out one, and sent you back to the start. It now waits for a real page, checks for the password and email fields themselves rather than guessing from the address, and won't move on until it's sure twice over.
- The sign-in now has a web view to itself. Reading your orders happens in a second one behind it, sharing the same session, so nothing Poise does can navigate away from a half-typed password — and if a read does come back empty, you're returned to the page you were on rather than to the beginning.

## 0.7.0 — 2026-09-25

- Connect Amazon, and every Amazon charge gets its order. Sign in once, on Amazon's own page, inside Poise; the session stays on your phone and the only thing that ever reaches the server is an order number. Tap "See it on Amazon" on a charge and the Amazon app opens on that exact order — the thing your bank can't tell you, because Amazon only shares it with the card it co-brands.
- Poise reads one page: your Amazon payments list, which is the one place a charge's amount and date resolve to an order. No browsing history, no addresses, no saved cards, and nothing can be bought.
- It keeps up on its own. New Amazon charges arrive with their order; Amazon signs you out every few weeks and Poise says so instead of quietly going stale. Settings → Amazon shows how fresh it is, and disconnecting forgets the session and every order number with it.

## 0.6.3 — 2026-09-24

- Where compares against the whole month before, not the same stretch of it. A month in progress reads "so far · $X less than last month" — the plain comparison, instead of the "vs Aug 1–24" window nobody thinks in.
- Category rows compare the same way, so a month in progress reads lower than a finished one and the header says so once.

## 0.6.2 — 2026-09-24

- "vs Aug" now says what it actually compares. A month in progress is measured against the same stretch of the month before — September 1–24 against August 1–24 — so the label reads "vs Aug 1–24" instead of implying the whole of August. A month that's over still compares whole.
- Category rows show just the change; the comparison is stated once, above the list, which leaves room for the name and what it usually costs.

## 0.6.1 — 2026-09-24

- Tap any month in a category's history to see that month: the total, what it was against a usual month, its merchants and its charges. "This month" brings you back.

## 0.6.0 — 2026-09-24

- Apple Card, Apple Cash and Savings now keep themselves up to date in the background. A charge reaches Poise — and becomes a heads-up — without opening the app, about once an hour, as Wallet reports it.

## 0.5.1 — 2026-09-24

- No more "charged twice?" when a pending charge simply posts. A pending row and the posted row it becomes are one charge — Poise now waits for the old row to clear before saying anything, and never pairs a pending charge with a posted one.
- Two pending charges, or two posted ones, are still flagged the way they were.

## 0.5.0 — 2026-09-23

- A category now has its own history: a bar per month against what a usual month costs, over 12 months, 2 years or everything Poise has. Tap Where → a category to see it.
- It compares the right thing: once a year of history exists, this month is measured against the same month last year rather than against the average.
- "What moved" names the merchants behind the change — the ones that grew, the ones that are new, and the ones that stopped.
- "Tell me when Groceries costs more than usual" gives a category the same heads-up a tracked price has.
- Each category row in Where carries a small trend line and what it usually costs.
- Poise now keeps five years of transactions on the phone instead of thirteen months, so the history has something to show.

## 0.4.1 — 2026-09-23

- Pull to refresh on Home no longer leaves the title sitting on top of the search field. Search is now the field the design always had, right above the feed.

## 0.4.0 — 2026-09-23

- Prices only holds things that actually have a price: a plan's own charge, anything you've named, and places that charge the same every time. Amazon, Instacart, Target and the rest were never prices — they're stores, and their totals live in Spending.
- A plan and its pay-as-you-go now share one page: the plan's price chart, and the usage underneath it by month, instead of two separate runs in the list.
- The list leads with what changed, then what you're watching, and keeps the steady ones behind a single line you can open.
- Long lists collapse: a run shows its last three charges with "See all".
- A store's page says so — "a store, not a price", with the range that proves it — and offers "Follow an item from here" to name one thing and track that instead.

## 0.3.4 — 2026-09-22

- Next 14: a pending card payment reads as money leaving, like a statement, and shows once rather than on both the card and the account it was paid from. It no longer paints a false payday on the chart.

## 0.3.3 — 2026-09-22

- A credit-card payment no longer reads as income. Some banks (Robinhood) sign it positive on the card; Poise shows it plainly, without a plus or the green, whichever side it lands on and however it got classified.

## 0.3.2 — 2026-09-22

- Left the app open overnight and yesterday still said TODAY. The feed's day headers (and "since you last looked") now follow the real day, and everything dated against today — the next two weeks, this month's pace — moves on at midnight.

## 0.3.1 — 2026-09-21

- Plan and usage are now small tags beside the name (PLAN, USAGE) instead of part of it, so a label reads as a label. Cancelled and ended subscriptions carry the same kind of tag.

## 0.3.0 — 2026-09-21

- Prices has a home: the Where tab now switches between Spending and Prices, and the list holds everything you've bought twice or more — steady things with a usual price, varied things (groceries, gas, usage) with their range, and a subscription's plan as its own run.
- Price alerts live under Prices → Tracked, not in Watching. Watching stays for refunds and suspicious charges.
- A subscription can be re-filed from its page: Subscription, Bill, or Just purchases (out of Leaks).
- Plans with pay-as-you-go on top (Cursor, Anthropic) show "Plus usage · $X this month" — counted as spending, never as the subscription.
- "I cancelled this": pick the date, and the subscription drops out of the totals, Next 14 and the verdict into a Cancelled & ended section. If that merchant charges again, it goes to the top of Leaks and you get a push.
- A subscription that goes quiet for two billing periods ends on its own; if it comes back, Leaks says so.

## 0.2.1 — 2026-09-20

- A merchant's logo now shows on every one of its charges, including the ones from Apple Card, as long as any bank has supplied one.

## 0.2.0 — 2026-09-20

- Prices: what you pay for the things you buy again. A merchant that charges about the same each time (a burrito, a fill-up, a plan) is an item on its own; name a charge and every purchase with that name becomes one — the way to follow one thing from a store that sells everything.
- Each item has a page: last, usual and lowest price, the run of prices as a chart, what changed and by how much, every purchase, and "Tell me when the price moves".
- The Prices list (from the Where tab, or the Price changes tile in Leaks) shows what moved lately first, with a sparkline and the change on every row.
- A charge that belongs to an item shows "Paid 7 times · usually $29.99" one tap from its history, and naming a purchase suggests the names you've already used at that merchant.
- Tracked items raise a heads-up — and a push — when a purchase lands off the usual price.

## 0.1.4 — 2026-09-20

- Next 14 finds the bills it was missing: rent and a same-day add-on under one landlord, two Netflix plans, and pay that lands on the 15th and the last day of the month (with the Friday-before rule).
- Charges on a card show with the card's name and no longer drain checking on the day — it's the statement that does.
- Tap a bar to see that day: the row lights up and the chart says what leaves, what lands, and the balance after.
- The verdict's "ahead" now counts card statements and skips card subscriptions, matching Next 14.

## 0.1.3 — 2026-09-20

- Apple Card: the statement in Next 14 and on the card's page is now rebuilt from last month's posted charges and refunds (less anything paid since), instead of the whole current balance. Wallet only shares the due date and the minimum.

## 0.1.2 — 2026-09-19

- Next 14: the chart now follows the balance's movement instead of its size, so bills and payday show even against a large balance. Today is blue, a short day is a red stub, payday is green.

## 0.1.1 — 2026-09-19

- Where: a day's charges no longer include the next day's (charges on the 1st also counted in both months — fixed the same way).
- "Charged twice?" now means the same card, the same day, $10 or more, and not a habit — tolls and coffees stay quiet.
- Say "Both are real" twice for a merchant and Poise stops asking there; each merchant page has an "Ask about double charges" switch.
- The "charged twice" push follows the same rules.

## 0.1.0 — 2026-09-19

- First TestFlight build: the verdict, Leaks, Pace, Next 14, Where, Apple Card via Wallet, pushes, widgets, onboarding.
