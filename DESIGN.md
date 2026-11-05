# Design

This is the design for the iPhone app. It replaces every earlier design note. Where this file and an older document disagree, this file wins.

The full set of screens is in `docs/design/adam-app-design.html`. Open it in a browser. The Theme switch at the top flips every screen between light and dark. `docs/design/build_design.py` regenerates it.

## What the product is

- A smart speaker with two plugs.
- You talk to it and it does things: buy this, research this, show me how this looks, did anything happen, where are my keys.
- It works with most smart home gear, but it is not only a smart home product.
- Alexa, Google and Apple limit what you can do to what the company allows. This one is as polished as they are, but you use it how you see fit.
- It acts without being asked. Examples: you run out of groceries, you sit at your desk and focus mode turns on.

## What the app is for

The speaker is the main way in. The app covers everything the speaker cannot:

1. See what is happening at home from anywhere.
2. Approve or decline things that need you.
3. Send things to it: text, voice, photos, links, PDFs.
4. Set it up and control it: accounts, cards, devices, permissions, people, routines.

## Structure

- **Main screen.** Nearly empty, with the message box at the bottom. Three chips at the top left (needs you, working, done) each open a short list. A group with nothing in it is not shown. Two icons at the top right open Home and Settings.
- **A task.** Each request has its own conversation. Open it from a list. The header and message box are frosted over the thread.
- **Home.** Who is home, devices, things like keys, today's events.
- **Settings.** Connections, Home (People, Routines, Things), Permissions, You.
- No tab bar. No sidebar. No endless single thread. No app name in the interface. The launch screen and notifications use the A mark only.

## Look

| | Light | Dark |
| --- | --- | --- |
| Background | #f5f5f6 | #0d0e10 |
| Card | #ffffff | #17181b |
| Item | #f5f5f6 | #0d0e10 |
| Text | #111213 | #f2f3f4 |
| Secondary text | #6b6f76 | #8d9199 |
| Line | #e4e5e8 | #26282c |
| Accent (graphite, the default) | #1a1b1e | #eceef0 |
| Warning | #b45309 | #f0a23b |
| Danger | #c2362f | #f06a62 |

- Font: Geist everywhere. Times use tabular figures.
- Type: title 28/600, screen title 24/600, card title 15/600, body 14/400, secondary 13/400, caption 12/500.
- Radii: card 18, item 12 (card padding 6, so the corners line up), button 12, small button 9, chips and the message box fully round.
- Spacing steps: 4, 8, 12, 16, 24. Screen edge padding is 16. Rows inside a card are 6 apart.
- One level of nesting: a group card with item rows inside. Controls inside a row have no box of their own.
- Frosted glass only on the header and message box, when a conversation scrolls under them. Cards are plain. Never glass on glass.
- One accent, used for buttons and the selected chip. Warning and danger show state only.
- Icons sit next to a count or a word. An icon alone is only used for Home and Settings.
- Words are plain and literal. No taglines, no mood words.

## Behaviour

- **Money.** Spending can be set to Always ask, Ask above an amount you scroll to (a wheel from £1 to £500), or Never ask. The Never ask option says what it means: purchases go through without asking.
- **People.** Modelled on Apple Home. Invite someone as a Resident or a Guest. Guests get limited access for set days and hours. Each person has their own switches. Only the owner approves spending unless that is switched on for someone.
- **Things.** Asking where something is works with or without a tag. A tag gives the exact spot. Without one, the answer is a best guess from what the home noticed, marked Estimate.
- **Status.** Shown with colour, icon and words together. Progress is visible. A failure says why and what to do.
- **Haptics.** Only for results that matter (success, error, warning) and for controls (a tick). Nothing for opening screens or lists.
- **Animation.** Follows the phone's Reduce Motion setting. Reduced means a short fade.
- **Appearance choices.** Theme, accent colour and haptics. Nothing else. Cards, spacing, fonts and corners are fixed.

## Dropped from the old app

Memory page, full history page, paired displays, import from ChatGPT or Claude, Private mode, the four colour themes, the opening-style option, the round menu button and the wheel menu, and the app name in the interface. The Done list replaces history. The two plugs have no screen of their own; they appear in Home as devices if they report anything.

## Not settled

- Whether the hardware can notice enough to make the keys estimate useful. The design labels it as a guess either way.
- The icons for needs you, working and done (bell, clock, check) are not tested with people.
## Build status (2026-11-05)

Built in the app, in `OxyApp/OxyApp/Design` and `OxyApp/OxyApp/Features`: colours (light and dark, six accents), icons drawn from this design, shared parts, the main screen with real chips and lists from `/agent/state` and working Approve buttons, the message box with attach and voice, the conversation screen, the task screen, Home (from the real home data), Settings (Connections, You), Appearance, and sign in, create account and Sign in with Apple.

Not built yet: first-run setup (notification permission, speaker pairing, connecting accounts), People, Things, Routines, notification settings and quiet hours, Privacy, the speaker screen and its fix flow, share from other apps, no-internet and signed-out states, lock-screen notification buttons, the spending options with the scroll wheel, and the dot on the Home icon.

Geist (regular, medium, semibold) is bundled in `OxyApp/OxyApp/Resources/Fonts` with its licence, taken from the official v1.9.1 release. The app's font is chosen in one place, `Font.ds` in `Design/DSTokens.swift`.

Accounts, Cards, Saved logins and Account still open the old screens, full screen, until they are restyled. The Permissions page is not in Settings yet. The old main screen and its helpers are still in the project but no longer used.

Run it with launch environment `OXY_DEBUG_AUTOLOGIN=1`, plus `OXY_DEBUG_BOARD=sample` and `OXY_DEBUG_HOME=sample` to fill the screens without a server.
