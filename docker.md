# Standalone Docker

Run Lens as its own app against Postgres, without mounting it in a Phoenix host.

Image: [`oivoodoo/phoenix_lens`](https://hub.docker.com/r/oivoodoo/phoenix_lens).

```sh
docker run --rm -p 8080:8080 \
  -e POSTGRES_HOST=host.docker.internal \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=app \
  oivoodoo/phoenix_lens
```

Open [http://localhost:8080/lens](http://localhost:8080/lens). The first visit is **Set up Lens**: create the operator username and password you will use to sign in.

On Linux, pass `--add-host=host.docker.internal:host-gateway` so `POSTGRES_HOST=host.docker.internal` reaches Postgres on the host.

Or with Compose from this repo (Postgres + a **shared folder** at `./data` → `/data`):

```sh
mkdir -p data
docker compose up --build
```

Drop CSV, Parquet, JSON, SQLite, or DuckDB files into `./data`. In **Settings → Sources** attach them as `/data/yourfile.csv` (same for `.parquet`, `.json`, `.sqlite`, `.duckdb`).

Using only the published image, copy [examples/docker-compose.yml](../examples/docker-compose.yml):

```sh
mkdir -p data
docker compose -f examples/docker-compose.yml up
```

Point the shared folder at another host directory with `LENS_SHARED_DIR=/path/to/exports`. Files must be world-readable; the container runs as `nobody`.

## Environment

| Variable | Required | Default | Purpose |
| --- | --- | --- | --- |
| `DATABASE_URL` | one of URL or host | | `postgres://user:pass@host:5432/db` |
| `POSTGRES_HOST` | one of URL or host | | Hostname when not using `DATABASE_URL` |
| `POSTGRES_PORT` | | `5432` | |
| `POSTGRES_USER` | | `postgres` | |
| `POSTGRES_PASSWORD` | | | |
| `POSTGRES_DB` | | `postgres` | |
| `PORT` | | `8080` | HTTP listen port |
| `PHX_HOST` | | `localhost` | Public hostname for URLs and passkeys |
| `PHX_SCHEME` | | `http` | `https` behind a TLS proxy |
| `SECRET_KEY_BASE` | recommended | random | Cookie signing; generate with `mix phx.gen.secret`. If omitted, sessions reset when the container restarts. |
| `HTTP_BASIC_USERNAME` / `HTTP_BASIC_PASSWORD` | | | Extra HTTP basic auth (also `PHOENIX_LENS_*` and `BASIC_AUTH_*`) |
| `SMTP_HOST` + `SMTP_FROM` | | | Enable email verification and email 2FA |
| `SMTP_PORT` | | `587` | |
| `SMTP_USERNAME` / `SMTP_PASSWORD` | | | |
| `SMTP_TLS` | | `true` | |
| `POSTGRES_SSL` | | `false` | `true` to require SSL to Postgres |
| `POOL_SIZE` | | `5` | Ecto pool |
| `LENS_SHARED_DIR` | Compose | `./data` | Host folder bind-mounted to `/data` |
| `LENS_DATA_DIR` | | `/data` | Path inside the container (informational) |

`PHOENIX_LENS_DATABASE_URL` is an alias for `DATABASE_URL`. `PGHOST` / `PGUSER` / `PGPASSWORD` / `PGDATABASE` / `PGPORT` also work.

## First boot

1. Lens creates its metadata tables on the configured database (`phoenix_lens_*`).
2. `/lens/setup` asks for the **operator** username and password (min 10 characters).
3. If SMTP env vars are set, it also asks for an email, sends a 6-digit code, and stores the verified address. Later sign-ins send a new code (email 2FA).
4. If HTTP basic env vars are set, the browser asks for that user/password *before* the operator login.

This operator login exists only in standalone mode. When you mount Lens in a Phoenix app, keep using the host pipeline.

To reset the operator, delete the row:

```sql
DELETE FROM phoenix_lens_operators;
```

Then reopen `/lens/setup`. `PhoenixLens.Auth.reset!()` still clears TOTP/passkeys only.

## Build and publish

Tag the image with the Lens version from `mix.exs` (`@version`) and push both that tag and `latest` to Docker Hub:

```sh
VERSION=$(awk -F '"' '/@version /{print $2; exit}' mix.exs)

docker build -t oivoodoo/phoenix_lens:$VERSION -t oivoodoo/phoenix_lens:latest .
docker login
docker push oivoodoo/phoenix_lens:$VERSION
docker push oivoodoo/phoenix_lens:latest
```

GitHub Actions (`.github/workflows/docker.yml`) builds on `main` and version tags.

Pushing from CI needs a **Docker Hub personal access token** with **Read & Write** (or Read, Write, Delete). An account password or a read-only token fails with `401 Unauthorized: access token has insufficient scopes`.

1. [hub.docker.com](https://hub.docker.com) → Account Settings → Personal access tokens → Generate
2. Access permissions: **Read & Write**
3. GitHub repo → Settings → Secrets and variables → Actions:

   - `DOCKERHUB_USERNAME` — Hub username (`oivoodoo`)
   - `DOCKERHUB_TOKEN` — the access token, not the account password

Then re-run the failed Docker workflow.

Health check: `GET /health` returns `200 ok` when Postgres answers.

## macOS desktop (Electron)

Yes — you can wrap the same standalone release in Electron as a Mac `.app`. Electron is only a window: it starts the Mix release as a child process, waits for `GET /health`, and loads `http://127.0.0.1:$PORT/lens`.

That is a **separate** packaging job from Docker. Constraints:

| Piece | Reality |
| --- | --- |
| Elixir | Build a **macOS** Mix release (`MIX_ENV=prod mix release`) on a Mac. DuckDB’s NIF is platform-specific; you cannot reuse the Linux Docker image inside Electron. |
| Postgres | Still required for questions, operator login, and audit. Ship Postgres.app / a local Postgres, or point `DATABASE_URL` at an existing server. Embedding Postgres inside the `.app` is a different project. |
| Distribution | `electron-builder` can make a `.dmg`. Notarization and Apple Developer signing are required for other people’s Macs. The App Store is a poor fit (unsigned ERTS helper, local HTTP server). |
| Lighter option | Skip Electron and open the browser after `mix phoenix_lens.server` / Docker. Same app, no Chromium bundle (~150MB+). |

A typical Electron main process:

1. `spawn` `rel/phoenix_lens/bin/server` with `PORT`, `POSTGRES_*` / `DATABASE_URL`, `PHX_HOST=127.0.0.1`
2. Poll `http://127.0.0.1:$PORT/health` until `200`
3. `BrowserWindow` → `http://127.0.0.1:$PORT/lens`
4. On quit, SIGTERM the release

Say if you want that wrapper scaffolded in-repo (`desktop/` + `electron-builder` for `darwin-arm64`).
