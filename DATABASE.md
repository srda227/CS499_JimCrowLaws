# Database Setup & Reference

This document covers everything you need to know about the PostgreSQL database used by the Jim Crow Laws project — from first-time setup to schema details, import scripts, and the API server.

---

## Overview

The project uses **PostgreSQL 16** running inside a Docker container. A second container runs **pgAdmin 4**, a browser-based GUI for inspecting and querying the database. Both containers are managed by a single `docker-compose.yml` file.

| Container name   | Purpose                     | Default port |
|------------------|-----------------------------|--------------|
| `jimcrow_db`     | PostgreSQL 16 database      | `5432`       |
| `jimcrow_pgadmin`| pgAdmin 4 web UI            | `8080`       |

---

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (includes Docker Compose)
- Python 3.9+ with `pip`

---

## Step 1 — Configure Environment Variables

All database credentials are read from a `.env` file in the project root. This file is **not** committed to version control.

Copy the example file and fill in your values:

```bash
cp .env.example .env
```

Then open `.env` and set:

```ini
# PostgreSQL
POSTGRES_DB=jimcrow_laws          # name of the database
POSTGRES_USER=jimcrow_user        # database username
POSTGRES_PASSWORD=change_me       # strong password of your choice
POSTGRES_PORT=5432                # host port mapped to the container

# pgAdmin 4
PGADMIN_EMAIL=admin@example.com   # login email for the pgAdmin web UI
PGADMIN_PASSWORD=change_me        # login password for pgAdmin
PGADMIN_PORT=8080                 # host port for pgAdmin

# Full connection URL (used by some tools)
DATABASE_URL=postgresql://jimcrow_user:change_me@localhost:5432/jimcrow_laws
```

> **Security note:** Never commit `.env` to Git. The `.gitignore` should already exclude it.

---

## Step 2 — Start the Database

From the project root, run:

```bash
docker compose up -d
```

Docker will:
1. Pull `postgres:16-alpine` and `dpage/pgadmin4` images (first run only).
2. Create a named volume `postgres_data` for persistent storage.
3. Execute every `.sql` file in `init-scripts/` exactly once (first run only).
4. Start both containers in the background.

**Verify the containers are healthy:**

```bash
docker compose ps
```

Both `jimcrow_db` and `jimcrow_pgadmin` should show `healthy` / `running`.

**Stop the containers (data is preserved):**

```bash
docker compose down
```

**Stop and delete all data (full reset):**

```bash
docker compose down -v
```

---

## Step 3 — Database Initialisation

The file `init-scripts/01-init-database.sql` runs automatically the very first time the `postgres` container starts. It:

- Enables the `uuid-ossp` extension (UUID generation) and `pg_trgm` extension (trigram full-text search).
- Creates the three core tables: `legal_documents`, `document_classifications`, `extracted_entities`.
- Creates all indexes (B-tree and GIN full-text).
- Grants full privileges on all tables and sequences to `jimcrow_user`.

> **Important:** If the `postgres_data` Docker volume already exists, this script will **not** re-run. To re-initialise from scratch, run `docker compose down -v` first to delete the volume.

**Upgrading an existing database:** if your volume was created before the import columns were added (imports fail with `column "entry_id" does not exist` or `there is no unique or exclusion constraint matching the ON CONFLICT specification`), apply the migration instead of deleting your data:

```bash
docker exec -i jimcrow_db psql -U jimcrow_user -d jimcrow_laws < migrations/001_add_import_columns.sql
```

It is safe to run more than once.

---

## Database Schema

### `legal_documents` (primary table)

This is the main table queried by the API and search UI. Every imported statute entry lands here.

| Column              | Type              | Description |
|---------------------|-------------------|-------------|
| `id`                | UUID (PK)         | Auto-generated unique ID |
| `entry_id`          | VARCHAR (UNIQUE)  | Stable ID from the processing pipeline, e.g. `gen_assemb_1865_p87_s1`. Used to prevent duplicate imports. |
| `title`             | TEXT              | Short descriptive title of the statute or section |
| `source_file`       | VARCHAR(255)      | Original filename (e.g. `Gen Assemb 1865_results_classified.json`) |
| `document_type`     | VARCHAR(100)      | Type of source document: `session_laws`, `constitution`, `codes`, `amendments`, `criminal_laws`, `civil_laws`, `other` |
| `year`              | INTEGER           | Year the law was enacted |
| `date_enacted`      | DATE              | Set to `YYYY-01-01` based on `year` |
| `citation`          | TEXT              | Full legal citation string |
| `category`          | VARCHAR(100)      | Jim Crow category: `education`, `voting`, `transportation`, `public_accommodations`, `employment`, `marriage`, `other`, etc. |
| `summary`           | TEXT              | One-to-two sentence LLM-generated summary |
| `keywords`          | TEXT[]            | Array of racial/legal keywords found in the text |
| `full_text`         | TEXT              | Raw OCR text of the statute section |
| `is_jim_crow`       | VARCHAR(20)       | Classification result: `yes`, `no`, or `ambiguous` |
| `confidence`        | DECIMAL(5,2)      | LLM confidence score (0.0 – 1.0) |
| `racial_indicator`  | VARCHAR(50)       | How race is referenced: `explicit`, `implicit`, `none` |
| `needs_human_review`| BOOLEAN           | `true` if the LLM flagged this entry as ambiguous or low-confidence |
| `reasoning`         | TEXT              | LLM's internal reasoning for the classification |
| `page_number`       | INTEGER           | Page number in the source document |
| `jurisdiction`      | VARCHAR(100)      | Jurisdiction (default: Kentucky) |
| `ocr_confidence`    | DECIMAL(5,2)      | Confidence score from the OCR engine |
| `created_at`        | TIMESTAMP         | Row creation time |
| `updated_at`        | TIMESTAMP         | Last update time |

**Indexes on `legal_documents`:**
- `idx_legal_documents_title` — B-tree on `title`
- `idx_legal_documents_type` — B-tree on `document_type`
- `idx_legal_documents_jurisdiction` — B-tree on `jurisdiction`
- `idx_legal_documents_date_enacted` — B-tree on `date_enacted`
- `idx_legal_documents_fulltext` — GIN index on `to_tsvector('english', full_text)` for fast full-text search

---

### `document_classifications`

Stores individual LLM classification tags attached to a document. Links back to `legal_documents` via a foreign key.

| Column                | Type         | Description |
|-----------------------|--------------|-------------|
| `id`                  | UUID (PK)    | Auto-generated |
| `document_id`         | UUID (FK)    | References `legal_documents.id` |
| `classification_type` | VARCHAR(100) | Type of classification (e.g. `category`, `sentiment`) |
| `classification_value`| TEXT         | The classification result |
| `confidence_score`    | DECIMAL(5,2) | Confidence of this specific classification |
| `model_used`          | VARCHAR(100) | Name/version of the model that produced this result |
| `created_at`          | TIMESTAMP    | Row creation time |

---

### `extracted_entities`

Stores named entities (people, places, dates, organisations) extracted from document text.

| Column           | Type         | Description |
|------------------|--------------|-------------|
| `id`             | UUID (PK)    | Auto-generated |
| `document_id`    | UUID (FK)    | References `legal_documents.id` |
| `entity_type`    | VARCHAR(50)  | e.g. `PERSON`, `LOCATION`, `DATE`, `ORG` |
| `entity_text`    | VARCHAR(500) | The extracted text span |
| `start_position` | INTEGER      | Character offset (start) in `full_text` |
| `end_position`   | INTEGER      | Character offset (end) in `full_text` |
| `confidence_score`| DECIMAL(5,2)| Extraction confidence |
| `created_at`     | TIMESTAMP    | Row creation time |

---

## Step 4 — Import Processed Data

After running the OCR and document-processing pipeline, classified JSON files land in `doc_processing_results/`. Use the import scripts below to load them into the database.

### Install Python dependencies

```bash
pip install psycopg2-binary python-dotenv
```

### Import a single file

```bash
python import_classified.py doc_processing_results/Gen_Assemb_1865_results_classified.json
```

If no path argument is given, it defaults to `doc_processing_results/classified_results.json`.

### Import all files at once

```bash
python import_all.py
```

This scans `doc_processing_results/` for every file matching `*_results_classified.json` and imports them all. It prints a table showing how many rows were inserted vs. skipped (duplicates) per file.

**Both scripts:**
- Only import entries where `is_jim_crow == "yes"`.
- Use `ON CONFLICT (entry_id) DO NOTHING` — re-running is safe; duplicates are skipped, not duplicated.
- Strip NUL bytes (`\x00`) from OCR text before inserting, since PostgreSQL rejects them.

---

## Step 5 — Run the API Server

The Flask API server connects to the database and serves the search UI.

### Install dependencies

```bash
pip install flask flask-cors psycopg2-binary python-dotenv
```

### Start the server

```bash
python api_server.py
```

The server reads database credentials from `.env` and connects to `localhost:5432`. On startup it prints whether the database connection succeeded.

| URL | Description |
|-----|-------------|
| `http://localhost:5000/` | Search UI (serves `index.html`) |
| `http://localhost:5000/search` | Search endpoint (query params below) |
| `http://localhost:5000/categories` | Returns all distinct categories in the database |
| `http://localhost:5000/keywords` | Returns all distinct keywords in the database |
| `http://localhost:5000/health` | Returns `{"status":"healthy"}` if DB is reachable |

### `/search` query parameters

| Parameter  | Type    | Description |
|------------|---------|-------------|
| `keyword`  | string  | Full-text search across title, summary, full_text, and keywords |
| `category` | string  | Filter by category (use `all` or omit for no filter) |
| `year_from`| integer | Earliest year (inclusive) |
| `year_to`  | integer | Latest year (inclusive) |
| `page`     | integer | Page number (default `1`) |
| `limit`    | integer | Results per page (default `50`) |

Example:
```
GET http://localhost:5000/search?keyword=school&category=education&year_from=1870&year_to=1920&page=1&limit=25
```

---

## pgAdmin 4 (Browser-based DB GUI)

Once the containers are running, open pgAdmin at:

```
http://localhost:8080
```

Log in with the `PGADMIN_EMAIL` and `PGADMIN_PASSWORD` values from your `.env`.

**Connect pgAdmin to the database:**

1. In the left panel, right-click **Servers → Register → Server…**
2. Fill in the **General** tab → Name: `jimcrow_db`
3. Fill in the **Connection** tab:
   - Host: `postgres` *(use the Docker service name, not `localhost`)*
   - Port: `5432`
   - Maintenance database: value of `POSTGRES_DB`
   - Username: value of `POSTGRES_USER`
   - Password: value of `POSTGRES_PASSWORD`
4. Click **Save**.

You can now browse tables, run SQL queries, and inspect data through the GUI.

---

## Useful Commands

```bash
# View live container logs
docker compose logs -f postgres

# Connect to the database directly via psql
docker exec -it jimcrow_db psql -U jimcrow_user -d jimcrow_laws

# Count total Jim Crow entries
docker exec -it jimcrow_db psql -U jimcrow_user -d jimcrow_laws \
  -c "SELECT COUNT(*) FROM legal_documents WHERE is_jim_crow = 'yes';"

# Check row counts by year
docker exec -it jimcrow_db psql -U jimcrow_user -d jimcrow_laws \
  -c "SELECT year, COUNT(*) FROM legal_documents WHERE is_jim_crow='yes' GROUP BY year ORDER BY year;"

# Check row counts by category
docker exec -it jimcrow_db psql -U jimcrow_user -d jimcrow_laws \
  -c "SELECT category, COUNT(*) FROM legal_documents WHERE is_jim_crow='yes' GROUP BY category ORDER BY COUNT(*) DESC;"

# List all table names
docker exec -it jimcrow_db psql -U jimcrow_user -d jimcrow_laws \
  -c "\dt"
```

---

## Troubleshooting

### `psycopg2.OperationalError: could not connect to server`
- Make sure the Docker containers are running: `docker compose ps`
- Make sure `POSTGRES_PORT` in `.env` matches the port in `docker-compose.yml` (default `5432`)
- Make sure you're connecting to `localhost`, not `postgres` (the Docker service name is only used container-to-container)

### `role "jimcrow_user" does not exist`
The database was initialised before the `POSTGRES_USER` env var was set. Run `docker compose down -v` to delete the volume and re-run `docker compose up -d`.

### Import script says `0 inserted`
- Check that the JSON files are in `doc_processing_results/` and end in `_results_classified.json`
- Check that at least some entries have `"is_jim_crow": "yes"` — only those are imported
- If you already imported the file once, re-running will report `0 inserted, N skipped` (this is correct behaviour)

### pgAdmin cannot connect using `localhost`
Inside the Docker network, pgAdmin must reach the database using the service name `postgres`, not `localhost`. See the pgAdmin connection instructions above.

---

## Data Flow Summary

```
Scanned PDF
    │
    ▼
OCR (ocr/jim_crow_ocr.py)
    │  → ocr_results/*_results.json
    ▼
Document Processing (doc_processing/processor.py)
    │  → doc_processing_results/*_results_classified.json
    ▼
Human Review (reviewer/reviewer_ui.py)
    │  → corrections saved back to classified JSON
    ▼
Database Import (import_all.py  or  import_classified.py)
    │  → legal_documents table in PostgreSQL
    ▼
API Server (api_server.py)  +  Search UI (index.html)
```
