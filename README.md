# Documenso on Railway

A one-click Railway template for [Documenso](https://github.com/documenso/documenso), the open-source document signing platform (an alternative to DocuSign).

This repo builds the official image `documenso/documenso:v2.22.0`, pinned by digest, with a small entrypoint. Railway builds the Documenso service from this repo, so a merge to `main` shows up as an "update available" notice for everyone who deployed the template. Read [CHANGELOG.md](CHANGELOG.md) before you apply an update.

## What the template deploys

| Service | Source | Data |
|---|---|---|
| Documenso | this repo (`Dockerfile`) | volume at `/opt/documenso` (signing certificate) |
| Postgres | Railway's Postgres | volume (accounts, documents, audit logs) |

Uploaded and signed PDFs are stored in Postgres (`NEXT_PUBLIC_UPLOAD_TRANSPORT=database`), so the database volume holds everything except the signing certificate.

## What the entrypoint does

1. **Signing certificate.** On first boot it creates a self-signed `.p12` certificate (10 years) on the volume, protected by `NEXT_PRIVATE_SIGNING_PASSPHRASE`, and reuses it on every later boot. Documenso can't sign documents without one. To use your own certificate, replace `/opt/documenso/cert.p12` on the volume (same passphrase) or set `NEXT_PRIVATE_SIGNING_LOCAL_FILE_CONTENTS` to its base64 contents.
2. **Migrations.** `prisma migrate deploy`, as upstream's start script does.
3. **First admin.** Documenso only lets verified emails sign in, so without SMTP a fresh install has no usable login. If `DOCUMENSO_ADMIN_EMAIL` and `DOCUMENSO_ADMIN_PASSWORD` are set and that account doesn't exist yet, the entrypoint signs it up through Documenso's own sign-up endpoint on a private side port, marks it verified and gives it the admin role. It runs once.
4. **Server.** Starts Documenso on `PORT` (3000) as the image's unprivileged `nodejs` user. Public sign-up is off by default (`NEXT_PUBLIC_DISABLE_SIGNUP=true`).

## Variables

| Variable | Default | Notes |
|---|---|---|
| `DOCUMENSO_ADMIN_EMAIL` | (you enter it) | Email of the first admin account |
| `DOCUMENSO_ADMIN_PASSWORD` | generated secret | Password of the first admin. Read it in the service's Variables tab. Changing it later doesn't change the account's password |
| `NEXTAUTH_SECRET`, `NEXT_PRIVATE_ENCRYPTION_KEY`, `NEXT_PRIVATE_ENCRYPTION_SECONDARY_KEY` | generated secrets | Keep them: changing the encryption keys makes stored secrets unreadable |
| `NEXT_PRIVATE_SIGNING_PASSPHRASE` | generated secret | Passphrase of the signing certificate on the volume |
| `NEXT_PRIVATE_DATABASE_URL` | `${{Postgres.DATABASE_URL}}` | Private network connection to Postgres |
| `NEXT_PUBLIC_WEBAPP_URL` | `https://${{RAILWAY_PUBLIC_DOMAIN}}` | Public URL. Update it if you add a custom domain |
| `NEXT_PUBLIC_DISABLE_SIGNUP` | `true` | Set to `false` to let anyone create an account |
| `PORT` | `3000` | Port Documenso listens on |

**Email (optional but recommended).** Documenso sends signing requests, invitations and password resets by email. Add your SMTP settings to the Documenso service to enable them: `NEXT_PRIVATE_SMTP_HOST`, `NEXT_PRIVATE_SMTP_PORT`, `NEXT_PRIVATE_SMTP_USERNAME`, `NEXT_PRIVATE_SMTP_PASSWORD`, `NEXT_PRIVATE_SMTP_FROM_ADDRESS` and `NEXT_PRIVATE_SMTP_FROM_NAME` (or Resend with `NEXT_PRIVATE_SMTP_TRANSPORT=resend` and `NEXT_PRIVATE_RESEND_API_KEY`). Without email you can still create documents and share signing links by hand. See [Documenso's environment variables](https://docs.documenso.com/docs/self-hosting/configuration/environment).

## Updates

The Documenso image is pinned in `Dockerfile`. A new Documenso release lands here as a PR that bumps the pin and adds a `CHANGELOG.md` entry. Once it's merged to `main`, Railway shows deployers an "update available" notice, and they choose when to apply it. Migrations run on boot.

## License

The wrapper in this repo is MIT. Documenso itself is AGPL-3.0, see [its repository](https://github.com/documenso/documenso).
