-- Drop old table if exists
DROP TABLE IF EXISTS public.report_embeddings;

-- Recreate table with 768 dimension (Gemini text-embedding-004)
CREATE TABLE IF NOT EXISTS public.report_embeddings (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    patient_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    report_id UUID,
    chunk_index INTEGER,
    chunk_text TEXT NOT NULL,
    embedding vector(768),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Recreate index
CREATE INDEX IF NOT EXISTS report_embeddings_embedding_idx ON public.report_embeddings USING hnsw (embedding vector_cosine_ops);

-- Create match_report_chunks function for similarity search
CREATE OR REPLACE FUNCTION match_report_chunks (
  query_embedding vector(768),
  match_threshold float,
  match_count int,
  p_patient_id uuid
)
RETURNS TABLE (
  id uuid,
  chunk_text text,
  similarity float
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT
    report_embeddings.id,
    report_embeddings.chunk_text,
    1 - (report_embeddings.embedding <=> query_embedding) AS similarity
  FROM report_embeddings
  WHERE report_embeddings.patient_id = p_patient_id
    AND 1 - (report_embeddings.embedding <=> query_embedding) > match_threshold
  ORDER BY report_embeddings.embedding <=> query_embedding
  LIMIT match_count;
END;
$$;
