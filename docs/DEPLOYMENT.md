# Deploying SabayGo

Design, 25 Nov 2026. Nothing here is built yet. The decisions at the end
are the owner's, and the build waits on them.

## Why

Today the server is a laptop. Its address changes at every place, every
phone has to be on the same Wi-Fi as the laptop, and the camera phone
cannot be: its Wi-Fi is the Tapo's hotspot. A deployment puts the server
on the internet at one fixed address. Every app is then built once with
that address and reaches it from any network, mobile data in the van
included. Nobody types an address, and nothing is rebuilt for a new place.

## The picture

```
                          https://<domain>
                                 |
         one cloud server  +-----+--------------------------------+
                           | Caddy: HTTPS (Let's Encrypt)         |
                           |   /           console (static files) |
                           |   /api/v1/*   backend                |
                           |   /media/*    backend                |
                           |   /health     backend                |
                           | backend: FastAPI, ONE worker         |
                           | MySQL 8 at +08:00, not exposed       |
                           +-----+--------------------------------+
                                 |  internet
     +----------------+----------+---------+------------------------+
 Passenger phones  Dispatcher phone   Terminal office PC     Camera phone (realme)
 mobile data or    mobile data        any browser:           mobile data to the server;
 any Wi-Fi                            the console            its Wi-Fi is the hotspot
                                                             the Tapo joins
```

One origin serves the console, the API and the media. The console's
requests are then same-origin, so no CORS rule is needed for it, and one
certificate covers everything.

## Each piece

| Piece | Runs on | Talks to | Built |
|---|---|---|---|
| Backend + MySQL | the cloud server, Docker Compose | — | an image on the server, per version |
| Console | the same server, files served by Caddy | `https://<domain>/api/v1` | once per version, `--dart-define=API_BASE_URL=https://<domain>/api/v1` |
| Passenger / Dispatcher app | the phones | the domain, compiled in | one signed release APK per version |
| Edge app | the realme in the van | the domain (its default; Set-up keeps the field) | one signed release APK per version |
| Tapo C110 | the van door, on van power | only the realme's hotspot | — |
| Laptop | development, `ai_service/eval/` | — | — |

## The van

- **Tapo**: joins the realme's 2.4 GHz hotspot and nothing else, and
  needs no internet to work (the 24 Nov test: the stream came back with
  the phone's data off). It *can* reach the internet, though: a hotspot
  shares the phone's mobile data, and the realme keeps its data on to
  reach the server. The video leaves the van only if someone opens the
  live view in the Tapo app or cloud recording is on. So the TP-Link
  account the camera is registered to is the cooperative's, not a
  student's personal one (whoever holds it can watch the door live), and
  cloud recording stays off. Its first setup, in the Tapo app, needs
  internet through the hotspot; daily use does not.
- **realme**: hosts the hotspot, reads the Tapo's `stream2`, counts on the
  phone, and sends door events, stills and heartbeats to the domain over
  its own mobile data. Its SIM needs a data load. Where the signal drops,
  events are kept on the phone and uploaded later; the server files each
  one by the time it happened, not the time it arrived
  (`backend/app/application/edge/ledger.py`).
- The terminal's Wi-Fi is not needed by anything.

## Rules the server must keep

- **One backend worker** (`uvicorn --workers 1`). The unpaid release,
  phone silence and evidence retention jobs run inside the process
  (`backend/app/main.py`, `lifespan`). Two workers would run each job
  twice: a passenger would be told twice that their seat was released.
- **MySQL at +08:00** (`--default-time-zone=+08:00`, `TZ=Asia/Manila`),
  as in `docker-compose.yml`. A server left on UTC shifts every
  check-in window and cutoff by eight hours, silently.
- **Migrations with `db/apply.sh`**, never `db/reset-dev.sh`, which wipes
  the database. Every migration already has its down script
  (`db/rollback.sh`).
- **No seed data.** No dev accounts (`sabaygo123`) exist on the server.
  The first Terminal Manager account is made by a one-off script. A2Z's
  setup (terminals, routes, fares, vans, staff) is then done in the
  console, as in `docs/DAY1_TEST_GUIDE.md`.
- **Secrets only in the server's `.env`**: a new `JWT_SECRET`, the
  database passwords, `ENVIRONMENT=production`, `DEBUG=false`,
  `CORS_ORIGINS=["https://<domain>"]`. In production the private-LAN
  CORS pattern is off by itself (`backend/app/config.py`).
- **Only ports 80/443 (Caddy) and SSH open.** MySQL and port 8000 are
  reachable only inside the server.
- **A nightly backup**: a `mysqldump` and `backend/media`, copied off the
  server. If the server is lost and there is no copy, every record goes
  with it.

## What gets built

1. A backend `Dockerfile`, plus `deploy/docker-compose.prod.yml` (mysql,
   backend, caddy), `deploy/Caddyfile` and `deploy/.env.example`.
2. A script that makes the first Terminal Manager account.
3. Release builds of both Android apps: HTTPS only (plain HTTP stays in
   debug builds), the domain compiled in, and signed with a release
   keystore kept out of git. If the keystore is lost, no update can be
   installed over the app.
4. The console's production build, with `API_BASE_URL` set to the domain.
5. SMS for the SOS. The gateway handset sits behind its carrier's NAT, so
   a cloud server cannot call it the way the laptop can on the same
   Wi-Fi. Either the gateway app's cloud mode relays the message through
   its public server (the SOS text and the numbers pass through it), or
   Twilio is used, or SMS stays off.
6. `deploy/backup.sh`, run every night by cron.
7. The update procedure: `git pull`, `db/apply.sh`, rebuild, restart. To
   roll back: the previous image and `db/rollback.sh <version>`.

## Decisions for the owner

1. **Hosting.** A VPS in Singapore (the nearest region to Davao) with
   2 GB of RAM. MySQL 8 and the backend are tight in 1 GB. That costs
   roughly US$6–12 a month (check current prices), or nothing on a free
   tier such as Oracle Cloud Always Free, if its sign-up goes through.
2. **Domain.** A bought name (a `.com` is about US$10–15 a year) or a free
   subdomain (e.g. DuckDNS). HTTPS works with either.
3. **SMS for the SOS.** The gateway's cloud relay, Twilio, or off (item 5).
4. **Data.** Passenger accounts, trips, GPS readings and door stills would
   live on a hosted server outside the cooperative, probably outside the
   Philippines. A2Z should agree to that, and the paper should say so
   under the Data Privacy Act of 2012. Stills are already deleted when
   their retention period ends.
5. **Getting the app to phones.** An APK download link for the pilot, or
   Play Store internal testing (a one-time developer fee).

## What stays for development

`./run.sh` on the laptop, debug builds with the Server line on the
sign-in screen, and the console at `localhost:3001`. Deployment is in
addition to these and replaces none of them; the journey tests keep
running against the laptop.

## The manuscript

The paper already calls the count edge-to-cloud. Tables 3 and 4 have no
server row. Once this is built, add one (the cloud server, its region,
Caddy, Docker) through `docs/MANUSCRIPT_CORRECTIONS.md`.
