# Shared data folder

Docker Compose bind-mounts this directory to `/data` inside the Lens container.

Drop files here, then attach them in **Settings** as DuckDB extra sources:

| Kind | Path in Lens |
| --- | --- |
| CSV | `/data/orders.csv` |
| Parquet | `/data/events.parquet` |
| JSON | `/data/payload.json` |
| SQLite | `/data/app.sqlite` |
| DuckDB | `/data/warehouse.duckdb` |

The container process runs as `nobody`. Files must be world-readable (`chmod a+r`).

Override the host path:

```sh
LENS_SHARED_DIR=/path/to/exports docker compose up
```
