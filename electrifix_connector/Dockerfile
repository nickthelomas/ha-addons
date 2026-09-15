# The ElectriFix Connector image.
#
# Two static binaries on Home Assistant's own base image: cloudflared (the
# tunnel) and Caddy (a reverse proxy whose ONLY job is to strip three
# headers). Nothing else is installed.
#
# EVERY DOWNLOAD IS PINNED AND VERIFIED. This runs on a stranger's box on the
# strength of a sentence we wrote on a web page; an unpinned "latest" would
# mean the add-on that worked yesterday breaks on a fresh install tomorrow,
# with us blamed and no way to tell what changed. The digests are the second
# half of that: a pinned version fetched over a poisoned mirror is still a
# pinned version.
#
# The two projects publish differently, so they are verified differently and
# both are honest about what is actually being checked:
#
#   cloudflared -- ships NO checksums file. The sha256 sums below were
#                  computed from the real release assets on 2026-09-12 and
#                  are the pin. Bumping CLOUDFLARED_VERSION means recomputing
#                  them; the build fails loudly if you forget.
#   caddy       -- ships `caddy_<v>_checksums.txt` (sha512). That file is
#                  fetched and the tarball is checked against it, so a Caddy
#                  bump is a one-line version change with nothing to copy by
#                  hand.
#
# ARCH: `i386` is deliberately absent from config.yaml. Caddy publishes no
# 386 linux build, so an i386 add-on could not be built at all -- and an
# arch listed but unbuildable is a customer watching an install fail with no
# explanation. armhf maps to Caddy's armv6, armv7 to armv7.
ARG BUILD_FROM=ghcr.io/home-assistant/amd64-base:3.19
FROM ${BUILD_FROM}

ARG BUILD_ARCH=amd64
ARG CLOUDFLARED_VERSION=2026.3.0
ARG CADDY_VERSION=2.8.4

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apk add --no-cache curl ca-certificates tar

# --- cloudflared ------------------------------------------------------------
# Release assets are named per GOARCH, which is NOT what Home Assistant calls
# the same machines, so the mapping is explicit. An unmapped arch exits
# non-zero here (loud, at build time) rather than downloading a 404 page and
# marking it executable.
RUN set -euxo pipefail; \
    case "${BUILD_ARCH}" in \
      amd64)   CF_ARCH=amd64; CF_SHA256=4a9e50e6d6d798e90fcd01933151a90bf7edd99a0a55c28ad18f2e16263a5c30 ;; \
      aarch64) CF_ARCH=arm64; CF_SHA256=0755ba4cbab59980e6148367fcf53a8f3ec85a97deefd63c2420cf7850769bee ;; \
      armv7|armhf) CF_ARCH=arm; CF_SHA256=ca16ed5253373846f7d366d591669d0e868e0724e35599abad2c8b2bc2340cfa ;; \
      *) echo "unsupported BUILD_ARCH ${BUILD_ARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL --retry 3 -o /usr/local/bin/cloudflared \
      "https://github.com/cloudflare/cloudflared/releases/download/${CLOUDFLARED_VERSION}/cloudflared-linux-${CF_ARCH}"; \
    echo "${CF_SHA256}  /usr/local/bin/cloudflared" | sha256sum -c - \
      || { echo "cloudflared digest mismatch -- refusing to build" >&2; exit 1; }; \
    chmod +x /usr/local/bin/cloudflared; \
    cloudflared --version

# --- caddy ------------------------------------------------------------------
# Verified against the release's own sha512 checksums file, so a version bump
# needs no hand-copied digest.
RUN set -euxo pipefail; \
    case "${BUILD_ARCH}" in \
      amd64)   CADDY_ARCH=amd64 ;; \
      aarch64) CADDY_ARCH=arm64 ;; \
      armv7)   CADDY_ARCH=armv7 ;; \
      armhf)   CADDY_ARCH=armv6 ;; \
      *) echo "unsupported BUILD_ARCH ${BUILD_ARCH}" >&2; exit 1 ;; \
    esac; \
    ASSET="caddy_${CADDY_VERSION}_linux_${CADDY_ARCH}.tar.gz"; \
    BASE="https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}"; \
    cd /tmp; \
    curl -fsSL --retry 3 -o "${ASSET}" "${BASE}/${ASSET}"; \
    curl -fsSL --retry 3 -o sums.txt \
      "${BASE}/caddy_${CADDY_VERSION}_checksums.txt"; \
    grep " ${ASSET}\$" sums.txt > want.txt; \
    test -s want.txt || { echo "no checksum published for ${ASSET}" >&2; exit 1; }; \
    sha512sum -c want.txt \
      || { echo "caddy digest mismatch -- refusing to build" >&2; exit 1; }; \
    tar -xzf "${ASSET}" caddy; \
    mv caddy /usr/local/bin/caddy; \
    chmod +x /usr/local/bin/caddy; \
    rm -f "${ASSET}" sums.txt want.txt; \
    caddy version

# BOTH templates ship; `run.sh` probes Home Assistant once at start and
# installs one of them as /etc/caddy/Caddyfile. There is deliberately no
# single mixed-scheme Caddyfile: Caddy 2.8 refuses two schemes in one
# reverse_proxy and exits 1, which is a proxy that never starts.
COPY Caddyfile.http /etc/caddy/Caddyfile.http
COPY Caddyfile.https /etc/caddy/Caddyfile.https
COPY run.sh /run.sh
RUN chmod a+x /run.sh

CMD ["/run.sh"]
