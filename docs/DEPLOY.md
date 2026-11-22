# Deploy

How FamilyTimer gets onto the family Macs. Written for whoever deploys next: a person, or a
supervisor session (Claude Code, Codex, ...) that has never seen this repository. Read
`docs/SPEC.md` first for what the programs do; this file is only about installing them.

## The pieces

| On the developer's Mac | What |
|---|---|
| `bin/deploy NAME` | builds, signs, copies, then runs the updater on the target over SSH |
| `~/.config/familytimer/NAME.env` | one file per child's Mac: host, secrets, config. **Never in the repository** |

| On the child's Mac | What |
|---|---|
| `/usr/local/libexec/familytimer/familytimerd` | the daemon (root): counts time, Telegram, Healthchecks, logout |
| `/usr/local/libexec/familytimer/FamilyTimerAgent` | the menu bar app, runs in the child's session |
| `/usr/local/libexec/familytimer/update` | the root updater (copy of `deploy/update`) |
| `/etc/sudoers.d/familytimer` | lets the admin run **only** the updater without a password |
| `/Library/Application Support/FamilyTimer/config` | the config (0600, root) |
| `/Library/Application Support/FamilyTimer/state.json`, `telegram.json` | today's ledger and phase, Telegram offset |
| `/Library/LaunchDaemons/com.2manyclicks.familytimer.daemon.plist` | starts the daemon (`KeepAlive`) |
| `/Library/LaunchAgents/com.2manyclicks.familytimer.agent.plist` | starts the agent in every GUI session (`KeepAlive`) |
| `/var/log/familytimer.log` | the daemon's log (tokens are redacted) |

The agent runs in every user's session but shows nothing unless the daemon talks to it, and
the daemon only accepts the child's uid. In a parent's session the agent stays hidden.

## The env file

`~/.config/familytimer/NAME.env`, mode 0600, one per Mac. Example with fake values:

    HOST=admin@192.168.1.10
    DRY_RUN=1
    CHILD_USER=arthur
    CHILD_NAMES=Arthur,art
    LANGUAGE=it
    TIME_LIMIT=3600
    WEEKEND_TIME_LIMIT=3600
    TELEGRAM_BOT_TOKEN=123:abc
    TELEGRAM_CHAT_ID=-100123
    PARENT_USER_IDS=111,222
    HEALTHCHECK_URL=https://hc-ping.com/...

- `HOST`: the SSH target, an **admin** account of that Mac, never the child's.
- `DRY_RUN=1` (optional): log instead of locking and logging out.
- `CHILD_USER`: the child's macOS short name. `CHILD_NAMES`: the names the parents use in
  Telegram commands (`/extra 10m art`).
- `TIME_LIMIT`, `WEEKEND_TIME_LIMIT`: seconds per day. `LANGUAGE`: `en` (default) or `it`.
- `TELEGRAM_BOT_TOKEN`: one bot per Mac. `TELEGRAM_CHAT_ID`: the parents' group, shared by
  all the bots. `PARENT_USER_IDS`: who may command.
- No comments on the value lines: the whole line after `=` is the value.

`HOST` and `DRY_RUN` are for `bin/deploy`; every other line is copied as the daemon's config
(all keys: SPEC 5). The real files on the developer's Mac are named after the child (one per
Mac); list them with `ls ~/.config/familytimer/`. Read them with care: they hold bot tokens.
Never print a token, never copy one into the repository, a commit, a card or a log.

## What `bin/deploy NAME` does

1. Reads `HOST`, asks the target its CPU (`uname -m`) and builds a release for that CPU only.
2. Signs both binaries with the hardened runtime, with the local identity in
   `~/.config/familytimer/signing` when it exists (see below), ad hoc otherwise.
3. Stages binaries, `deploy/update`, the config and the `dry-run` marker in
   `~/.familytimer-stage` (mode 700) of the admin account on the target.
4. Runs `sudo -n /usr/local/libexec/familytimer/update ~/.familytimer-stage`, then deletes
   the stage.

The updater (`deploy/update`, as root):

- checks the stage belongs to the admin who ran sudo and is not writable by others;
- installs the binaries and **itself**, then the sudoers rule (first time only, checked with
  `visudo`), then the config;
- writes the daemon plist (with `DRY_RUN=1` in its environment if the marker is there),
  boots the old daemon out, waits until it is gone, bootstraps the new one;
- writes the agent plist and restarts the agent in the session at the console, waiting
  for the old one to stop first (bootstrapping too early fails with "5: Input/output error");
- prints the daemon's launchd state and the last log lines.

**The updater that runs is the one already installed**, not the one in the stage (sudoers
allows only that path). A change to `deploy/update` therefore takes effect from the
**second** deploy after it.

### First install on a new Mac

The sudoers rule is not there yet, so `sudo` needs the admin password. `bin/deploy` asks for
it when it has a terminal. A supervisor session has none: it stops with exit 2 and prints
the command for the human to run (in Claude Code, with the `!` prefix):

    ssh -t admin@HOST 'sudo bash ~/.familytimer-stage/update ~/.familytimer-stage'

Before the first install, the human enables Remote Login for the admin account only and
adds the developer's SSH key to it. Run `tools/spike0s1.swift` there once (SPEC 0S1) to check
that locking works on that macOS.

### Signing identity and the Accessibility permission

To record websites the agent needs the **Accessibility** permission (SPEC 9). macOS ties it
to the code signature: an ad hoc signature changes at every build, so the permission would
be lost at every deploy. `bin/deploy` therefore signs with a self-signed certificate kept on
the developer's Mac, outside the repository:

    ~/.config/familytimer/signing/cert.pem, key.pem       the certificate and its key
    ~/.config/familytimer/signing/familytimer.keychain-db a keychain that holds them
    ~/.config/familytimer/signing/keychain.pass           that keychain's password

The keychain is in the user's keychain search list (`security list-keychains -d user`);
`bin/deploy` unlocks it. The designated requirement is then
`identifier "com.2manyclicks.familytimer.FamilyTimerAgent" and certificate leaf = H"..."`,
which stays the same across builds. Losing the files means a new certificate and granting
the permission again on every Mac.

Granting it, once per Mac, by a person at that Mac with an admin password. The agent asks
macOS once per user (`AXIsProcessTrustedWithOptions`), which adds `FamilyTimerAgent` to System
Settings › Privacy & Security › Accessibility, switched off: turn it on there. If it is not in
the list, add it with `+`, Cmd-Shift-G, `/usr/local/libexec/familytimer/FamilyTimerAgent`. Until then the
parents get a Telegram notice at most once a day and only apps are recorded.

## Checking a Mac

    ssh HOST 'tail -20 /var/log/familytimer.log'
    ssh HOST 'launchctl print system/com.2manyclicks.familytimer.daemon | grep -E "state =|pid ="'
    ssh HOST 'stat -f "%Su %u" /dev/console; ps -axo user,command | grep "FamilyTimer[A]gent"'

Good signs in the log: `familytimerd ... started`, `agent connected (uid N)`, a `status:` line
every 5 minutes with `used`, `remaining`, `phase` and `idle`. Without `DRY_RUN` the started line
does not mention it; with it, logouts appear as `DRY_RUN: would log out`.

From Telegram, `/status NAME` in the parents' group answers with the same numbers.

## Rules for whoever deploys

- Test locally first (`swift build && swift test`); deploy only committed code.
- Without `DRY_RUN` the child is really locked out and logged out (unsaved work is lost).
  Check `used` in the log before deploying a lower limit: if it is already over, the child
  gets the "time is over" dialog at the next tick. Tell the parents.
- Deploy only to the Macs the parents named. Ask before removing `DRY_RUN` or changing limits.
- A Mac that sleeps drops SSH ("Operation timed out"): ask a parent to wake it, then retry.
- Two daemons must never poll the same bot: one bot per Mac.
- The old minertimer (Minecraft only) may run on the same Mac; leave it alone (SPEC 7.2).

## Troubleshooting

| Symptom | Cause, fix |
|---|---|
| `Bootstrap failed: 5: Input/output error` | the old job was still stopping; the updater now waits. Check `launchctl print`: often the job is running anyway |
| no ⏱ in the child's menu bar | agent not running in that session: `ps` above. The daemon restarts it after 60 s (`agent missing ... restart 1/2` in the log), twice, then tells the parents on Telegram. It also stays hidden until the first `state` message (a few seconds) |
| `agent socket: refused uid N` in the log | a non-child session (a parent) connected; expected |
| `getUpdates failed: The network connection was lost` | the Mac slept or the network dropped; it retries by itself |
| deploy says "first install" on a Mac that had it | `/etc/sudoers.d/familytimer` is missing or names another admin |

## Undo

Emergency, from Telegram: `/unlock NAME` or `/extra 30m NAME`. Back to logging only: set
`DRY_RUN=1` in the env file and redeploy. Full removal (as root on the target): boot out and
delete both plists, then delete `/usr/local/libexec/familytimer`,
`/Library/Application Support/FamilyTimer`, `/etc/sudoers.d/familytimer` and the log.
