# Vision

pingwing is an internal notification service: one HTTP call in, a delivered
message out, with the queueing, the SMTP conversation, the retries and the
record of what happened hidden behind it. It exists so that five programs in one
platform do not each grow their own mail client. This document says which
transports, guarantees and integrations that promise should eventually cover,
and which parts of the design are load-bearing enough to shape the answer.

## Where pingwing is today

A Guile program on GNU Artanis, one process, two halves. `app/api/v1.scm` holds
three routes — post a task, list the queue, answer liveness — and writes rows.
`lib/pingwing/tasks.scm` holds the worker, which sweeps: requeue what a dead
process left in `processing`, claim a batch, deliver it concurrently on a
`run-fibers` scheduler, rest, repeat. Ingestion and delivery meet in exactly one
place, a row of the `tasks` table, and never share a transaction.

Only `send-email` is implemented. A task names a template, the template is a
Scheme module under `lib/pingwing/templates/` that fills a plain-text part and
an HTML part, and delivery is one libcurl SMTP conversation per recipient. Three
templates ship: `password-reset`, `system-alert` and `lucidplan-new-ticket`.

What is already unusually careful, and worth protecting:

- **Statements are built by `kracht` and bound by SQLite.** SQL text and values
  travel separately, so a subject with an apostrophe, or a value that spells out
  `'; DROP TABLE tasks; --`, is a value and cannot change the shape of a
  statement. There is no escaping helper, deliberately.
- **The message is built to survive the wire.** RFC 2047 headers, an RFC 5322
  date independent of the host locale, a generated `Message-ID`, a fresh MIME
  boundary, quoted-printable over the UTF-8 bytes, CRLF endings, soft-wrapped
  lines, an escaped leading dot, and header values stripped of line breaks.
- **One message per recipient.** No recipient reads another's address off a
  `To` header.
- **The palette is measured, not chosen.** `lib/pingwing/css.scm` holds one table
  read twice, and suites assert that every painted element wears a class the
  dark override can reach and that every text colour clears 4.5:1 against the
  layers it is actually composited over.
- **Migration history is ledgered** by mutastructura, by name and checksum, so an
  edited migration is reported rather than quietly re-run.

Four decisions constrain what comes next. Authentication belongs to the reverse
proxy, because there is no user model to protect and a password hash would be an
account system guarding three machines that already hold a shared secret. A
template is code, chosen from a fixed list at the API boundary. The queue's
durability is a single SQLite file in WAL mode, and the worker is not a separate
process. And the API answers about the queue in aggregate only: there is no
route that reads or changes one task.

## The vision

1. **One queue, several transports.** `send-email` is the first transport, not
   the service. A webhook, a chat message and a push notification become task
   types that share the same row, the same retry clocks and the same record of
   failure, so an operator reads one table and one log to know what the platform
   told whom.
2. **Callers get closure, not silence.** A task is posted with a key, so a
   caller that retries does not send twice, and its outcome is either delivered
   back to a URL the caller registered or available on a route that can wait.
   "Did the onboarding mail go out?" becomes a request rather than a look in
   `sqlite3`.
3. **A message is described, not programmed.** Adding a template should be
   posting a document — subject, parts, variables, which variables are secret —
   through the same API, without a JSON path into `eval`. Python's `logging`
   mistake and its cure are both instructive: strings over the wire are data, and
   data with a declared shape renders safely.
4. **The service reports on itself.** Per-template and per-recipient-domain
   counts for accepted, failed and retried, a metric endpoint, and a retention
   policy, so the answer to "is mail working" is a graph rather than a manual
   sweep of `last_error`.
5. **It is deployable by someone who does not read Scheme.** A container image,
   a Shepherd and a systemd unit, a documented backup-and-restore, and an upgrade
   that is `maak migrate` — the same commands a stranger can follow on a machine
   with no Guix.

## Features that are in scope and not built yet

- **`send-slack` as a task type.** Named as a TODO in the manual. The hard part
  is not the webhook: it is that every retry, error and status the mail path
  learned is phrased in SMTP's vocabulary, and a second transport needs a shape
  that describes both without pretending a webhook has an envelope sender.
- **A template supplied in the request.** Also a TODO, and the one place the
  design should push back: sending Scheme over the wire is `eval` of untrusted
  input. The achievable version is a declarative template — parts, variables,
  escaping rules — validated against a schema, with rendering in the existing
  HTML furniture.
- **A translated catalogue.** `ENTRY` binds the gettext domain to
  `./sys/i18n/locale`, which holds no `.mo`, and the manual is written in
  English. The hard part is not the catalogue: it is that a message is built
  server-side in one locale, so localising it means deciding a locale per task
  or per recipient, and shipping templates that read correctly in both.
- **A task's own route, and a retry command.** The manual states plainly that
  there is none. The hard part is concurrency: a manual retry that races a sweep
  claim either delivers twice or loses the message, so the claim needs to be a
  thing a second caller can see.
- **Idempotency.** Nothing in a request distinguishes a caller's retry from a
  caller's second intent. The hard part is that the key must live in the task
  row and be unique in SQLite, which is a schema decision rather than an API one.
- **Bounce handling.** Delivery is called sent when the server accepted it, which
  is correct and incomplete: a later hard bounce is invisible. The hard part is
  that the bounce arrives by mail, so the service needs an inbox it does not
  have.

## New features that would be worth having

- **Attachments**, fetched by URL with a size cap and an SSRF policy, or passed
  inline with a limit. Rendering the bytes is easy; the policy is the feature.
- **A body preview route** that renders a template with given variables and
  returns the two parts without sending anything. It would have caught the dark
  palette contrast fault in review rather than in a browser screenshot.
- **Digest batching**: hold notifications for one recipient for a window and send
  one message instead of nine. The queue already knows how to wait.
- **Per-caller settings** filled from the proxy's identity: an allow-list of
  templates, a default sender, a rate limit. This is the smallest honest
  multi-tenancy, and it keeps the "no users table" decision intact.
- **A token-bucket rate limit per recipient domain**, because the fastest way to
  lose a sending reputation is a loop that posts a thousand tasks.
- **A task that sends a scheduled message** — a future `not-before` on the row,
  claimed by a sweep — which turns the queue into a reminder service for the rest
  of the platform.

## Contributions that would move the needle

1. **A status route and an idempotency key.** Small, self-contained, and it
   removes the one failure a caller cannot see: a retried POST that sent twice.
2. **A second transport through the same queue.** Proves whether the abstraction
   is a queue with one delivery or a mail service with a table, and it is the
   project's own TODO.
3. **A preview route for templates.** A day's work that makes every template
   change reviewable without an SMTP account, and gives the contrast suites a
   second consumer.
4. **Retention and pruning with a documented backup.** Rows are kept forever
   today; a tested `maak prune` plus the restore procedure is the difference
   between a service and a toy.
5. **The gettext catalogue filled for one language other than English**, with the
   locale decision written down. Small, and it forces the per-recipient question
   to be answered on purpose.
6. **A container image and a unit file.** Cheapest way to make a stranger able to
   run it, and the first thing a deployment asks for.
7. **Bounce handling.** The largest item here and the one that turns "we sent it"
   into "they received it".

## Compared to related projects

| Project | What it is | Where pingwing differs |
| --- | --- | --- |
| Postfix, exim | Mail transfer agents: they speak SMTP and queue what they cannot deliver | A real MTA is the substrate pingwing calls; it has no API, no templates, no per-call record, and its queue is operational rather than inspectable JSON |
| listmonk | A self-hosted newsletter and mailing-list manager with subscribers, campaigns and a web UI | It owns subscribers, consent and campaigns; pingwing owns transactions, has no list, no UI and no unsubscribe model, and never renders a public page |
| Postal, Mailu | Self-hosted mail server suites with a delivery API and webhooks | The closest neighbours: they run the whole mail server including IMAP and DNS; pingwing is a client of somebody else's SMTP and owns only the task |
| Novu, Courier | Hosted notification infrastructure with multi-channel workflows and templates | The feature set this document argues toward, delivered as a service with an account model; pingwing is self-hosted, MIT, and has no user table by design |
| Apprise | A Python library and CLI that fans one message out to ~100 notification sinks | Its breadth across sinks is the lesson; it is a library with no queue, no persistence and no retry record, so a caller learns nothing about what happened |
| ntfy | A pub/sub push service: publish to a topic, subscribers receive it | Excellent for push to phones; not transactional mail, no per-recipient SMTP conversation and no template layer |
| Mailgun, Postmark, SES | Transactional mail providers with an HTTP API | They sell deliverability, reputation and bounce handling, and pingwing calls them; what they cannot give is a queue you own and a record in your own database |
| Flask-Mail, Django's `send_mail` | In-process mail helpers inside one application | A library, not a service: every application still needs its own retry logic, and a slow SMTP server blocks a request thread |

Everything in that table does something pingwing should learn: multi-channel
delivery from Apprise and Novu, bounce and complaint handling from Mailgun and
Postal, a queue an operator can see and edit from listmonk, and an idempotency
key from every payments API that ever had to be retried.

Where pingwing is ahead, and should stay ahead: there is no account system to
attack, because the credential is the proxy's and the callers are machines; one
row is the whole durable record of a message, so an incident is answered by
reading a table rather than by correlating a log and a queue; delivery is one
message per recipient, which most bulk senders trade away; the markup is
asserted against a contrast floor over every template and both palettes, which
almost nothing in this space does; and the migrations are checksummed, so a
deployment's schema cannot silently differ from its source.

## In the long run

- **The task table becomes the ecosystem's record of what was sent.** The other
  projects already point at pingwing; the durable value is not the SMTP
  conversation but the row that says who was told what, when and with which
  result.
- **Transports as data.** Once a transport is a record — an endpoint, a payload
  shape, a retry policy — adding one is configuration rather than a module, and
  the queue is what the project actually owns.
- **Templates as data, in the same store.** A template with variables and a
  secret marking is a row; a version of it can be diffed; and the preview route
  makes the diff meaningful.
- **A rate limit and a reputation budget as first-class state**, because a
  notification service that gets its sending domain blocked has failed at the
  only job it had.
- **Two processes, if and only if a number says so.** The worker shares the
  server's process today. Splitting it is a small change; deciding to split it
  without a measurement would be the wrong one.

## Closing

The order worth arguing about is: idempotency and a status route first, then a
second transport, then templates as data. Everything else in this document is a
consequence of those three, and the reasoning behind each is in the manual's own
sections — the queue, the retry clocks and the message bytes.

*This document describes intent, not commitments.*
