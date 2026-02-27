-- Migration: 002 — Tabela transacoes
-- Registra todas as transações recebidas via Pagtrust.

CREATE TABLE IF NOT EXISTS transacoes (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id    TEXT NOT NULL UNIQUE,
    aluno_id    UUID NOT NULL REFERENCES alunos (id) ON DELETE CASCADE,
    valor       NUMERIC(10, 2) NOT NULL,
    status      TEXT NOT NULL,          -- Ex: APPROVED, REFUSED, REFUNDED
    criado_em   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    dados_raw   JSONB                    -- Payload original da Pagtrust (para auditoria)
);

CREATE INDEX IF NOT EXISTS idx_transacoes_aluno_id ON transacoes (aluno_id);
CREATE INDEX IF NOT EXISTS idx_transacoes_order_id ON transacoes (order_id);
CREATE INDEX IF NOT EXISTS idx_transacoes_status   ON transacoes (status);
