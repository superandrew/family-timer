# Block single apps instead of the whole Mac

Asked by a child: when time is over, block games but leave the rest usable (homework,
music).

- Apps: no VPN needed. The agent can close an app and the daemon can kill its process;
  the same mechanism as the Minecraft limit, driven by the categories (`/app` buttons).
- Sites: blocking a site needs network filtering (DNS, proxy or a network extension), which
  FamilyTimer avoids on purpose (SPEC 1). Closing the browser tab is possible through
  Accessibility but easy to get around.
- Questions: what stays allowed after the daily time ends? Does study time count? Does the
  whole-Mac lock stay as the last resort?
