# Changelog

Every TestFlight build bumps the version; the section for it becomes the build's "What to Test" notes.

## 0.14.1 — 2026-10-25

- Subscriptions and bills show the merchant's logo, like their charges do: on a subscription's page and in the Leaks rows, including cancelled ones. They used to show the first letter of the name. A merchant without a logo shows its category icon.
- Logos load once and stay. Poise keeps each one on the phone after the first download, so scrolling and reopening the app show them right away, offline too, instead of fetching them again.

## 0.14.0 — 2026-10-24

- Subscriptions is no longer a category. A category says what a charge was for. Whether it repeats is a separate answer: a subscription you can cancel, or a bill you have to pay. So a gym can be Health and a subscription at the same time.
- Two new categories: Entertainment (Netflix, Spotify, Disney+, Peacock, Nintendo) and Tech (Apple, apps, devices). Charges that were under Subscriptions moved to where they belong, and Amazon Prime and Uber One went back to Shopping and Transport.
- A charge that repeats now shows "It repeats monthly" under its category, with Subscription, Bill or Just purchases to pick from.
- A subscription's page in Leaks shows its category, and "File under" changes it for every charge from that merchant.
- Bills are worked out from what the merchant is (rent, utilities, phone, internet, insurance, loans), not from the category. A gym filed under Health used to be called a bill.

## 0.13.1 — 2026-10-23

- Amazon no longer says it signed you out every time you open the app. After a restart, Poise was checking the sign-in on the wrong page — one that hadn't loaded anything yet — so every check counted as signed out even though your Amazon session was fine. It now checks the page it actually read.
- A slow Amazon page is retried later instead of being taken as a sign-out. Only Amazon's own sign-in form counts as signed out.

## 0.13.0 — 2026-10-23

- Pull to refresh is nearly instant. It used to wait for each bank in turn to answer, close to a minute in all (Barclays alone took about 35 seconds). Now the pull asks every bank at once and lets go in about a second. New charges slide in a few seconds later as each bank sends them.
- Poise refreshes in the background about once an hour, so the app opens with the latest charges already there. iOS picks the exact times based on how often you open the app.
- Apple Card and Amazon no longer hold up a pull. They update on their own and appear when they're ready.

## 0.12.2 — 2026-10-23

- Charges show on the day they happened, where you are. Some banks date charges by their own clock: Robinhood uses UTC, so dinner at 7:30 pm used to show up as tomorrow's. Poise now uses the time the bank authorised the charge, in your time zone, and falls back to the bank's date only when no time is given.
- A charge never shows on a later day than when Poise first saw it, and it keeps that day when it settles.
- Past charges are fixed too. Fifteen from the last three months moved back to the evening they happened.

## 0.12.1 — 2026-10-23

- On Home, a card past last month's total kept a thin bar but drew it thick. The bar is thin again, and only the small mark where last month ended stands taller.

## 0.12.0 — 2026-10-23

- Sixteen finishes for your cards, up from eight. The new ones are Rose, Copper, Midnight, Lagoon, Sage, Violet, Ruby and Sunset. Look & name now groups them in rows: metals, blues, greens and warm colours.
- Pick the chip, too: Gold, Silver, Rose or Black. Each option shows the chip on your card's finish. A card whose chip you haven't picked keeps the one that comes with its finish, and "Back to the bank's look" resets the chip with everything else.
- Putting a card back on the default under "How you pay it" now sticks. Before, the card kept the old choice.

## 0.11.0 — 2026-10-22

- Your cards look like cards. Each one has a finish of its own with a fine grain, a soft light across it that moves as you tilt your phone, a lit edge and a shadow in its own colour, plus a chip and the last four along the bottom. Robinhood is gold, Apple Card titanium, Prime Visa ocean; cards Poise can't place get one of the deeper finishes, and two cards with the same name never get the same one.
- Look & name: give any card a name of your own and pick from eight finishes, with a live preview. It's at the top of "This card" on a card's page, or press and hold a card on Home. The name shows everywhere that card does, and "Back to the bank's look" undoes it.
- The ® and ™ banks put in card names are gone.
- The cards on Home now show last month's total next to this month's, with a thin bar for how far into it you are. Past it, the bar runs full with a small mark where last month ended.
- A light tap as you swipe between cards on a card's page.
- Where: a little more room between the period tabs and the month under them.

## 0.10.1 — 2026-10-22

- Pulling to refresh now brings in today's charges. A pull asks your banks for anything new, but the new charges come back a few seconds later, and the app used to reload before they arrived, so the pull looked like it did nothing. It now waits a moment for them, and if a bank is slow they still appear once they land, up to a minute later.
- "As of" under the verdict now shows when your banks were last checked, not when one last had something new. A pull that found nothing used to leave it reading hours ago.
- Charges some cards date by UTC (Robinhood, for one) no longer show up as tomorrow's when you spend in the evening. They count as today's, so they're in this month's totals right away.

## 0.10.0 — 2026-10-22

- Your cards are on Home. Under the verdict, each card is drawn in its own colours with its last four and what went on it this month; tap one to open it.
- A card's page now shows what it was spent on, not just its settings. The card sits at the top — what's owed, and what's due when — and your other cards are a swipe away. Below it: the week, month or year on that card alone, how it compares with the one before, where it went as one coloured bar split by category, the merchants it was spent at, and every charge by day. Tap a category for its own page on that card; a chip there widens it back to every card. How you pay it and the rest of the card's settings are at the bottom.
- Fixed a crash. When a request failed — a dropped connection mid-refresh, a save that didn't go through — the code meant to show the error called itself instead, over and over, until the app ran out of room and closed. It now shows the error.

## 0.9.9 — 2026-10-21

- Signing back in to Amazon now shows you the page that actually needs it. Amazon was letting Poise onto the payments page but stopping it at each order's own page, and the sign-in sheet opened the payments page — which went straight through, so the sheet closed having fixed nothing and the next read failed the same way. The sheet now opens the order Amazon stopped on, so whatever it asks — a password again, a code, a robot check — is in front of you.
- Orders are opened at a person's pace rather than one straight after another, which is what Amazon's robot checks look for.
- When a read is stopped, the line under "Contents read" says which kind of check it was.

## 0.9.8 — 2026-10-21

- Reading what was in an Amazon order goes straight to the page Amazon now keeps it on, and waits for the order itself — or a sign-in — rather than taking the first text that stops moving.
- When Amazon wants a fresh sign-in before showing an order, Poise now notices. It was asking the wrong web view — the one showing the payments page, not the one that had opened the order — so the request went unseen and the read simply came back empty.
- "Contents read" counts what was actually read; re-reading an order already on file to follow a return was being counted as a failure. When a read does fail, the reason now sits under the figure.

## 0.9.7 — 2026-10-21

- Fixed the real reason recent Amazon orders weren't filling in. Reading the payments page walks back page by page until it runs out, and Amazon's last page isn't the payments page — Poise was taking that as "the session has gone", telling you to sign in again, and giving up before it read what was in any of the orders. So the order numbers matched (103 of 110) while the item names never arrived. The end of a list is now the end of a list.
- Each half of a check reports its own result. The Amazon page shows "Orders seen" and "Contents read" separately, because they fail for different reasons and a figure for one says nothing about the other.

## 0.9.6 — 2026-10-21

- Amazon charges are being read again. Amazon redesigned its payments page around the middle of the month and started writing the date as "Oct 21, 2026" instead of "October 21, 2026" — and an order whose date Poise can't read is skipped, so every charge after the redesign arrived with nothing attached. Both spellings work now, as do both page layouts, since Amazon still serves the old one in places.
- A page Poise can't read no longer fails quietly. If order numbers are plainly there but none can be read, that's recorded as a page that has changed shape rather than a page with nothing on it — the two looked identical from the outside, which is why this went unnoticed for a week.
- Pull to refresh and the next check will fill in everything missed.

## 0.9.5 — 2026-10-09

- Each card decides how it's paid. One toggle covered every card, which is wrong the moment two are paid differently — and it only offered two answers. A card's own page now asks for one of four: the statement balance, the whole balance, the minimum, or a set amount each month. Each names the money it would cost, and a line underneath says exactly what Next will subtract and on which day.
- The statement balance and the whole balance are separate choices because they're separate sums. A card used since its statement closed owes more than the statement says — on the Prime Visa, $4,020.25 against $6,312.73 — and paying the statement is the one that avoids interest.
- Settings keeps a default for newly linked cards. A card you haven't decided about follows it, so changing the default still moves them.
- Fixed while checking it on a real card: "the whole balance" was showing the credit still available rather than the debt — $10,715 on a card owing $1,284.

## 0.9.4 — 2026-10-09

- Signing into Amazon is now the whole of it. The sheet closes the moment you're in, and the reading carries on behind a ring on Home — "Reading your Amazon orders · 30 of 71". Nothing to wait on and nothing to come back to.
- Allowing a bank to share card due dates takes effect immediately. The refresh straight after it was being skipped by the limit that stops repeated pulls, so allowing it appeared to do nothing until something else triggered a sync — which is exactly how it felt. It now forces the read, and tries once more a few seconds later, since a bank can take a moment to attach a permission it has only just granted.
- A card whose due date has passed no longer falls out of Next. Banks keep reporting last month's date until the next statement closes, and during that gap the payment vanished from the forecast entirely — an Apple Card with $1,284 owed and a Chase card with $89 were both missing. The date rolls forward a month and the row says it's estimated.

## 0.9.3 — 2026-10-09

- Next was leaving card payments out, and now says so. The due dates it needs come from the bank, and Chase and Robinhood were refusing them — the permission was asked for as optional when the accounts were linked, so it was never granted. The refusal was being swallowed, which is why a card with thousands owed simply wasn't in the forecast and nothing explained it.
- The Next screen now names what's missing — "$6,312 owed with no due date Poise can see" — and **Allow** takes you back through your bank to grant it. One trip, and the payment appears in the forecast from then on.
- Statements are refreshed on the hourly check too, not only when you open the app, so a due date that moves is picked up on its own.
- Barclays was already giving us everything; Apple Card gives a due date and the statement is rebuilt from your charges. Those were right before and are unchanged.

## 0.9.2 — 2026-10-03

- Watching says what the money was for. A refund you're owed now shows the thing itself — "Tapo ColorPro outdoor camera" — then what was charged, to which card, and how long it's been waiting against the window it was given. A row can finally answer whether it's worth chasing.
- Poise reads the return status from Amazon rather than asking you. The order page says "Return started · your refund will be processed when we receive your item", so a refund that's in hand no longer looks like one that's gone quiet, and it stops being counted as overdue while the merchant says it's under way. Orders behind an open refund watch are re-read so the status stays current.
- "It arrived" closes the ones Poise genuinely can't see the end of — store credit, a gift card, a partial amount, or money back to a card you haven't linked. It's the fallback, not the method.

## 0.9.1 — 2026-10-03

- A refund watch now closes only on the refund it's actually waiting for. It was accepting any refund from the same shop that was at least as large, so at Amazon — where refunds are frequent — a $108.20 refund closed a watch waiting on $76.85, and Poise said money had come back that hadn't. The amount has to match now. A smaller refund is a partial one and leaves the watch open, which is the truth.
- Watches already closed on the wrong refund repair themselves: each is re-checked, and one that doesn't hold up reopens with its real age, so an overdue refund goes back to saying it's overdue.
- One refund watch per charge. A wrongly closed watch used to let a second be made for the same charge, leaving two rows waiting on the same money; the duplicates are cleared up on their own.

## 0.9.0 — 2026-10-02

- Next can look thirty days ahead. A fortnight answers "can I reach payday"; it's the wrong window for rent, a quarterly insurance bill or an annual renewal landing on the 29th — those sit just past the edge while the screen looks calm. The switch is above the chart, where you're looking, and it's remembered.
- Fourteen stays the default, because most days it's the more useful read and a month of bars is harder to scan. The bars thin their gaps at thirty so they stay legible in the same card.

## 0.8.9 — 2026-10-02

- The tab is called "Next". The screen's own title still says how far ahead it's looking, so the window is named once rather than twice — and it leaves room for that window to change.

## 0.8.8 — 2026-10-02

- Text that changes under you now resolves instead of snapping. When an Amazon order is read while you're looking at the feed, "Shopping" becomes "Naked Whey Isolate Protein" the way invisible ink clears in iMessage — the words emerging from a haze, left to right. Only an actual change animates; scrolling a row back on screen is not news, so the feed doesn't shimmer every time it moves.

## 0.8.7 — 2026-10-01

- Signing in is now the only part that needs you. The long read carries on by itself — close the sheet, or the app, and it keeps going; "Leave it running" says so. It resumes where it stopped the next time Poise is open, because it only ever reads orders that still want reading.
- Being honest about one limit: this runs while Poise is open, not while your phone is in your pocket. A web session can't be read from a sleeping app, so a sweep that was interrupted finishes on the next open or pull rather than overnight.

## 0.8.6 — 2026-10-01

- An Amazon charge now sits on the day you bought it. Amazon's own order date decides, because a card only authorises when the seller ships — and Apple Card reports no authorisation at all, so every Amazon charge on it was landing in the feed on the day it posted, days late. Chase charges were already right; this makes both agree with Amazon.
- Orders read before this update are read once more to pick up their date, so your history corrects itself rather than only new charges being right.

## 0.8.5 — 2026-09-30

- Pulling to refresh really does check Amazon. It always asked, but only if a quarter of an hour had passed, so a pull often did nothing — now it's two minutes, and it reads further back and picks up what was in more of the new orders while it's there.
- When Amazon has signed you out, Home says so and signs you back in from there. That was the reason for the trip to Settings: a dropped session failed quietly, and the only way to find out was to go looking for it.
- A dropped session is retried on its own every few hours, so if Amazon lets Poise back in the message clears itself.

## 0.8.4 — 2026-09-30

- A credit-card payment is one row again. Paying the Apple Card from Chase produces two real rows from two banks — the money leaving one and landing on the other — and the feed was showing both, which reads as paying twice. It now shows the money leaving, which is what happened, and keeps the other half for the card's own balance. The same was true of moving money into savings.
- Nothing was actually counted twice: both halves were already left out of spending, and the day totals were right. It was the feed that looked wrong.

## 0.8.3 — 2026-09-29

- Fixed the crash. When iOS woke Poise for a background Amazon check, the work was handed to it on a background thread while every part of it — the model, the web view — belongs on the main one. Assuming otherwise doesn't fail politely; it stops the app dead. That's the crash report, and it could only happen while the app wasn't in front of you, which is why it seemed to come from nowhere.
- Reading orders is much lighter. The reader now loads words only — no product photography, no ad carousels — and lets go of each page before the next. Seventy order pages in a row was enough memory for iOS to kill the app, which also arrives as a crash report. The sweep is faster for it, and the sign-in screen still looks like Amazon.

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
