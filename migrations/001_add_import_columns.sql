-- Upgrade an existing jimcrow_db volume to the schema the import scripts expect.
-- Fresh installs do not need this: init-scripts/01-init-database.sql already
-- creates these columns. Safe to run more than once.
--
--   docker exec -i jimcrow_db psql -U jimcrow_user -d jimcrow_laws < migrations/001_add_import_columns.sql

BEGIN;

ALTER TABLE legal_documents
    ADD COLUMN IF NOT EXISTS entry_id VARCHAR(255),
    ADD COLUMN IF NOT EXISTS year INTEGER,
    ADD COLUMN IF NOT EXISTS citation TEXT,
    ADD COLUMN IF NOT EXISTS category VARCHAR(100),
    ADD COLUMN IF NOT EXISTS summary TEXT,
    ADD COLUMN IF NOT EXISTS keywords TEXT[],
    ADD COLUMN IF NOT EXISTS is_jim_crow VARCHAR(20),
    ADD COLUMN IF NOT EXISTS confidence DECIMAL(5,2),
    ADD COLUMN IF NOT EXISTS racial_indicator VARCHAR(50),
    ADD COLUMN IF NOT EXISTS needs_human_review BOOLEAN DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS reasoning TEXT,
    ADD COLUMN IF NOT EXISTS page_number INTEGER;

ALTER TABLE legal_documents ALTER COLUMN title TYPE TEXT;
ALTER TABLE legal_documents ALTER COLUMN jurisdiction SET DEFAULT 'Kentucky';

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'legal_documents_entry_id_key'
          AND conrelid = 'legal_documents'::regclass
    ) THEN
        ALTER TABLE legal_documents
            ADD CONSTRAINT legal_documents_entry_id_key UNIQUE (entry_id);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_legal_documents_year ON legal_documents(year);
CREATE INDEX IF NOT EXISTS idx_legal_documents_category ON legal_documents(category);
CREATE INDEX IF NOT EXISTS idx_legal_documents_is_jim_crow ON legal_documents(is_jim_crow);

COMMIT;
