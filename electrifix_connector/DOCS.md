# ElectriFix Connector — how it works

This is the page the Supervisor shows under the add-on's **Documentation**
tab. It is written for the customer who wants to know exactly what they just
installed before they press Start, because on this screen that person deserves
a straight answer.

## The whole thing, in order

1. You paste a **job code** and press Start.
2. The add-on checks **once**, at start, whether your Home Assistant speaks
   HTTP or HTTPS on port 8123 (it serves HTTPS if you have `ssl_certificate:`
   under `http:` in your configuration). You do not have to tell it which —
   and the log says which one it found.
3. It starts **Caddy**, a small web proxy, listening on `127.0.0.1` port
   8124 — inside the add-on's own container. Nothing on your network can
   reach it. (On the HTTPS path the certificate is not verified: that hop
   never leaves your own machine, and there is no CA that could verify a
   self-signed certificate issued for a Docker hostname.)
4. The add-on starts **cloudflared**, Cloudflare's tunnel client, with your
   job code. cloudflared makes **outbound** connections to Cloudflare. No
   incoming connection is ever accepted, so your router and firewall stay
   exactly as they are.
5. Cloudflare now has a route: one web address, created for your job,
   pointing at that proxy — and therefore at your Home Assistant.
6. That web address sits behind **Cloudflare Access** with one rule: admit
   one service token, ElectriFix's. Everyone else on the internet gets a
   login page they cannot pass, even knowing the address.
7. ElectriFix connects through it with your Home Assistant long-lived token,
   which you created and can revoke, and does the audit.
8. When the job closes, the service deletes the Access rule, then the DNS
   record, then the tunnel — in that order, so the address is never live with
   its guard already removed.

## Why there is a proxy in here at all

cloudflared adds `X-Forwarded-For`, `X-Forwarded-Proto` and
`X-Forwarded-Host` to every request. Home Assistant refuses requests carrying
those unless you edit `configuration.yaml`:

```yaml
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 172.30.32.0/23
```

...and restart. We are not willing to ask for that. It is a change to **your**
configuration that outlives the job, `trusted_proxies` is a setting you can
get subtly wrong in a way that weakens your own security, and it is exactly
the kind of YAML editing you hired us to avoid.

So Caddy **deletes** those three headers on the way through
(`header_up -X-Forwarded-For`, and the other two). Home Assistant sees an
ordinary request from a container on its own Docker network, the same as the
companion app on your WiFi. Your configuration is untouched.

There are two config templates in the add-on, `Caddyfile.http` and
`Caddyfile.https`, and the start-up check installs exactly one of them. They
are separate files rather than one file with two upstreams because Caddy
refuses to mix schemes in a single proxy — and a config Caddy refuses is a
proxy that never starts at all.

Because the headers are deleted rather than rewritten, nothing can smuggle a
forged client IP through either.

## What this add-on is allowed to do

From `config.yaml`, which you can read:

| Setting | Value | What that means |
| --- | --- | --- |
| `host_network` | `false` | It has its own network namespace. It cannot see your LAN. |
| `ports` | *(none)* | Nothing is published to your network. |
| `privileged` | *(none)* | No kernel capabilities. |
| `hassio_api` | *(not set)* | It cannot talk to the Supervisor, so it cannot install, change or remove anything. |
| `homeassistant_api` | *(not set)* | It cannot call your Home Assistant API. It only forwards what comes down the tunnel. |
| `ingress` | `false` | No panel in your sidebar, and nothing published on the add-on's behalf. |
| `map` | *(not set)* | It cannot read your config, your media, or your backups. |

The only thing it reads is `job_code`, and the only outbound connection it
makes is to Cloudflare.

## The job code

It is a Cloudflare tunnel token: the credential that says "this cloudflared
belongs to that tunnel". Treat it like a password.

- It is stored by the Supervisor in `/data/options.json` on your own machine,
  and it is a `password`-type option so the UI masks it.
- The add-on **never prints it** — not to the log, not truncated. If you
  paste an add-on log to us, you are not pasting your job code.
- It only works for your job, and it stops working when the job closes.

If you think it has been exposed, tell us and we will destroy that tunnel and
issue a new code. It costs nothing.

## Stopping and removing it

**Stop** ends the tunnel immediately; the address stops answering within
seconds. **Uninstall** removes the add-on and `/data/options.json` with it.

Either way, ElectriFix's route into your Home Assistant is gone. Revoking the
long-lived token (**Profile → Security** in Home Assistant) removes the other
half, and you can do that whenever you like — we also destroy it ourselves at
the end of the job and send you an itemised list of what was removed.

## Troubleshooting

See the **README** tab: what each log message means, and what to send us if
you are stuck.

## Support

**admin@electrifixperth.com** — or reply to the email your job page came in.
