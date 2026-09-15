#!/usr/bin/env bash
# The ElectriFix Connector: pick a proxy config, start it, then dial out.
#
# Deliberately dumb about ROUTING. It reads ONE option -- the job code -- and
# runs cloudflared with it. Every routing decision (which hostname, which
# origin, who is allowed through) lives on ElectriFix's Cloudflare account,
# not here, so nothing a customer can edit in this add-on can point the
# tunnel somewhere else or take the authentication off.
#
# It is NOT dumb about two things, because both were bugs:
#
# 1. WHICH SCHEME Home Assistant speaks. A customer with `ssl_certificate:`
#    under `http:` serves TLS on 8123, and an http:// upstream against that
#    fails every request. Caddy 2.8 refuses to put both schemes in one
#    `reverse_proxy` ("all proxy upstreams must use the same scheme"), so a
#    mixed-scheme Caddyfile does not merely degrade -- `caddy run` exits 1 and
#    there is no proxy at all. So: probe ONCE, install ONE single-scheme
#    template.
#
# 2. WHETHER CADDY IS STILL ALIVE. The previous version backgrounded Caddy
#    and never looked again. A Caddy that exited 1 produced a silent 15-second
#    wait loop, then a tunnel dialled to a dead origin -- so the add-on showed
#    "running", the hostname answered 502, and to us that is indistinguishable
#    from "the customer has not started it yet". That is the one diagnosis we
#    must not get wrong, so this script now supervises both processes and
#    exits non-zero if either dies.
set -euo pipefail

CONFIG_PATH=/data/options.json
CADDYFILE=/etc/caddy/Caddyfile
HA_HOST=homeassistant
HA_PORT=8123

# Options arrive in /data/options.json (the Supervisor writes it from the
# add-on's Configuration tab). Read it with jq, which the Home Assistant base
# image ships. NOT bashio::config: those shell functions only exist when a
# script is launched through `with-contenv bashio`, and the first real
# install (2026-09-13, K16) died with "bashio::config: command not found".
job_code="$(jq -r '.job_code // empty' /data/options.json 2>/dev/null || true)"
log() { echo "[connector] $*"; }
err() { echo "[connector] ERROR: $*" >&2; }

# NEVER echo the code, not even truncated. An add-on log is one click away in
# the Supervisor UI and gets pasted verbatim into support threads; a job code
# is a bearer credential for this house until the job closes.
if [[ -z "${job_code}" || "${job_code}" == "null" ]]; then
	err "No job code set yet."
	err "Open the job page ElectriFix emailed you, copy the job code, then"
	err "paste it into this add-on's Configuration tab and press Start."
	exit 1
fi

# ---------------------------------------------------------------- the probe
#
# ONE round trip, fail fast. HTTPS is tried first because a wrong guess there
# is cheap (an immediate TLS error) while an HTTPS server handed a plain HTTP
# request can sit and wait. `--insecure` because a self-signed certificate is
# the NORMAL case for Home Assistant and we are only asking "which protocol",
# not "do I trust this" -- the trust decision is in Caddyfile.https, with its
# reasoning.
#
# `-o /dev/null` and `-s`: the RESPONSE must never reach the log. A Home
# Assistant page can name entities and areas, and this log gets pasted into
# support threads.
choose_template() {
	if curl -sS --insecure --max-time 5 -o /dev/null \
		"https://${HA_HOST}:${HA_PORT}/" 2>/dev/null; then
		echo https
		return
	fi
	if curl -sS --max-time 5 -o /dev/null \
		"http://${HA_HOST}:${HA_PORT}/" 2>/dev/null; then
		echo http
		return
	fi
	# Neither answered. Default to plain HTTP -- the overwhelming majority --
	# and let Caddy's own log say what happened per request. This is NOT a
	# fatal case: Home Assistant may simply still be starting up, and an
	# add-on that refused to boot for that would look broken to a customer
	# whose system is fine.
	echo ""
}

scheme="$(choose_template)"
if [[ -z "${scheme}" ]]; then
	log "Home Assistant didn't answer on ${HA_PORT} yet -- assuming plain HTTP."
	log "If it is still starting up, this will pick up as soon as it does."
	scheme=http
else
	log "Home Assistant speaks ${scheme} on port ${HA_PORT}."
fi

install -m 0644 "/etc/caddy/Caddyfile.${scheme}" "${CADDYFILE}"

# ------------------------------------------------------------- the processes

log "Starting the local proxy on 127.0.0.1:8124"
caddy run --config "${CADDYFILE}" --adapter caddyfile &
caddy_pid=$!

cloudflared_pid=""

# If either process dies the whole add-on goes down together: cloudflared
# without Caddy is a tunnel to nothing, and Caddy without cloudflared is a
# proxy nobody can reach.
cleanup() {
	[[ -n "${cloudflared_pid}" ]] && kill "${cloudflared_pid}" 2>/dev/null || true
	kill "${caddy_pid}" 2>/dev/null || true
	wait 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Wait for the proxy to actually accept a connection before dialling out, so
# the tunnel never reports itself connected while the origin is still down --
# and CHECK CADDY IS STILL RUNNING on every pass, so a config Caddy refused
# fails in a second with a real error instead of hanging for 15.
proxy_up=0
for _ in $(seq 1 30); do
	if ! kill -0 "${caddy_pid}" 2>/dev/null; then
		err "The local proxy exited immediately."
		err "That is our bug, not your setup -- please send us this log."
		wait "${caddy_pid}" 2>/dev/null || true
		exit 1
	fi
	if (exec 3<>/dev/tcp/127.0.0.1/8124) 2>/dev/null; then
		exec 3>&- 2>/dev/null || true
		proxy_up=1
		break
	fi
	sleep 0.5
done

if [[ "${proxy_up}" -ne 1 ]]; then
	err "The local proxy never started listening on 127.0.0.1:8124."
	err "That is our bug, not your setup -- please send us this log."
	exit 1
fi

log "Connecting to ElectriFix"
log "Nothing on your network is opened up: this is an outbound connection,"
log "and it stops the moment you stop this add-on."

# `--no-autoupdate`: an add-on that silently replaces its own pinned binary
# is an add-on whose behaviour we cannot reason about on a customer's box.
#
# Backgrounded rather than exec'd, so this script stays alive to supervise
# Caddy. `wait -n` returns as soon as EITHER exits; whichever it was, the
# add-on stops with a non-zero status so Home Assistant shows it as stopped
# rather than leaving a green "running" badge over a dead proxy.
cloudflared --no-autoupdate \
	--loglevel info \
	--metrics 127.0.0.1:0 \
	tunnel run --token "${job_code}" &
cloudflared_pid=$!

# `|| status=$?`: under `set -e` a non-zero `wait -n` would abort the script
# before the diagnostic below could say WHICH process died.
status=0
wait -n "${caddy_pid}" "${cloudflared_pid}" || status=$?

if ! kill -0 "${caddy_pid}" 2>/dev/null; then
	err "The local proxy stopped. Shutting the connector down."
else
	err "The connection to ElectriFix stopped. Shutting the connector down."
fi
exit $((status == 0 ? 1 : status))
