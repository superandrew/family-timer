# FamilyTimer — v1 specification

FamilyTimer limits a child's daily time on a Mac and lets parents grant extra time from
Telegram. It is a fork of [minecraft-timer](https://github.com/linaspurinis/minecraft-timer)
by Linas Purinis (MIT), itself based on [minertimer](https://github.com/soferio/minertimer)
by Soferio Pty Limited. From minecraft-timer it keeps the idea, the Telegram approval flow,
the LaunchDaemon install and the `KEY=VALUE` config format; the code is rewritten in Swift
and extended from "Minecraft only" to "the whole Mac".

Status: design. Nothing below is implemented yet unless a task in `docs/tasks/` says so.

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
- Protection against someone who knows an administrator password. The child account must be
  a **standard** user; with an admin password every local control can be removed.

## 3. Architecture

Three parts, one Swift package:

| Part | Runs as | Job |
|---|---|---|
| `FamilyTimerCore` | library | Pure logic, no system calls: config, durations, commands, day ledger, policy state machine, Telegram JSON. Fully unit-tested. |
| `familytimerd` | root, LaunchDaemon (`KeepAlive` true) | The authority. Measures active time, keeps state, talks to Telegram and Healthchecks, decides when to lock, logs the child out if the agent is missing. |
| `FamilyTimerAgent` | the child, LaunchAgent (Aqua sessions only) | The face. Menu bar countdown, warnings, the "Ask for more time" dialog, the screen lock and re-lock. |

### 3.1 Trust model

The daemon never trusts the agent for anything that matters.

- **Counting** is done by the daemon alone: a second counts when the console user is the
  child and the system HID idle time is below `IDLE_THRESHOLD`. Both are readable by root
  (`SCDynamicStoreCopyConsoleUser`, IOKit `IOHIDSystem` → `HIDIdleTime`). A locked screen
  produces no input, so it becomes idle and stops counting by itself.
- The agent can only **ask** (a time request, which still needs a parent) and **report** that
  it is alive. A forged message from the child can at most send a request to the parents.
- If the budget is over, the child is the console user and active, and the agent has not
  confirmed a lock within `GRACE_TIME` + 30 s, the daemon logs the child out
  (`launchctl bootout gui/<uid>`). Killing the agent therefore only makes things worse.
- The child cannot change the clock, unload the daemon or edit the config: all need admin.

### 3.2 Locking

The agent locks the screen with `SACLockScreenImmediate` from the private
`login.framework` (loaded with `dlopen`). It is private API: task 0S1 verifies it on the
macOS version in use before anything depends on it. Fallback when it fails: the daemon logs
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
| `locked` | screen locked and re-locked | `open` on `/extra`, `/studio`, `/unlock`, a late Approve, or a new day |

`/lock` forces `locked` until midnight or `/unlock`, whatever the budget.
A Telegram approval that arrives after the lock still grants the time and unlocks.

### 4.3 Telegram

- One bot per Mac (two daemons polling the same bot steal each other's updates).
  Both parents are in one group with the bot; `TELEGRAM_CHAT_ID` is that group.
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

## 5. Configuration

File `/Library/Application Support/FamilyTimer/config`, owner root, mode 0600.
`KEY=VALUE` lines as in minecraft-timer; `#` comments; values may be quoted; unknown keys are
ignored, so an old minecraft-timer config still loads.

| Key | Default | Meaning |
|---|---|---|
| `CHILD_USER` | required | short macOS user name of the child |
| `TIME_LIMIT` | 3600 | weekday budget, seconds |
| `WEEKEND_TIME_LIMIT` | 3600 | Saturday and Sunday budget, seconds |
| `EXTENSION_TIME` | 1800 | seconds asked by the "Ask for more time" button |
| `IDLE_THRESHOLD` | 120 | seconds without input after which time stops counting |
| `GRACE_TIME` | 300 | seconds the child may continue after the budget ends |
| `APPROVAL_TIMEOUT` | 600 | seconds a request waits for an answer |
| `TELEGRAM_BOT_TOKEN` | "" | empty disables Telegram |
| `TELEGRAM_CHAT_ID` | "" | group chat id (negative number) |
| `PARENT_USER_IDS` | "" | comma-separated Telegram user ids allowed to command; empty = anyone in the chat |
| `HEALTHCHECK_URL` | "" | empty disables the heartbeat |
| `HEALTHCHECK_INTERVAL` | 300 | seconds |

## 6. Files

| Path | Owner / mode |
|---|---|
| `/usr/local/libexec/familytimer/familytimerd` | root, 0755 |
| `/usr/local/libexec/familytimer/FamilyTimerAgent` | root, 0755 |
| `/Library/LaunchDaemons/io.github.familytimer.daemon.plist` | root:wheel, 0644 |
| `/Library/LaunchAgents/io.github.familytimer.agent.plist` | root:wheel, 0644 |
| `/Library/Application Support/FamilyTimer/config` and `state.json` | root, 0600 |
| `/var/log/familytimer.log` | root |

`install.sh` and `uninstall.sh` (run with `sudo`) build in release mode, copy, set modes and
load both jobs. The uninstaller also re-enables nothing and deletes nothing outside these
paths. The bundle id prefix is a placeholder until the project has a public name.

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
| 0S1 | S | Spike: verify `SACLockScreenImmediate`, `HIDIdleTime`, console user on the macOS in use |
| 005 | S/L | `Policy`: the phase machine of 4.2 as a pure function `(state, event, now) -> (state, [action])` |
| 006 | S | `familytimerd`: tick loop, persistence, Telegram client, Healthchecks, logout fallback |
| 007 | S | `FamilyTimerAgent`: menu bar, dialogs, lock loop, socket client |
| 008 | S/L | `install.sh`, `uninstall.sh`, plists, README |
| 009 | S | End-to-end test on a throw-away standard user, in dry-run first |

Every enforcement path gets a `DRY_RUN=1` mode that logs instead of locking or logging out.

## 8. Open questions

- Does `SACLockScreenImmediate` still work on macOS 27? (task 0S1)
- XCTest needs Xcode, not only the Command Line Tools: confirm Xcode is installed on the
  build Mac.
- Project name and bundle id before publishing.
- Healthchecks while the Mac sleeps (4.4).
