# ElectriFix Connector

A temporary, secure way for ElectriFix to reach your Home Assistant while
your $29 repair job is open.

If you already reach Home Assistant from outside your house — Nabu Casa,
DuckDNS, your own web address — **you do not need this**. This is for the
very common case where Home Assistant only works on your home WiFi.

---

## What it actually does

Your Home Assistant **dials out** to us. Nothing on your network is opened,
no port is forwarded, and your router is not touched.

```
your Home Assistant  ──outbound──▶  Cloudflare  ──▶  ElectriFix
   (this add-on)                    (locked to one
                                     login: ours)
```

The web address it creates is guarded by Cloudflare Access and admits exactly
one credential, which only ElectriFix holds. Nobody else on the internet can
reach it, even if they know the address.

It is also **temporary by design**. The address and the tunnel are created
for your job and destroyed when your job closes. Stop or uninstall the add-on
and the way in is gone immediately, whatever we have or have not finished.

## What it does not do

- It does not read anything itself, and it does not talk to your Home
  Assistant's API. It is a pipe.
- It does not ask for host networking, and it publishes no port to your
  network — it listens on `127.0.0.1` **inside its own container**.
- It does not ask for Supervisor access, so it cannot install, change or
  remove anything.
- It does not change your `configuration.yaml`. Not one line. (That is why
  it includes a small proxy — see `DOCS.md`.)

You can read `config.yaml` in this folder to check every one of those.

---

## Install it — a few clicks

1. In Home Assistant go to **Settings → Apps**, press **Install app** (bottom
   right), then the **⋮** menu (top right) → **Repositories**. Paste
   `https://github.com/nickthelomas/ha-addons`, press **Add** (bottom right)
   and wait a moment for it to load. *(On older versions this is Settings →
   Add-ons → Add-on Store.)*
2. Go back, type **electrifix** into the search box, open **ElectriFix
   Connector** and press **Install**. It builds on your box the first time,
   so give it a few minutes.
3. Open the **Configuration** tab and paste your **job code** into
   `job_code`, then **Save**. The job code is on your ElectriFix job page,
   with a Copy button next to it.
4. Go back to the **Info** tab and press **Start**.

That is it. Your job page will notice within a few seconds and move you on to
the next step by itself — you do not need to tell us.

> **The job code is a key to your house.** Treat it like a password: don't
> post it in a forum, a Discord, or a screenshot. It stops working when your
> job closes.

### When you are done

**Settings → Apps → ElectriFix Connector → Uninstall.** Nothing is left
behind. You can also just click **Stop** if you would rather keep it for a
follow-up; a stopped add-on carries no traffic.

---

## If it does not work

**"No job code set yet"** in the log — the Configuration tab was saved empty,
or the paste picked up a space. Copy it again from the job page with the Copy
button and press Save, then Start.

**The add-on starts and immediately stops** — check the **Log** tab. If it
says the tunnel token is invalid, your job code is for a job that has already
closed; ask us for a fresh one.

**The add-on is running but the job page still says "waiting"** — give it 30
seconds. If it is still waiting, open the Log tab and send us what it says.
The log never contains your job code or your Home Assistant token, so it is
safe to paste to us.

**Your Home Assistant is on HTTPS** — if you have ever added
`ssl_certificate:` to your `configuration.yaml`, Home Assistant serves HTTPS
on port 8123. The add-on checks which one you use when it starts and says so
in the log (*"Home Assistant speaks https on port 8123"*), so there is nothing
for you to change. If the log shows repeated `tls` or `handshake` errors and
the job page never moves, send us the log — that is ours to fix, not yours.

**"The local proxy exited immediately"** — that is our bug, not your setup.
The add-on stops itself rather than sitting there looking healthy while
nothing works. Send us the log.

**It will not install** — this add-on needs Home Assistant **OS** or
**Supervised**. If Settings has no "Apps" (or "Add-ons") entry at all you are on
Container or Core, where add-ons do not exist. Tell us and we will sort out
another way in.

---

---

Questions: **admin@electrifixperth.com** ·
[fix.electrifixperth.com.au](https://fix.electrifixperth.com.au)
