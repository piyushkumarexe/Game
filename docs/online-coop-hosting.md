# Online crew: hosting and joining a Redmesa expedition

Four players share one RV. The session is **host-authoritative**: the host owns
the RV physics, the mission chain, the crew roster and the voice routing. A
client sends input and nothing else, which is what keeps a friend's phone from
being able to rewrite the rig's state.

This is an original implementation. It uses no titles, art, models, audio, map
data, characters or text from any other game.

## Transports

| | WebSocket (`ws://` / `wss://`) | ENet (UDP) |
|---|---|---|
| Best for | playing over the internet, behind a shared host or a reverse proxy | four phones on the same Wi-Fi or LAN |
| Protocol | TCP, one port, no UDP hole punching | UDP, needs an open/forwarded UDP port |
| Channels | reliable only — Godot's WebSocket peer has no unreliable mode | true unreliable channels for RV and player state |
| Feel | ~9 KB/s per talker, ~7 KB/s of RV state; very readable on broadband | lowest jitter on a clean LAN |
| In-game string | `ws://203.0.113.9:24817/` or `wss://trip.example.com` | `enet:192.168.1.20:24817` |

Pick the transport from the main menu — **HOST ONLINE EXPEDITION** (WebSocket)
or **HOST SAME-WI-FI CREW (UDP)**. Joining auto-detects it from what you paste,
so a single `IP:PORT` string is enough for either.

## Host from a machine you control (recommended)

The clearest setup is a dedicated host that nobody plays on, so the trip keeps
running even if the host's phone drops:

```bash
# 1. build the headless server binary (Godot strips rendering resources for it)
godot --headless --export-release "Linux Dedicated Server" build/server/DustboundServer.x86_64

# 2. run it
./DustboundServer.x86_64 --headless -- --server --port 24817
```

Or straight from a source checkout, no export step:

```bash
godot --headless --path . -- --server --port 24817          # WebSocket (default)
godot --headless --path . -- --server --port 24817 --enet  # UDP for a LAN
```

The process prints `SERVER_READY transport=websocket port=24817 max_players=4`
and then builds Redmesa Valley. Crew may already connect while that happens —
joins that arrive mid-build are queued and spawned as soon as the terrain and
the RV collider exist, so nobody lands inside an unfinished chunk.

## Hosting from a phone or the editor

Tap **HOST ONLINE EXPEDITION**. The menu shows the share line, e.g.

```
ws://192.168.1.20:24817/   (port 24817 open on your router for internet play)
```

On the same Wi-Fi, crew paste that directly. Over the internet they need a
routable address: port-forward TCP 24817 to the host machine, or run the
dedicated server on a VPS. Android needs the `INTERNET` permission, which the
export preset already sets; the radio additionally needs `RECORD_AUDIO`, which
is enabled in the same preset.

## wss:// behind a reverse proxy

Certificates are the boring part of voice chat over the internet, so terminate
TLS on a proxy and let the game keep speaking plain `ws://` on localhost.

```nginx
# nginx
stream {  # optional: raw TCP passthrough on 24817
  server { listen 24817; proxy_pass 127.0.0.1:24817; }
}
```

```nginx
# nginx, HTTP path with TLS termination
server {
  listen 443 ssl;
  server_name trip.example.com;
  ssl_certificate     /etc/letsencrypt/live/trip.example.com/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/trip.example.com/privkey.pem;
  location / {
    proxy_pass http://127.0.0.1:24817;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_read_timeout 3600s;
  }
}
```

```yaml
# Caddyfile
trip.example.com {
	reverse_proxy 127.0.0.1:24817
}
```

Caddy's automatic TLS makes the session reachable as
`wss://trip.example.com:443/` — that exact string is what crew paste into the
join field.

## Docker

```bash
docker run -d --name dustbound-server -p 24817:24817 \
  -v "$PWD/build/server:/srv" debian:stable-slim \
  sh -c "cd /srv && ./DustboundServer.x86_64 --headless -- --server --port 24817"
```

## Joining

Type any of these into **JOIN A CREW**:

```
192.168.1.20                 → ws://192.168.1.20:24817/
192.168.1.20:24817           → ws://192.168.1.20:24817/
wss://trip.example.com        → wss://trip.example.com:443/
enet:192.168.1.20:24817       → UDP, host-authoritative LAN session
```

The last address is remembered in `user://dustbound_settings.cfg`, so a regular
crew only types it once.

## Roles, and why co-op is not four copies of solo

Roles are identity and intent, not hard locks: anyone can do anything, but the
route is built so that the split is worth it.

- **DRIVER** — wheel, gearbox, handbrake, and both cables from the dash.
- **MECHANIC** — the repair bench at Lantern Post Garage; the rig only heals
  there, so a mechanic decides *when* the crew stops.
- **SCOUT** — walks the route on foot: carries crates, hauls the bridge planks
  into the sockets, and can hook a cable at a station while the driver sits
  still.
- **NAVIGATOR** — reads the trip bar and calls hazards on the radio; the
  cheapest win in Mudwater Bog is a voice call, not a second winch.

The winch is the co-op move. `_toggle_winch` searches for a marked tree or steel
post within 22 m of the hook, so the two people who matter are the one at the
station and the one on the throttle. Cable stations stand at the bog and on Last
Light Pass for exactly that reason — on foot, USE **HOOK FRONT CABLE** or
**HOOK REAR CABLE**.

Riding: when the driver seat is taken, USE on the RV offers
**RIDE ALONG AS CREW** (two bench seats). Boarding and stepping out are both
gated to under ~2.4 m/s, because a moving coach is how co-op runs end in a
laughable rescue. Riders are carried by the coach transform, so nobody is
stranded three switchbacks behind the rig, and the door is left open where they
stepped out.

## Radio

12 kHz mono, ~9 KB/s per talker, filtered by distance on the host
(`VOICE_RANGE_M = 26`). Push-to-talk is `V` / right-stick click / the RADIO
touch button; `M` deafens you. A green nameplate means that crew member is
talking to you right now — which also means *your* mic works for them.

A missing or unaccepted microphone never blocks the trip: the game toasts
"NO MICROPHONE" and drops you to gestures and buttons. Android prompts for
`RECORD_AUDIO` once, on the first online session.

## Synchronization model

- **RV**: simulated only on the host. Clients receive a transform plus
  velocities per physics tick on an unreliable channel (channel 1) and
  interpolate at `0.42`, which hides jitter without letting a client "correct"
  the rig.
- **Crew on foot**: each player node is authoritative over itself and broadcasts
  its transform (channel 1); everyone else interpolates at `13/s`.
- **Mission state**: `GameSession.complete_target()` and `set_checkpoint()` run
  on the host and are rebroadcast (leg index, checkpoint, crates, planks).
- **Toasts**: host-side events — a crate loaded, a cable that found no anchor,
  a crew member who dropped out — are relayed so the crew reads one feed.
- **Interaction**: clients `rpc_id(1, ...)` their request; the host checks the
  distance to the object before applying it. A client can never reach an
  interactable it is not standing next to.
- **Disconnects**: the host releases the abandoned driver seat and any ride
  slot, so the RV parks instead of freezing with a phantom driver. A late
  joiner is re-spawned into the current leg and receives the mission board.

## Known limits, deliberately not faked

- No accounts, no matchmaking, no lobby browser, no session history. Friends
  connect by address.
- No host migration. If the host leaves, the trip ends for everyone.
- WebSocket is TCP: on a lossy mobile connection one dropped packet stalls the
  RV update briefly (head-of-line blocking). Use ENet on the same LAN, or a
  wired host, when that shows up.
- Voice over TCP can lag behind the picture on a bad link; it is capped and
  coalesced to 20 packets/s per talker to keep the game state first.
- Verified in CI headless (host + two joining crew, roster rpcs, spawn, mission
  sync). Not yet verified on four physical phones — see the checklist below.

## Self-test

CI runs the real handshake headless:

```bash
godot --headless --path . -- --server --port 24817 --selftest &
godot --headless --path . -- --join 127.0.0.1:24817 --selftest --selftest-wait 110 &
godot --headless --path . -- --join 127.0.0.1:24817 --selftest --selftest-wait 110 &
wait
```

`SERVER_SELFTEST_OK crew=2` plus two `CLIENT_SELFTEST OK` lines mean the roster,
the spawn rpcs and the world-sync path worked. Anything else prints the crew
count it reached, which is where the failure lives.

## Device checklist before calling co-op stable

- Four devices on Wi-Fi, one hosting: roster shows 4/4 and the campfire spawns
  do not overlap.
- A phone joining *after* the host already reached Mudwater Bog spawns on the
  trail at the last checkpoint, not back at camp.
- Driver disconnects mid-bog: the RV parks and someone else can take the wheel.
- Both cables hooked from a cable station by a scout while the driver idles.
- A passenger stepping out at 4 km/h, and the prompt refusing it at 40 km/h.
- Radio audible both ways within ~26 m, silent beyond it; `M` deafens.
- Android permission denied once, then re-offered on the next session.
