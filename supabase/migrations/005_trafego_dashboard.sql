-- ============================================================
-- Migration: 005_trafego_dashboard.sql
-- Tabela campanhas_metricas + views de tráfego e dashboard
-- ============================================================


-- ============================================================
-- TABELA: campanhas_metricas
-- Métricas diárias de Meta Ads e Google Ads.
-- Upsert key: (plataforma, campanha_id, data_referencia)
-- ============================================================

CREATE TABLE IF NOT EXISTS campanhas_metricas (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  plataforma      TEXT    NOT NULL CHECK (plataforma IN ('meta', 'google')),
  campanha_id     TEXT    NOT NULL,
  campanha_nome   TEXT,
  data_referencia DATE    NOT NULL,
  spend           DECIMAL(10, 2) DEFAULT 0,
  impressions     INTEGER DEFAULT 0,
  clicks          INTEGER DEFAULT 0,
  leads           INTEGER DEFAULT 0,
  conversoes      INTEGER DEFAULT 0,
  criado_em       TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (plataforma, campanha_id, data_referencia)
);

CREATE INDEX IF NOT EXISTS idx_campanhas_data       ON campanhas_metricas (data_referencia);
CREATE INDEX IF NOT EXISTS idx_campanhas_plataforma ON campanhas_metricas (plataforma);

ALTER TABLE campanhas_metricas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Service role full access" ON campanhas_metricas FOR ALL USING (true);


-- ============================================================
-- VIEW: v_roas_por_campanha
-- Cruza spend das campanhas com faturamento do Pagtrust por dia.
-- NOTA: receita_dia é o total do dia (não atribuída por canal).
-- ============================================================

CREATE OR REPLACE VIEW v_roas_por_campanha AS
SELECT
  cm.plataforma,
  cm.campanha_nome,
  cm.data_referencia,
  cm.spend,
  cm.impressions,
  cm.clicks,
  cm.leads,
  cm.conversoes,
  COALESCE(SUM(t.valor), 0)                           AS receita_dia,
  CASE
    WHEN cm.spend > 0
    THEN ROUND(COALESCE(SUM(t.valor), 0) / cm.spend, 2)
    ELSE 0
  END                                                  AS roas,
  CASE
    WHEN NULLIF(cm.leads, 0) IS NOT NULL
    THEN ROUND(cm.spend / cm.leads, 2)
    ELSE NULL
  END                                                  AS cpl,
  CASE
    WHEN NULLIF(cm.conversoes, 0) IS NOT NULL
    THEN ROUND(cm.spend / cm.conversoes, 2)
    ELSE NULL
  END                                                  AS cpa
FROM campanhas_metricas cm
LEFT JOIN transacoes t
  ON  DATE(t.criado_em) = cm.data_referencia
  AND t.status          = 'PURCHASE_APPROVED'
GROUP BY
  cm.plataforma, cm.campanha_nome, cm.data_referencia,
  cm.spend, cm.impressions, cm.clicks, cm.leads, cm.conversoes;


-- ============================================================
-- VIEW: v_funil_completo
-- Funil: tráfego → compra → acesso → engajamento → conclusão.
-- ============================================================

CREATE OR REPLACE VIEW v_funil_completo AS
SELECT
  DATE(t.criado_em)                                         AS data,
  COUNT(DISTINCT t.aluno_id)                                AS compradores,
  COUNT(DISTINCT t.aluno_id) FILTER (
    WHERE a.status_aluno != 'nunca_acessou'
  )                                                         AS acessaram,
  COUNT(DISTINCT t.aluno_id) FILTER (
    WHERE a.status_aluno IN ('em_andamento', 'quase_concluindo', 'concluido')
  )                                                         AS engajados,
  COUNT(DISTINCT t.aluno_id) FILTER (
    WHERE a.status_aluno = 'concluido'
  )                                                         AS concluidos,
  SUM(t.valor)                                              AS faturamento,
  ROUND(AVG(t.valor), 2)                                    AS ticket_medio
FROM transacoes t
JOIN alunos a ON a.id = t.aluno_id
WHERE t.status = 'PURCHASE_APPROVED'
GROUP BY DATE(t.criado_em)
ORDER BY data DESC;


-- ============================================================
-- VIEW: v_resumo_diario
-- Resumo diário para Looker Studio: vendas, faturamento,
-- investimento em tráfego e ROAS geral.
-- ============================================================

CREATE OR REPLACE VIEW v_resumo_diario AS
SELECT
  DATE(t.criado_em)                                             AS data,
  COUNT(DISTINCT t.id)                                          AS total_vendas,
  COUNT(DISTINCT t.aluno_id)                                    AS compradores_unicos,
  SUM(t.valor)                                                  AS faturamento,
  ROUND(AVG(t.valor), 2)                                        AS ticket_medio,
  COUNT(DISTINCT t.id) FILTER (
    WHERE t.metodo_pagamento = 'PIX'
  )                                                             AS vendas_pix,
  COUNT(DISTINCT t.id) FILTER (
    WHERE t.metodo_pagamento = 'Cartao Credito'
  )                                                             AS vendas_cartao,
  COALESCE((
    SELECT SUM(cm.spend)
    FROM   campanhas_metricas cm
    WHERE  cm.data_referencia = DATE(t.criado_em)
  ), 0)                                                         AS investimento_total,
  CASE
    WHEN COALESCE((
      SELECT SUM(cm.spend)
      FROM   campanhas_metricas cm
      WHERE  cm.data_referencia = DATE(t.criado_em)
    ), 0) > 0
    THEN ROUND(
      SUM(t.valor) / (
        SELECT SUM(cm.spend)
        FROM   campanhas_metricas cm
        WHERE  cm.data_referencia = DATE(t.criado_em)
      ), 2
    )
    ELSE NULL
  END                                                           AS roas_geral
FROM transacoes t
WHERE t.status = 'PURCHASE_APPROVED'
GROUP BY DATE(t.criado_em)
ORDER BY data DESC;
