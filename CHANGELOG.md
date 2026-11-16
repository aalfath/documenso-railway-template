# Changelog

## 2.22.0-railway.1 (2026-11-16)

- First release of the template: Documenso v2.22.0 (`documenso/documenso:v2.22.0@sha256:f9976d2142d34ee89506e161b0a5ec859a0c327f3fe0a398b46d3941fc8dd35e`) with Railway's Postgres.
- Entrypoint creates a self-signed signing certificate on the volume, runs migrations, creates the first admin account once, and starts the server as the `nodejs` user.
- Public sign-up is off by default.
