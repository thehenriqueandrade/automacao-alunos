-- ============================================================
-- Migration: 002_cooldown_antispam.sql
-- Reescreve as views SDR e Tutor com cooldown anti-spam de 7 dias
-- e adiciona v_pix_abandonados para o Fluxo 04.
-- ============================================================


-- ============================================================
-- VIEW: v_alunos_sdr_prioridade (com cooldown 7 dias)
-- Exclui alunos contatados (SDR ou Tutor) nos últimos 7 dias.
-- Ordenada por contato mais antigo primeiro (NULLS FIRST = nunca contatados primeiro).
-- ============================================================

DROP VIEW IF EXISTS v_alunos_sdr_prioridade;
CREATE VIEW v_alunos_sdr_prioridade AS
SELECT
  a.id,
  a.nome,
  a.email,
  a.whatsapp,
  a.status_aluno,
  a.ultimo_contato_sdr,
  STRING_AGG(p.nome, ', ' ORDER BY p.nome) AS produtos,
  MIN(ap.progresso_pct)                    AS menor_progresso,
  SUM(t.valor)                             AS valor_total,
  MIN(t.criado_em)                         AS data_compra
FROM alunos a
JOIN aluno_produtos ap ON ap.aluno_id = a.id
JOIN produtos p        ON p.id        = ap.produto_id
LEFT JOIN transacoes t ON t.aluno_id  = a.id
WHERE
  a.status_aluno IN ('nunca_acessou', 'inativo')
  AND a.whatsapp IS NOT NULL
  AND a.bloqueado_antipirataria = FALSE
  AND (
    a.ultimo_contato_sdr IS NULL
    OR a.ultimo_contato_sdr < now() - interval '7 days'
  )
  AND (
    a.ultimo_contato_tutor IS NULL
    OR a.ultimo_contato_tutor < now() - interval '7 days'
  )
GROUP BY a.id, a.nome, a.email, a.whatsapp, a.status_aluno, a.ultimo_contato_sdr
ORDER BY a.ultimo_contato_sdr ASC NULLS FIRST;


-- ============================================================
-- VIEW: v_alunos_tutor_acompanhamento (com cooldown 7 dias + prioridade)
-- Exclui alunos contatados (SDR ou Tutor) nos últimos 7 dias.
-- Ordenada por prioridade (quase_concluindo > em_andamento > iniciante)
-- e por menor progresso (quem mais precisa de apoio vem primeiro).
-- ============================================================

DROP VIEW IF EXISTS v_alunos_tutor_acompanhamento;
CREATE VIEW v_alunos_tutor_acompanhamento AS
SELECT
  a.id,
  a.nome,
  a.email,
  a.whatsapp,
  a.status_aluno,
  a.ultimo_contato_tutor,
  STRING_AGG(p.nome, ', ' ORDER BY p.nome)             AS produtos,
  MIN(ap.progresso_pct)                                AS menor_progresso,
  MAX(ap.ultimo_acesso)                                AS ultimo_acesso,
  EXTRACT(DAY FROM now() - MAX(ap.ultimo_acesso))::INT AS dias_sem_acesso,
  CASE a.status_aluno
    WHEN 'quase_concluindo' THEN 1
    WHEN 'em_andamento'     THEN 2
    WHEN 'iniciante'        THEN 3
  END                                                  AS prioridade
FROM alunos a
JOIN aluno_produtos ap ON ap.aluno_id = a.id
JOIN produtos p        ON p.id        = ap.produto_id
WHERE
  a.status_aluno IN ('iniciante', 'em_andamento', 'quase_concluindo')
  AND a.whatsapp IS NOT NULL
  AND a.bloqueado_antipirataria = FALSE
  AND (
    a.ultimo_contato_tutor IS NULL
    OR a.ultimo_contato_tutor < now() - interval '7 days'
  )
  AND (
    a.ultimo_contato_sdr IS NULL
    OR a.ultimo_contato_sdr < now() - interval '7 days'
  )
GROUP BY a.id, a.nome, a.email, a.whatsapp, a.status_aluno, a.ultimo_contato_tutor
ORDER BY prioridade ASC, menor_progresso DESC;


-- ============================================================
-- VIEW: v_pix_abandonados
-- PIX gerados há mais de 1h e menos de 24h, ainda não aprovados,
-- cujo aluno não foi contatado nas últimas 24h.
-- Um registro por aluno (PIX mais recente).
-- Usada pelo Fluxo 04 — Carrinho Abandonado.
-- ============================================================

CREATE OR REPLACE VIEW v_pix_abandonados AS
SELECT DISTINCT ON (a.id)
  a.id,
  a.nome,
  a.whatsapp,
  a.email,
  p.nome  AS produto,
  t.valor,
  t.criado_em AS data_pix
FROM transacoes t
JOIN alunos a          ON a.id  = t.aluno_id
JOIN aluno_produtos ap ON ap.aluno_id = a.id
JOIN produtos p        ON p.id  = ap.produto_id
WHERE
  t.metodo_pagamento = 'PIX'
  AND t.status != 'PURCHASE_APPROVED'
  AND t.criado_em < now() - interval '1 hour'
  AND t.criado_em > now() - interval '24 hours'
  AND a.whatsapp IS NOT NULL
  AND a.bloqueado_antipirataria = FALSE
  AND (
    a.ultimo_contato_sdr IS NULL
    OR a.ultimo_contato_sdr < now() - interval '24 hours'
  )
ORDER BY a.id, t.criado_em DESC;
