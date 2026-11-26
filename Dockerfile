# Upstream's Whatomate image, pinned to a release. The wrapper adds the Railway entrypoint
# and busybox, whose httpd serves the notice page shown
# when the server can't start.
FROM shridh0r/whatomate:0.1.1-beta-0.18

RUN apt-get update && apt-get install -y --no-install-recommends busybox \
    && rm -rf /var/lib/apt/lists/*

COPY --chmod=0755 railway-entrypoint.sh drop-file-cache.sh /usr/local/bin/

WORKDIR /app
ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
