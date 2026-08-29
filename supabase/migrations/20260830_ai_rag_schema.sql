-- Enable pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- Table for storing report embeddings
CREATE TABLE IF NOT EXISTS public.report_embeddings (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    patient_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    report_id UUID, -- If there's a reports table, it can reference it, else just UUID
    chunk_index INTEGER,
    chunk_text TEXT NOT NULL,
    embedding vector(1536), -- Dimension based on typical text embeddings
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index for similarity search
CREATE INDEX IF NOT EXISTS report_embeddings_embedding_idx ON public.report_embeddings USING hnsw (embedding vector_cosine_ops);

-- Table for unified chat history (Persistent memory)
CREATE TABLE IF NOT EXISTS public.chat_history (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('patient', 'doctor', 'admin')),
    sender TEXT NOT NULL CHECK (sender IN ('user', 'bot', 'assistant')),
    message TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes for efficient history retrieval
CREATE INDEX IF NOT EXISTS chat_history_user_id_idx ON public.chat_history(user_id);
CREATE INDEX IF NOT EXISTS chat_history_role_idx ON public.chat_history(role);
CREATE INDEX IF NOT EXISTS chat_history_created_at_idx ON public.chat_history(created_at);
