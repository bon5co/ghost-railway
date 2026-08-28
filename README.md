# ghost-railway

A Railway wrapper image for [Ghost](https://ghost.org) 6.60.0, the open-source
publishing platform (a self-hosted Substack / Medium alternative). It packages
the official `ghost:6.60.0-alpine` image so a Railway deploy comes up **already
owned by you** instead of waiting to be claimed by the first stranger who opens
the URL.

Image: `ghcr.io/bon5co/ghost-railway:6.60.0`

## Why this exists

A stock Ghost deploy has **no Owner account** until someone completes the setup
wizard, and `POST /ghost/api/admin/authentication/setup/` is unauthenticated.
On every competing Railway template the first person to reach the public URL —
not necessarily the deployer — can create the Owner and lock everyone else out
(`"Setup has already been completed."`), with no recovery path because Ghost's
password reset is an emailed link and a fresh deploy has no SMTP account.

This image closes that window:

- **The Owner is seeded over loopback before the public port opens.** Ghost
  binds `127.0.0.1:2368`; nginx only starts listening on `$PORT` after the
  Owner already exists, so the setup endpoint answers `422` from the first
  request the internet can reach.
- **It refuses to boot on an empty `GHOST_ADMIN_PASSWORD`**, so there is no way
  to deploy an unclaimed instance by accident.
- **The credential is re-applied on every boot**, so a redeploy is a working
  password reset — the recovery path Ghost otherwise only offers by email.

## What else it fixes

- **E-mail works with no SMTP account.** A bundled [mailpit](https://mailpit.axllent.org)
  sink catches staff invites, password resets and member magic links; read them
  at `/inbox` (basic auth, same admin credential). Set `SMTP_HOST` etc. to send
  real mail instead.
- **`$PORT` is honoured** through the nginx front end (Ghost 301-redirects any
  request without `X-Forwarded-Proto: https`, so it cannot sit on the edge
  directly, and Railway's healthcheck dials the injected port).
- **The content volume is repaired** on boot (Railway mounts volumes owned by
  uid 0; Ghost runs as `node`), and the shipped theme/content skeleton is
  restored so a fresh mount is not empty.
- **The image is pinned** to 6.60.0 against the incumbents' moving tags, on an
  app that migrates its database forward on boot.

## Variables

| Variable | Default | Notes |
| --- | --- | --- |
| `GHOST_ADMIN_EMAIL` | `admin@<domain>` | Owner login. |
| `GHOST_ADMIN_PASSWORD` | *(required)* | Owner password; boot fails if empty. |
| `GHOST_BLOG_TITLE` | `My Ghost Site` | Site title, seeded once. |
| `GHOST_ADMIN_NAME` | `Owner` | Owner display name. |
| `database__connection__*` | — | MySQL connection (host/port/user/password/database). |
| `SMTP_HOST` / `SMTP_PORT` / `SMTP_USER` / `SMTP_PASS` | — | Optional real SMTP; overrides the mailpit sink. |

Requires a MySQL 8 service and a volume mounted at `/var/lib/ghost/content`.
