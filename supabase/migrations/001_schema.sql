-- ============================================================
-- Migration: 001_schema.sql
-- Schema completo — automacao-alunos
-- 876 alunos · 11 produtos · 871 transações · R$ 23.548,30
-- ============================================================


-- ============================================================
-- ENUMs
-- ============================================================

CREATE TYPE status_aluno AS ENUM (
  'nunca_acessou',
  'inativo',
  'iniciante',
  'em_andamento',
  'quase_concluindo',
  'concluido'
);

CREATE TYPE metodo_pagamento AS ENUM (
  'PIX',
  'Cartao Credito',
  'Boleto',
  'Outro'
);


-- ============================================================
-- TABELA: produtos
-- ============================================================

CREATE TABLE IF NOT EXISTS produtos (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nome       TEXT NOT NULL UNIQUE,
  criado_em  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- ============================================================
-- TABELA: alunos
-- Chave de upsert: email (obrigatório no checkout Pagtrust)
-- ============================================================

CREATE TABLE IF NOT EXISTS alunos (
  id                       UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  nome                     TEXT        NOT NULL,
  email                    TEXT        NOT NULL UNIQUE,
  whatsapp                 TEXT,
  cidade                   TEXT,
  estado                   TEXT,
  status_aluno             status_aluno NOT NULL DEFAULT 'nunca_acessou',
  ultimo_contato_sdr       TIMESTAMPTZ,
  ultimo_contato_tutor     TIMESTAMPTZ,
  bloqueado_antipirataria  BOOLEAN     NOT NULL DEFAULT FALSE,
  criado_em                TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  atualizado_em            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_alunos_email    ON alunos (email);
CREATE INDEX IF NOT EXISTS idx_alunos_whatsapp ON alunos (whatsapp);
CREATE INDEX IF NOT EXISTS idx_alunos_status   ON alunos (status_aluno);

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


-- ============================================================
-- TABELA: transacoes
-- ============================================================

CREATE TABLE IF NOT EXISTS transacoes (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id          TEXT        NOT NULL UNIQUE,
  aluno_id          UUID        NOT NULL REFERENCES alunos (id) ON DELETE CASCADE,
  valor             NUMERIC(10, 2) NOT NULL,
  status            TEXT        NOT NULL,
  metodo_pagamento  metodo_pagamento,
  dados_raw         JSONB,
  criado_em         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_transacoes_aluno_id ON transacoes (aluno_id);
CREATE INDEX IF NOT EXISTS idx_transacoes_order_id ON transacoes (order_id);
CREATE INDEX IF NOT EXISTS idx_transacoes_status   ON transacoes (status);


-- ============================================================
-- TABELA: aluno_produtos
-- Substitui progresso_aulas. Relacionamento N:N aluno ↔ produto.
-- ============================================================

CREATE TABLE IF NOT EXISTS aluno_produtos (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  aluno_id       UUID NOT NULL REFERENCES alunos   (id) ON DELETE CASCADE,
  produto_id     UUID NOT NULL REFERENCES produtos (id) ON DELETE CASCADE,
  progresso_pct  INT  NOT NULL DEFAULT 0 CHECK (progresso_pct BETWEEN 0 AND 100),
  ultimo_acesso  TIMESTAMPTZ,
  UNIQUE (aluno_id, produto_id)
);

CREATE INDEX IF NOT EXISTS idx_aluno_produtos_aluno   ON aluno_produtos (aluno_id);
CREATE INDEX IF NOT EXISTS idx_aluno_produtos_produto ON aluno_produtos (produto_id);


-- ============================================================
-- VIEW: v_alunos_sdr_prioridade
-- Alunos nunca_acessou ou inativo com whatsapp.
-- Deduplica por aluno: agrega produtos, pega menor progresso.
-- Usada pelo Fluxo 02 — SDR IA.
-- ============================================================

CREATE OR REPLACE VIEW v_alunos_sdr_prioridade AS
SELECT
  a.id,
  a.nome,
  a.email,
  a.whatsapp,
  a.status_aluno,
  a.ultimo_contato_sdr,
  STRING_AGG(p.nome, ', ' ORDER BY p.nome)  AS produtos,
  MIN(ap.progresso_pct)                     AS menor_progresso,
  MAX(t.valor)                              AS maior_valor,
  MAX(t.criado_em)                          AS ultima_compra
FROM alunos a
JOIN aluno_produtos ap ON ap.aluno_id = a.id
JOIN produtos p        ON p.id        = ap.produto_id
LEFT JOIN transacoes t ON t.aluno_id  = a.id
WHERE a.status_aluno IN ('nunca_acessou', 'inativo')
  AND a.whatsapp IS NOT NULL
  AND a.bloqueado_antipirataria = FALSE
GROUP BY a.id, a.nome, a.email, a.whatsapp, a.status_aluno, a.ultimo_contato_sdr;


-- ============================================================
-- VIEW: v_alunos_tutor_acompanhamento
-- Alunos em progresso com whatsapp.
-- Deduplica por aluno: agrega produtos, pega menor progresso
-- e maior ultimo_acesso (mais recente entre todos os produtos).
-- Usada pelo Fluxo 03 — Tutor IA.
-- ============================================================

CREATE OR REPLACE VIEW v_alunos_tutor_acompanhamento AS
SELECT
  a.id,
  a.nome,
  a.email,
  a.whatsapp,
  a.status_aluno,
  a.ultimo_contato_tutor,
  STRING_AGG(p.nome, ', ' ORDER BY p.nome)            AS produtos,
  MIN(ap.progresso_pct)                               AS menor_progresso,
  MAX(ap.ultimo_acesso)                               AS ultimo_acesso,
  EXTRACT(DAY FROM NOW() - MAX(ap.ultimo_acesso))::INT AS dias_sem_acesso
FROM alunos a
JOIN aluno_produtos ap ON ap.aluno_id = a.id
JOIN produtos p        ON p.id        = ap.produto_id
WHERE a.status_aluno IN ('iniciante', 'em_andamento', 'quase_concluindo')
  AND a.whatsapp IS NOT NULL
  AND a.bloqueado_antipirataria = FALSE
GROUP BY a.id, a.nome, a.email, a.whatsapp, a.status_aluno, a.ultimo_contato_tutor;


-- ============================================================
-- VIEW: v_alunos_upsell
-- Alunos com ao menos um produto 100% concluído.
-- Agrega todos os cursos concluídos por aluno.
-- ============================================================

CREATE OR REPLACE VIEW v_alunos_upsell AS
SELECT
  a.id,
  a.nome,
  a.email,
  a.whatsapp,
  STRING_AGG(p.nome, ', ' ORDER BY p.nome) AS cursos_concluidos,
  COUNT(ap.id)                             AS total_concluidos
FROM alunos a
JOIN aluno_produtos ap ON ap.aluno_id = a.id AND ap.progresso_pct = 100
JOIN produtos p        ON p.id        = ap.produto_id
WHERE a.bloqueado_antipirataria = FALSE
GROUP BY a.id, a.nome, a.email, a.whatsapp;
