-- ============================================================
-- Migration: 003_historico_contatos.sql
-- Tabela de histórico de contatos enviados pelos fluxos n8n.
-- Registra cada mensagem enviada com sucesso para auditoria
-- e futura análise de resposta/conversão.
-- ============================================================

CREATE TABLE IF NOT EXISTS historico_contatos (
  id               BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  aluno_id         UUID        REFERENCES alunos (id) ON DELETE CASCADE,
  tipo             TEXT        NOT NULL CHECK (tipo IN ('sdr', 'tutor', 'carrinho_abandonado', 'upsell')),
  mensagem_enviada TEXT,
  respondeu        BOOLEAN     DEFAULT FALSE,
  criado_em        TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_historico_aluno_id  ON historico_contatos (aluno_id);
CREATE INDEX IF NOT EXISTS idx_historico_tipo       ON historico_contatos (tipo);
CREATE INDEX IF NOT EXISTS idx_historico_criado_em  ON historico_contatos (criado_em);

ALTER TABLE historico_contatos ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Service role full access" ON historico_contatos
  FOR ALL USING (true);
