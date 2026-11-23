# FamilyTimer — v1 specification

FamilyTimer limits a child's daily time on a Mac and lets parents grant extra time from
Telegram. It is a fork of [minecraft-timer](https://github.com/linaspurinis/minecraft-timer)
by Linas Purinis (MIT), itself based on [minertimer](https://github.com/soferio/minertimer)
by Soferio Pty Limited. From minecraft-timer it keeps the idea, the Telegram approval flow,
the LaunchDaemon install and the `KEY=VALUE` config format; the code is rewritten in Swift
and extended from "Minecraft only" to "the whole Mac".

Status: v1 in daily use on two family Macs; the usage log (section 9) is in progress. Section 7
says which task built what.

## 1. Goals (v1)

1. A daily budget of active time per child account (weekday and weekend values).
2. Warnings at 5 and 1 minute before the end.
3. When the budget is over: a dialog with **Ask for more time**. The request reaches the
   parents on Telegram with **Approve** / **Deny** buttons.
4. If denied, not answered in time, or not asked: the screen is locked, and it is locked again
   every time the child unlocks it, until midnight or until a parent grants time.
5. Parent commands on Telegram, all optional: `/status`, `/extra 30`, `/studio 2h`,
   `/lock`, `/unlock`, `/help`.
6. A heartbeat to Healthchecks.io so the parents learn when the Mac stops reporting.
7. No network filtering, no VPN, no proxy: FamilyTimer never touches network traffic.
   Its only network use is outbound HTTPS to `api.telegram.org` and the Healthchecks URL.
8. Zero running cost: Telegram bots and the Healthchecks.io Hobbyist plan are free.

## 2. Non-goals (v1)

- Per-app allowlists or blocklists. Browsers serve both school and fun, so v1 works on time,
  not on apps. `/studio` covers homework.
- Web filtering, activity reports, screenshots, location.
- iOS or Android. Windows and Linux.
- More than one child per Mac. Each child has a Mac; another child's account on the same Mac
  is not controlled (disable it, or give it no login, if that matters).
- Protection against someone who knows an administrator password. The child account must be
  a **standard** user; with an admin password every local control can be removed.

## 3. Architecture

Three parts, one Swift package:

| Part | Runs as | Job |
|---|---|---|
| `FamilyTimerCore` | library | Pure logic, no system calls: config, durations, commands, day ledger, policy state machine, Telegram JSON. Fully unit-tested. |
| `familytimerd` | root, LaunchDaemon (`KeepAlive` true) | The authority. Measures active time, keeps state, talks to Telegram and Healthchecks, decides when to lock, logs the child out if the agent is missing. |
| `FamilyTimerAgent` | the child, LaunchAgent (Aqua sessions only) | The face. Menu bar countdown (with ⛏ Minecraft left while the game runs; the menu lists time left, Minecraft left, study time and today's top 3 apps, lines computed by the daemon), warnings, the "Ask for more time" dialog, the screen lock and re-lock. |

### 3.1 Trust model

The daemon never trusts the agent for anything that matters.

- **Counting** is done by the daemon alone: a second counts when the console user is the
  child and the system HID idle time is below `IDLE_THRESHOLD`. Both are readable by root
  (`SCDynamicStoreCopyConsoleUser`, IOKit `IOHIDSystem` → `HIDIdleTime`). A locked screen
  left alone becomes idle and stops counting by itself. Input on the lock screen (mouse,
  typing the password) does reset `HIDIdleTime` (task 0S1), so someone fiddling with a
  locked Mac counts as active; the console user stays the child while the screen is locked.
  Only the phase `open` counts (4.2), so in `locked` this does not matter; in `open` it can
  only count against the child.
- **The lock state** is read by the daemon itself from the IORegistry: `IOConsoleUsers`, the
  entry whose `kCGSSessionUserIDKey` is the child's uid has `CGSSessionScreenIsLocked = true`
  only while the lock screen is up (verified in 0S1, readable without root). The agent's
  `locked` message is informational: a script that fakes it changes nothing.
- The agent can only **ask** (a time request, which still needs a parent) and **report** that
  it is alive. A forged message from the child can at most send a request to the parents.
- While the phase is `locked`, the daemon checks the lock state at every tick. If the child is
  the console user and active, at least 30 s have passed since the lock (or the last logout),
  and the screen was not seen locked in the last 30 s, the daemon logs the child out
  (`launchctl bootout gui/<uid>`). Killing the agent therefore only makes things worse.
  A new login while locked (after a restart, for example) waits 90 s instead, the time for
  the daemon to restart a missing agent; an agent that connects gets 30 s to lock (card 017).
- The child cannot change the clock, unload the daemon or edit the config: all need admin.

### 3.2 Locking

The agent locks the screen with `SACLockScreenImmediate` from the private
`login.framework` (loaded with `dlopen`). It is private API: task 0S1 verifies it on the
macOS version in use before anything depends on it. Verified on macOS 26.6.2, 26.7.1 and 27.0.1:
the symbol resolves, the call returns 0 and locks the session (also when run inside the
child's session with `launchctl asuser`, as the agent will be). Fallback when it fails: the daemon logs
the child out. While the phase is `locked`, the agent checks every 3 s and locks again
whenever the session is unlocked (the Qustodio-style loop that works with teenagers).
Parents can still log in with their own account from the login window.

### 3.3 Daemon ↔ agent

A Unix domain socket at `/var/run/familytimer.sock` (mode 0666, owner root). One JSON
object per line. Agent → daemon: `hello` (with uid), `heartbeat`, `request_time`,
`locked` (lock confirmed). Daemon → agent: `state` (remaining seconds, phase, warnings due),
`show_expired_dialog`, `request_result` (approved seconds or denied), `lock`.
The daemon ignores messages from a uid other than the configured child.

## 4. Behaviour

### 4.1 The day

- The day changes at local midnight (`Calendar.current`). A new day resets `used`, `extra`,
  any `/studio` window and any `/lock`.
- Budget of the day = `TIME_LIMIT` on Monday–Friday, `WEEKEND_TIME_LIMIT` on Saturday and
  Sunday (`Calendar.isDateInWeekend`).
- `remaining = max(0, budget + extra − used)`.
- The daemon ticks every 15 s and persists the ledger to
  `/Library/Application Support/FamilyTimer/state.json` (root, 0600) at every tick, so a
  reboot does not reset the day.

### 4.2 Phases

| Phase | Meaning | Leaves to |
|---|---|---|
| `open` | budget left, or a `/studio` window is running | `grace` when remaining hits 0 |
| `grace` | budget over; dialog shown; the child may keep going for `GRACE_TIME` (default 300 s) | `pending` on Ask; `locked` at grace end |
| `pending` | request sent to Telegram, waiting up to `APPROVAL_TIMEOUT` (default 600 s); child still inside until grace ends | `open` on Approve; `locked` on Deny, timeout or grace end without answer |
| `locked` | screen locked and re-locked | `open` on `/extra`, `/studio`, `/unlock`, an Approve, time coming back (a higher limit), or a new day |

`/lock` forces `locked` until midnight or `/unlock`, whatever the budget.
A Telegram approval that arrives after the lock still grants the time and unlocks.

Rules fixed by task 005 (`Policy.reduce`, the tests are the reference):

- Only `open` counts. Grace is not charged to the extra time a parent then grants, and
  a locked screen never counts.
- The child can ask in `grace` and, since task 012, in `locked`: when the child unlocks the
  screen, the agent shows a small window for 15 s with "Ask for more time", then locks again
  (5 s with nothing to ask; the window at most once a minute). One request at a time.
- Since task 018 the child can also ask in `open` during the last 15 minutes
  (`Policy.askEarlyWindow`), from the menu or the 5- and 1-minute warnings; not during a
  studio window. The parents' message says how much is left. Approved: the extra is added
  and nothing else changes. If the time runs out while waiting, the phase goes to `pending`
  (or `grace` if the request already timed out).
  After a Deny no request until midnight or a parent's `/extra`, `/studio`, `/unlock`.
  No request under `/lock`. Without a Telegram token the request is refused at once.
- A request survives the lock, so a late Approve works; a late Deny changes nothing.
  `/extra`, `/studio` and `/lock` cancel an open request.
- `/lock` wins: `/extra`, `/studio` and a late Approve add time but do not unlock while it
  holds. `/unlock` with no time left (and no `/studio`) leaves the child locked.
- Midnight resets the day whatever the phase: it cancels an open request and unlocks.

### 4.3 Telegram

- One bot per Mac (two daemons polling the same bot steal each other's updates). With
  several children, all the bots and both parents share **one group**;
  `TELEGRAM_CHAT_ID` is that group.
- A command may end with a child's name (`CHILD_NAMES`): `/extra 5m art`, `/studio 2h bea`,
  `/lock bea`, `/status art`; `/extra art 5m` works too. Without a name a command is for
  every child: `/status` gets one answer per child, `/lock` locks everyone. A bot ignores a
  command that names another child. Every answer starts with the child's name.
- The daemon long-polls `getUpdates` (timeout 25 s) all the time, not only during a request,
  and deletes any webhook at start (as minecraft-timer does).
- Commands and button presses are accepted only from `TELEGRAM_CHAT_ID`, and, when
  `PARENT_USER_IDS` is set, only from those Telegram user ids.
- Request message: "⏰ <child> has used today's time and asks for <EXTENSION_TIME> more
  minutes." with buttons `approve:<requestID>` / `deny:<requestID>`. After a press the message
  is edited to show who decided and the outcome.

| Command | Effect | Reply |
|---|---|---|
| `/status` | — | used, budget, extra, remaining, phase, studio end if any |
| `/extra <d>` | adds `d` to today's `extra`; unlocks if locked | new remaining |
| `/studio <d>` | counting paused for the next `d` of wall-clock time; unlocks if locked | end time |
| `/lock` | phase `locked` until midnight or `/unlock` | confirmation |
| `/unlock` | cancels `/lock`; if no budget is left the child is locked again at the next tick | confirmation and remaining |
| `/help`, `/start` | — | list of commands |

`<d>` is a duration: `30` (minutes), `30m`, `45min`, `2h`, `1h30`, `1h30m`; from 1 minute to
12 hours. Commands may carry a bot suffix (`/extra@family_bot 30`).

### 4.4 Healthchecks

Every `HEALTHCHECK_INTERVAL` seconds (default 300) the daemon sends a GET to
`HEALTHCHECK_URL`, and once more right after wake from sleep. When the URL is empty the
feature is off.
Known trade-off: a Mac that is asleep or off also stops pinging. The parents choose the
period and grace on Healthchecks.io (suggested: period 5 min, grace 60 min) and accept that
an alert means "the Mac is not reporting", not necessarily "tampering". To revisit after
some weeks of real use.

### 4.5 Closing apps: Minecraft and study time

- Minecraft has its own daily limit (`MINECRAFT_LIMIT`, `WEEKEND_MINECRAFT_LIMIT`) inside
  the daily budget. Its time is the usage log's: only while Minecraft is in front and the
  child is active. Minecraft Java has no bundle id (a bare `java`, also under Lunar Client):
  the agent recognises it by its path and reports it as `com.mojang.minecraft`.
- During a study window (`/studio`) Minecraft and every app classified 🎮 games or 💻 coding
  are closed. Browsers and sites are never closed: sites cannot be blocked without network
  filtering (goal 7).
- The daemon decides (`Blocking.reason`) at every tick and sends `close` to the agent, at
  most every 10 s per app. The agent shows why and quits the app (forced after 5 s).
- Minecraft is also checked by the daemon in the process list, in front or not: if it is
  still running a minute after `close`, the daemon kills it as root.
- The agent warns at 5 and 1 minute of Minecraft left, when the game is open.
- `/minecraft 15m` (or `/mc`) adds Minecraft time for today; `/extra` does not. `/status`
  shows the Minecraft line. Holidays are not known: weekend means Saturday and Sunday.

## 5. Configuration

File `/Library/Application Support/FamilyTimer/config`, owner root, mode 0600.
`KEY=VALUE` lines as in minecraft-timer; `#` comments; values may be quoted; unknown keys are
ignored, so an old minecraft-timer config still loads.

| Key | Default | Meaning |
|---|---|---|
| `CHILD_USER` | required | short macOS user name of the child |
| `TIME_LIMIT` | 3600 | weekday budget, seconds |
| `WEEKEND_TIME_LIMIT` | 3600 | Saturday and Sunday budget, seconds |
| `MINECRAFT_LIMIT` | 0 | Minecraft seconds per weekday, inside the daily budget; 0 = no limit |
| `WEEKEND_MINECRAFT_LIMIT` | MINECRAFT_LIMIT | Minecraft seconds on Saturday and Sunday |
| `EXTENSION_TIME` | 1800 | seconds asked by the "Ask for more time" button |
| `IDLE_THRESHOLD` | 120 | seconds without input after which time stops counting |
| `GRACE_TIME` | 300 | seconds the child may continue after the budget ends |
| `APPROVAL_TIMEOUT` | 600 | seconds a request waits for an answer |
| `TELEGRAM_BOT_TOKEN` | "" | empty disables Telegram |
| `TELEGRAM_CHAT_ID` | "" | group chat id (negative number) |
| `PARENT_USER_IDS` | "" | comma-separated Telegram user ids allowed to command; empty = anyone in the chat |
| `HEALTHCHECK_URL` | "" | empty disables the heartbeat |
| `HEALTHCHECK_INTERVAL` | 300 | seconds |
| `CHILD_NAMES` | CHILD_USER | comma-separated names the parents use in commands; the first is shown in messages |
| `LANGUAGE` | en | language of every text the child and the parents see: `en` or `it` |

## 6. Files

| Path | Owner / mode |
|---|---|
| `/usr/local/libexec/familytimer/familytimerd` | root, 0755 |
| `/usr/local/libexec/familytimer/FamilyTimerAgent` | root, 0755 |
| `/Library/LaunchDaemons/com.2manyclicks.familytimer.daemon.plist` | root:wheel, 0644 |
| `/Library/LaunchAgents/com.2manyclicks.familytimer.agent.plist` | root:wheel, 0644 |
| `/Library/Application Support/FamilyTimer/config` and `state.json` | root, 0600 |
| `/var/log/familytimer.log` | root |

`install.sh` and `uninstall.sh` (run with `sudo`) build in release mode, copy, set modes and
load both jobs. The uninstaller also re-enables nothing and deletes nothing outside these
paths. Bundle id prefix: `com.2manyclicks.familytimer` (launchd labels `com.2manyclicks.familytimer.daemon` and `.agent`).
It is written in one place per language: `FamilyTimer.bundleID` in `FamilyTimerCore` and
`BUNDLE_ID` at the top of `install.sh` / `uninstall.sh`; the plists are generated from a
template, so a fork changes the id in those two places only.

## 7. Plan

Tasks live in `docs/tasks/`. `L` = written by the local model with llm-dev, then reviewed;
`S` = written by the supervisor (system code, or logic too subtle to dictate).

| Task | Who | What |
|---|---|---|
| 000 | S | Swift package scaffold, `AGENTS.md`, this spec |
| 001 | L | `Config`: parse the `KEY=VALUE` file |
| 002 | L | `parseDuration` and `parseCommand` |
| 003 | L | `DayLedger`: day key, budget, ticks, extra, studio, rollover |
| 004 | L | Telegram `getUpdates` JSON decoding and parent check |
| 0S1 | S | Done (macOS 26.6.2, 26.7.1, 27.0.1). Spike: verify `SACLockScreenImmediate`, `HIDIdleTime`, console user on the macOS in use |
| 005 | S | Done. `Policy`: the phase machine of 4.2 as a pure function `(state, event, now) -> (state, [action])` |
| 006 | S | `familytimerd`: tick loop, persistence, Telegram client, Healthchecks, logout fallback |
| 007 | S | `FamilyTimerAgent`: menu bar, dialogs, lock loop, socket client |
| 008 | S/L | `install.sh`, `uninstall.sh`, plists, README |
| 009 | S | End-to-end test on a throw-away standard user, in dry-run first |
| 010 | S | Done. `bin/deploy` + `deploy/update`: install on the family Macs over SSH (7.2, `docs/DEPLOY.md`) |
| 011 | L | Done. `AgentWatch`: when to restart a missing agent and when to tell the parents |
| 012 | L | Done. Ask for more time while locked; a denial holds until midnight |
| 013 | L | Done. `UsageLog`: seconds per app and per site, per day |
| 014 | L | Done. `/app`, `/oggi`, usage replies, category buttons; locked reopens when time comes back |
| 015 | L | Done. Usage category coding |
| 016 | L | Done. Browsers are containers: 🌐, never classified |
| 017 | L | Done. A login while locked gets 90 s before the logout fallback |
| 018 | L | Done. Ask for more time in the last 15 minutes |
| 019 | L | Done. Minecraft limit: config, `/minecraft`, remaining |
| 020 | L | Done. Which app to close (Minecraft over, study time), texts, protocol |
| 021 | L | Done. Menu bar: Minecraft in the title, time and usage lines in the menu |

Every enforcement path gets a `DRY_RUN=1` mode that logs instead of locking or logging out.

### 7.1 Phases

| Phase | Tasks | Closed when |
|---|---|---|
| 1. Pure logic | 000-005, 0S1 | `FamilyTimerCore` complete; every transition of 4.2 has a test (including late Approve, `/lock`/`/unlock`, `/studio`, `/extra`, midnight); the lock-screen input case of 3.1 decided. |
| 2. Dry run on this Mac | 006-008 | Installed with `DRY_RUN=1` for a throw-away standard user on the development Mac: time counts only with real input, Telegram commands and the Approve button work, Healthchecks receives pings, locks and logouts appear only in the log. |
| 3. v1 | 009-010 | Full test without `DRY_RUN` on the throw-away user (re-lock on every unlock, logout when the agent is killed); then deployed to the family Macs and one week on the real child accounts without intervention. |

Everything is tested on the development Mac first; the family Macs come last.

### 7.2 Deploy over SSH

The supervisor deploys to the family Macs over SSH with a key the parents provide; the
parents say which Mac and which child account.

- Target account: an **administrator** account of each Mac, never the child's. Remote Login
  enabled for that account only. Every SSH key with admin access is as strong as the admin
  password (2.), so it stays off the child accounts and off shared machines.
- `bin/deploy NAME` builds a release for the target's CPU, signs it, copies it over SSH and runs
  the root updater `deploy/update`. How it works, the env file and troubleshooting:
  `docs/DEPLOY.md`.
- First on each Mac: run the 0S1 spike there (macOS version may differ) and record
  `sw_vers` and the CPU.
- Config per Mac: `CHILD_USER` and **one Telegram bot per Mac** (4.3). Bot tokens and
  Healthchecks URLs never go in the repository; `bin/deploy` reads them from
  `~/.config/familytimer/NAME.env`, outside the repo.
- `sudo`: the first install asks for the admin password and adds
  `/etc/sudoers.d/familytimer`, which lets that admin run **only**
  `/usr/local/libexec/familytimer/update` (root-owned, not writable by anyone else) without a
  password. `update` installs the files staged by `bin/deploy` in the admin's home; the child
  cannot write there. Later deploys need no password, so the supervisor deploys alone.
- The Mac must be awake: a locked Mac goes to sleep and drops SSH. Turn on "Wake for network
  access" in the energy settings, or wake it before deploying.
- Per-Mac details (host, admin, child account, CPU, macOS) live in the local file next to the
  secrets, never in the repository.
- A Mac may also run the old minertimer (`/Library/LaunchDaemons/com.soferio.minertimer_daily_timer.plist`),
  which closes Minecraft after its own daily limit. The two are independent and are kept
  together: Minecraft time also counts for FamilyTimer. `/extra` does not extend Minecraft.
  Per-app limits controlled from Telegram are a candidate for v2.

## 9. Usage per app and per site (v2, in progress)

What the children use, for the parents to see; no rules yet (they come once the parents have
seen a few weeks of data).

- The agent reports the app in front every 10 s and at every app switch (`AgentReport`). For
  a browser it adds the page's address and title, read with the Accessibility API; the
  permission is granted once per Mac by an admin (`docs/DEPLOY.md`). Without it only the app
  is known and the parents get a notice on Telegram, at most once a day.
- Every tick of active use (child at the console, not idle, not locked) adds 15 s to the app
  and, for a browser, to the site (`UsageLog`, host without `www.`). 35 days are kept in
  `usage.json`. Titles are not stored.
- `/app NAME` shows the last 7 days, `/oggi NAME` today, apps and sites apart. Something not
  yet classified gets buttons 🎮 games / 📚 study / 📺 video / 💻 coding / ▫️ other: under `/app` for the
  first five above 5 minutes, and once on its own when it passes 10 minutes in total.
  Browsers are never asked about and show 🌐: their time is classified through the sites.
- Trust: the report comes from the child's session, so a child who writes to the socket can
  lie about it. Good enough to look at; rules that close apps will check the process list.
- Next: per-category limits (for example games), decided by the parents with the data.

## 8. Open questions

- Re-run the 0S1 spike (`tools/spike0s1.swift`) after every major macOS update (`SACLockScreenImmediate` is private).
- Project name before publishing (the bundle id is fixed: `com.2manyclicks.familytimer`).
- Healthchecks while the Mac sleeps (4.4).
