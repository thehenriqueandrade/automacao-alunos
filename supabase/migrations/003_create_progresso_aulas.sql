-- Migration: 003 — Tabela progresso_aulas
-- Rastreia quais aulas cada aluno acessou/concluiu.

CREATE TABLE IF NOT EXISTS progresso_aulas (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    aluno_id        UUID NOT NULL REFERENCES alunos (id) ON DELETE CASCADE,
    aula_concluida  TEXT NOT NULL,      -- Identificador da aula (ex: "modulo-1/aula-3")
    data_acesso     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_progresso_aluno_id    ON progresso_aulas (aluno_id);
CREATE INDEX IF NOT EXISTS idx_progresso_data_acesso ON progresso_aulas (data_acesso);

-- View auxiliar: último acesso por aluno (usada pelo Fluxo Tutor no n8n)
CREATE OR REPLACE VIEW v_ultimo_acesso_aluno AS
SELECT
    a.id          AS aluno_id,
    a.nome,
    a.whatsapp,
    MAX(p.data_acesso)                                    AS ultimo_acesso,
    EXTRACT(DAY FROM NOW() - MAX(p.data_acesso))::INT     AS dias_sem_acesso,
    COUNT(p.id)                                           AS total_aulas_acessadas
FROM alunos a
LEFT JOIN progresso_aulas p ON p.aluno_id = a.id
GROUP BY a.id, a.nome, a.whatsapp;
