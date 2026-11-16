# Documenso for Railway: the official image, pinned by version and digest,
# plus a small entrypoint (signing certificate, migrations, first admin).
FROM documenso/documenso:v2.22.0@sha256:f9976d2142d34ee89506e161b0a5ec859a0c327f3fe0a398b46d3941fc8dd35e

# Railway volumes mount root-owned. Start as root to fix ownership of the
# certificate volume; the entrypoint then drops to the image's unprivileged
# "nodejs" user with busybox su.
USER root
COPY --chmod=755 entrypoint.sh /usr/local/bin/documenso-railway-entrypoint.sh

ENV PORT=3000 \
    NEXT_PRIVATE_SIGNING_TRANSPORT=local \
    NEXT_PRIVATE_SIGNING_LOCAL_FILE_PATH=/opt/documenso/cert.p12 \
    NEXT_PUBLIC_UPLOAD_TRANSPORT=database

WORKDIR /app/apps/remix
EXPOSE 3000
CMD ["/usr/local/bin/documenso-railway-entrypoint.sh"]
