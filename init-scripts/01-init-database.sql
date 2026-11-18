-- Initialize Jim Crow Laws Database
-- This script runs automatically when the database is first created

-- Create extensions we might need
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Create tables for storing legal documents and analysis
CREATE TABLE IF NOT EXISTS legal_documents (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- Stable ID from the processing pipeline; import scripts rely on
    -- ON CONFLICT (entry_id) to skip duplicates, so it must be UNIQUE.
    entry_id VARCHAR(255) UNIQUE,
    -- TEXT rather than VARCHAR(500): some LLM-generated titles exceed 500 chars.
    title TEXT NOT NULL,
    source_file VARCHAR(255),
    document_type VARCHAR(100),
    jurisdiction VARCHAR(100) DEFAULT 'Kentucky',
    year INTEGER,
    date_enacted DATE,
    date_repealed DATE,
    citation TEXT,
    category VARCHAR(100),
    summary TEXT,
    keywords TEXT[],
    full_text TEXT,
    is_jim_crow VARCHAR(20),
    confidence DECIMAL(5,2),
    racial_indicator VARCHAR(50),
    needs_human_review BOOLEAN DEFAULT FALSE,
    reasoning TEXT,
    page_number INTEGER,
    ocr_confidence DECIMAL(5,2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create table for document classifications
CREATE TABLE IF NOT EXISTS document_classifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    document_id UUID REFERENCES legal_documents(id) ON DELETE CASCADE,
    classification_type VARCHAR(100) NOT NULL,
    classification_value TEXT NOT NULL,
    confidence_score DECIMAL(5,2),
    model_used VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create table for extracted entities (people, places, dates, etc.)
CREATE TABLE IF NOT EXISTS extracted_entities (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    document_id UUID REFERENCES legal_documents(id) ON DELETE CASCADE,
    entity_type VARCHAR(50) NOT NULL,
    entity_text VARCHAR(500) NOT NULL,
    start_position INTEGER,
    end_position INTEGER,
    confidence_score DECIMAL(5,2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indices for better performance
CREATE INDEX IF NOT EXISTS idx_legal_documents_title ON legal_documents(title);
CREATE INDEX IF NOT EXISTS idx_legal_documents_type ON legal_documents(document_type);
CREATE INDEX IF NOT EXISTS idx_legal_documents_jurisdiction ON legal_documents(jurisdiction);
CREATE INDEX IF NOT EXISTS idx_legal_documents_date_enacted ON legal_documents(date_enacted);
CREATE INDEX IF NOT EXISTS idx_legal_documents_year ON legal_documents(year);
CREATE INDEX IF NOT EXISTS idx_legal_documents_category ON legal_documents(category);
CREATE INDEX IF NOT EXISTS idx_legal_documents_is_jim_crow ON legal_documents(is_jim_crow);
CREATE INDEX IF NOT EXISTS idx_document_classifications_type ON document_classifications(classification_type);
CREATE INDEX IF NOT EXISTS idx_extracted_entities_type ON extracted_entities(entity_type);

-- Create full-text search index
CREATE INDEX IF NOT EXISTS idx_legal_documents_fulltext ON legal_documents USING gin(to_tsvector('english', full_text));

-- Insert some sample data for testing
INSERT INTO legal_documents (title, document_type, jurisdiction, date_enacted, full_text) VALUES
('Sample Jim Crow Law', 'State Statute', 'Kentucky', '1885-03-15', 'This is a sample legal document text for testing purposes.'),
('Sample Constitution Article', 'Constitutional Amendment', 'Kentucky', '1891-05-20', 'Sample constitutional text regarding voting rights and civil liberties.')
ON CONFLICT DO NOTHING;

-- Grant necessary permissions
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO jimcrow_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO jimcrow_user;