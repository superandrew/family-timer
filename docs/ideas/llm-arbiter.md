# An LLM that answers time requests

A request goes to a model (Claude through the API) instead of straight to the parents.

- Context: usage today and by category (games, study, coding...), past requests and their
  outcome, time of day, school day or not.
- Parents' rules in plain words ("nothing after 21", "more if it was study or coding",
  "at most 30 extra minutes a day").
- Learning: a log of decisions and parent feedback ("too generous", "right") put in the
  context, not training.
- Two steps: first the model suggests ("15 min: 40 min of coding today") and a parent
  confirms with one tap; later small requests are decided alone, with a notice.

Constraints:
- Hard caps stay in the daemon: the model cannot give more than the parents allow.
- No free text from the child reaches the model (prompt injection); at most a reason from a
  fixed list.
- Usage statistics leave the Mac for the API: a choice for the parents.
