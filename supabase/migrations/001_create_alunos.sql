-- Migration: 001 — Tabela alunos
-- Cadastro único de cada aluno/lead no ecossistema.

CREATE TABLE IF NOT EXISTS alunos (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nome        TEXT NOT NULL,
    whatsapp    TEXT NOT NULL UNIQUE,
    email       TEXT,
    criado_em   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    atualizado_em TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Índice para buscas por WhatsApp (chave de entrada dos fluxos n8n)
CREATE INDEX IF NOT EXISTS idx_alunos_whatsapp ON alunos (whatsapp);

-- Trigger para manter atualizado_em sincronizado
CREATE OR REPLACE FUNCTION set_atualizado_em()
RETURNS TRIGGER AS $$
BEGIN
    NEW.atualizado_em = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_alunos_atualizado_em
    BEFORE UPDATE ON alunos
    FOR EACH ROW EXECUTE FUNCTION set_atualizado_em();
