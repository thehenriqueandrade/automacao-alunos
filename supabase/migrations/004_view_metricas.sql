-- ============================================================
-- Migration: 004_view_metricas.sql
-- Views para dashboard de métricas e análise de conversão.
-- ============================================================


-- ============================================================
-- VIEW: v_metricas_dashboard
-- Snapshot de distribuição de status e atividade de contatos.
-- Retorna uma única linha com todos os totais.
-- ============================================================

CREATE OR REPLACE VIEW v_metricas_dashboard AS
SELECT
  COUNT(*) FILTER (WHERE status_aluno = 'nunca_acessou')    AS total_nunca_acessou,
  COUNT(*) FILTER (WHERE status_aluno = 'inativo')          AS total_inativo,
  COUNT(*) FILTER (WHERE status_aluno = 'iniciante')        AS total_iniciante,
  COUNT(*) FILTER (WHERE status_aluno = 'em_andamento')     AS total_em_andamento,
  COUNT(*) FILTER (WHERE status_aluno = 'quase_concluindo') AS total_quase_concluindo,
  COUNT(*) FILTER (WHERE status_aluno = 'concluido')        AS total_concluido,
  COUNT(*) FILTER (
    WHERE ultimo_contato_sdr > now() - interval '7 days'
  )                                                         AS contatados_sdr_semana,
  COUNT(*) FILTER (
    WHERE ultimo_contato_tutor > now() - interval '7 days'
  )                                                         AS contatados_tutor_semana,
  COUNT(*)                                                  AS total_alunos,
  COUNT(*) FILTER (WHERE whatsapp IS NOT NULL)              AS alunos_com_whatsapp
FROM alunos;


-- ============================================================
-- VIEW: v_conversao_por_produto
-- Taxa de conclusão e progresso médio por produto.
-- Ordenada por volume de alunos (maior primeiro).
-- ============================================================

CREATE OR REPLACE VIEW v_conversao_por_produto AS
SELECT
  p.nome                                                    AS produto,
  COUNT(DISTINCT ap.aluno_id)                               AS total_alunos,
  COUNT(DISTINCT ap.aluno_id) FILTER (
    WHERE a.status_aluno = 'concluido'
  )                                                         AS concluidos,
  ROUND(
    COUNT(DISTINCT ap.aluno_id) FILTER (
      WHERE a.status_aluno = 'concluido'
    )::NUMERIC / NULLIF(COUNT(DISTINCT ap.aluno_id), 0) * 100,
    1
  )                                                         AS taxa_conclusao_pct,
  ROUND(AVG(ap.progresso_pct), 1)                           AS progresso_medio
FROM produtos p
JOIN aluno_produtos ap ON ap.produto_id = p.id
JOIN alunos a          ON a.id          = ap.aluno_id
GROUP BY p.nome
ORDER BY total_alunos DESC;
