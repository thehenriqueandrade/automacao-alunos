# Tarefas — Tráfego + Dashboard

## Contexto
Extensão do sistema de automação de alunos. Adicionar coleta diária de métricas de Meta Ads e Google Ads, salvar no Supabase e disponibilizar para o Google Looker Studio via views otimizadas.

Plataformas: Meta Ads + Google Ads
Dashboard: Google Looker Studio (conecta direto no Supabase via PostgreSQL)
Repositório: https://github.com/thehenriqueandrade/automacao-alunos

---

## TAREFA 1 — Migration: tabela campanhas_metricas e views

**Arquivo:** `supabase/migrations/005_trafego_dashboard.sql`

```sql
-- Tabela principal de métricas de tráfego
CREATE TABLE IF NOT EXISTS campanhas_metricas (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  plataforma TEXT NOT NULL CHECK (plataforma IN ('meta', 'google')),
  campanha_id TEXT NOT NULL,
  campanha_nome TEXT,
  data_referencia DATE NOT NULL,
  spend DECIMAL(10,2) DEFAULT 0,
  impressions INTEGER DEFAULT 0,
  clicks INTEGER DEFAULT 0,
  leads INTEGER DEFAULT 0,
  conversoes INTEGER DEFAULT 0,
  criado_em TIMESTAMPTZ DEFAULT now(),
  UNIQUE(plataforma, campanha_id, data_referencia)
);

CREATE INDEX idx_campanhas_data ON campanhas_metricas(data_referencia);
CREATE INDEX idx_campanhas_plataforma ON campanhas_metricas(plataforma);

ALTER TABLE campanhas_metricas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Service role full access" ON campanhas_metricas FOR ALL USING (true);

-- View ROAS por campanha (cruza spend com faturamento do Pagtrust)
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
  COALESCE(SUM(t.valor), 0) AS receita_dia,
  CASE
    WHEN cm.spend > 0 THEN ROUND(COALESCE(SUM(t.valor), 0) / cm.spend, 2)
    ELSE 0
  END AS roas,
  CASE
    WHEN NULLIF(cm.leads, 0) IS NOT NULL THEN ROUND(cm.spend / cm.leads, 2)
    ELSE NULL
  END AS cpl,
  CASE
    WHEN NULLIF(cm.conversoes, 0) IS NOT NULL THEN ROUND(cm.spend / cm.conversoes, 2)
    ELSE NULL
  END AS cpa
FROM campanhas_metricas cm
LEFT JOIN transacoes t ON DATE(t.data_compra) = cm.data_referencia
  AND t.status = 'PURCHASE_APPROVED'
GROUP BY
  cm.plataforma, cm.campanha_nome, cm.data_referencia,
  cm.spend, cm.impressions, cm.clicks, cm.leads, cm.conversoes;

-- View funil completo: tráfego → compra → acesso → conclusão
CREATE OR REPLACE VIEW v_funil_completo AS
SELECT
  DATE(t.data_compra) AS data,
  COUNT(DISTINCT t.aluno_id) AS compradores,
  COUNT(DISTINCT t.aluno_id) FILTER (
    WHERE a.status_aluno != 'nunca_acessou'
  ) AS acessaram,
  COUNT(DISTINCT t.aluno_id) FILTER (
    WHERE a.status_aluno IN ('em_andamento', 'quase_concluindo', 'concluido')
  ) AS engajados,
  COUNT(DISTINCT t.aluno_id) FILTER (
    WHERE a.status_aluno = 'concluido'
  ) AS concluidos,
  SUM(t.valor) AS faturamento,
  ROUND(AVG(t.valor), 2) AS ticket_medio
FROM transacoes t
JOIN alunos a ON a.id = t.aluno_id
WHERE t.status = 'PURCHASE_APPROVED'
GROUP BY DATE(t.data_compra)
ORDER BY data DESC;

-- View resumo diário para Looker Studio
CREATE OR REPLACE VIEW v_resumo_diario AS
SELECT
  DATE(t.data_compra) AS data,
  COUNT(DISTINCT t.id) AS total_vendas,
  COUNT(DISTINCT t.aluno_id) AS compradores_unicos,
  SUM(t.valor) AS faturamento,
  ROUND(AVG(t.valor), 2) AS ticket_medio,
  COUNT(DISTINCT t.id) FILTER (WHERE t.metodo_pagamento = 'PIX') AS vendas_pix,
  COUNT(DISTINCT t.id) FILTER (WHERE t.metodo_pagamento = 'Cartao Credito') AS vendas_cartao,
  COALESCE((
    SELECT SUM(cm.spend)
    FROM campanhas_metricas cm
    WHERE cm.data_referencia = DATE(t.data_compra)
  ), 0) AS investimento_total,
  CASE
    WHEN COALESCE((
      SELECT SUM(cm.spend)
      FROM campanhas_metricas cm
      WHERE cm.data_referencia = DATE(t.data_compra)
    ), 0) > 0
    THEN ROUND(
      SUM(t.valor) / (
        SELECT SUM(cm.spend)
        FROM campanhas_metricas cm
        WHERE cm.data_referencia = DATE(t.data_compra)
      ), 2
    )
    ELSE NULL
  END AS roas_geral
FROM transacoes t
WHERE t.status = 'PURCHASE_APPROVED'
GROUP BY DATE(t.data_compra)
ORDER BY data DESC;
```

---

## TAREFA 2 — Workflow n8n: Coleta de Métricas (Meta + Google)

**Arquivo:** `n8n/workflows/06-metricas-trafego.json`

### Estrutura do fluxo:

```
Cron — Diário 08h
  → Meta Ads — HTTP Request (busca métricas do dia anterior)
  → Normalizar Meta (extrair campanhas do response)
  → Loop Campanhas Meta
      → Supabase — Upsert campanhas_metricas (plataforma: 'meta')
  → Google Ads — HTTP Request (busca métricas do dia anterior)
  → Normalizar Google (extrair campanhas do response)
  → Loop Campanhas Google
      → Supabase — Upsert campanhas_metricas (plataforma: 'google')
  → Z-API — Notificar Operador (resumo diário)
```

### Nó Meta Ads — HTTP Request:

```
Método: GET
URL: https://graph.facebook.com/v19.0/{{ $env.META_AD_ACCOUNT_ID }}/campaigns

Query Parameters:
  fields: name,insights{spend,impressions,clicks,actions}
  date_preset: yesterday
  access_token: {{ $env.META_ACCESS_TOKEN }}
  limit: 100
```

### Extrair leads do campo actions do Meta:
```javascript
// No nó Code para normalizar Meta
const campaigns = $input.first().json.data || [];
return campaigns.map(campaign => {
  const insights = campaign.insights?.data?.[0] || {};
  const actions = insights.actions || [];
  const leads = actions.find(a => a.action_type === 'lead')?.value || 0;
  const purchases = actions.find(a => a.action_type === 'purchase')?.value || 0;
  
  return {
    plataforma: 'meta',
    campanha_id: campaign.id,
    campanha_nome: campaign.name,
    data_referencia: new Date(Date.now() - 86400000).toISOString().split('T')[0],
    spend: parseFloat(insights.spend || 0),
    impressions: parseInt(insights.impressions || 0),
    clicks: parseInt(insights.clicks || 0),
    leads: parseInt(leads),
    conversoes: parseInt(purchases)
  };
});
```

### Nó Google Ads — HTTP Request:

```
Método: POST
URL: https://googleads.googleapis.com/v16/customers/{{ $env.GOOGLE_ADS_CUSTOMER_ID }}/googleAds:search

Headers:
  Authorization: Bearer {{ $env.GOOGLE_ADS_ACCESS_TOKEN }}
  developer-token: {{ $env.GOOGLE_ADS_DEVELOPER_TOKEN }}
  login-customer-id: {{ $env.GOOGLE_ADS_MCC_ID }}

Body:
{
  "query": "SELECT campaign.id, campaign.name, metrics.cost_micros, metrics.impressions, metrics.clicks, metrics.conversions FROM campaign WHERE segments.date DURING YESTERDAY"
}
```

### Normalizar Google Ads:
```javascript
// No nó Code para normalizar Google
const rows = $input.first().json.results || [];
return rows.map(row => ({
  plataforma: 'google',
  campanha_id: row.campaign.id,
  campanha_nome: row.campaign.name,
  data_referencia: new Date(Date.now() - 86400000).toISOString().split('T')[0],
  spend: parseFloat((row.metrics.costMicros || 0) / 1000000),
  impressions: parseInt(row.metrics.impressions || 0),
  clicks: parseInt(row.metrics.clicks || 0),
  leads: 0,
  conversoes: parseInt(row.metrics.conversions || 0)
}));
```

### Nó Supabase — Upsert campanhas_metricas:
```
Operation: Upsert
Table: campanhas_metricas
On Conflict: plataforma,campanha_id,data_referencia
Fields: plataforma, campanha_id, campanha_nome, data_referencia, spend, impressions, clicks, leads, conversoes
```

### Mensagem de resumo diário para o operador:
```
📊 *Resumo Tráfego — {{ new Date(Date.now() - 86400000).toLocaleDateString('pt-BR') }}*

Meta Ads:
• Investimento: R$ {{ $('Loop Meta').item.json.spend_total }}
• Leads: {{ $('Loop Meta').item.json.leads_total }}
• CPL: R$ {{ $('Loop Meta').item.json.cpl }}

Google Ads:
• Investimento: R$ {{ $('Loop Google').item.json.spend_total }}
• Conversões: {{ $('Loop Google').item.json.conversoes_total }}
• CPA: R$ {{ $('Loop Google').item.json.cpa }}
```

---

## TAREFA 3 — Variáveis de ambiente adicionais no n8n

Adicionar em **Settings → Environment Variables**:

| Variável | Como obter |
|----------|-----------|
| `META_ACCESS_TOKEN` | Meta for Developers → Explorador API Graph |
| `META_AD_ACCOUNT_ID` | Business Manager → URL do Ads Manager (`act_XXXXXXXXX`) |
| `GOOGLE_ADS_ACCESS_TOKEN` | OAuth2 já configurado — pegar o access_token |
| `GOOGLE_ADS_DEVELOPER_TOKEN` | Google Ads API Center → conta MCC |
| `GOOGLE_ADS_CUSTOMER_ID` | ID da conta Google Ads (sem hífens) |
| `GOOGLE_ADS_MCC_ID` | ID da conta MCC (se usar conta de administrador) |

---

## TAREFA 4 — Configuração do Google Looker Studio

### Conectar Supabase ao Looker Studio:

O Looker Studio não tem conector nativo para Supabase, mas conecta via PostgreSQL direto.

**Passos:**
1. Acesse: https://lookerstudio.google.com
2. Clique em **"Criar"** → **"Fonte de dados"**
3. Busque o conector: **"PostgreSQL"**
4. Preencha com as credenciais do Supabase:
   - Host: `db.XXXX.supabase.co` (encontra em Supabase → Settings → Database)
   - Porta: `5432`
   - Database: `postgres`
   - Username: `postgres`
   - Password: sua senha do Supabase
5. Selecione as views como tabelas:
   - `v_resumo_diario`
   - `v_roas_por_campanha`
   - `v_funil_completo`
   - `v_metricas_dashboard`
   - `v_conversao_por_produto`

> ⚠️ Para conectar externamente, verifique se o IP do Looker Studio está liberado em Supabase → Settings → Database → Connection Pooling. Se necessário, habilite "Direct connection" e use a senha de service role.

---

### Estrutura do Dashboard — 3 páginas:

**Página 1 — Tráfego**
Fonte: `v_roas_por_campanha`
Widgets:
- Scorecard: Investimento Total (SUM spend)
- Scorecard: CPL Médio (AVG cpl)
- Scorecard: ROAS Geral (AVG roas)
- Gráfico de barras: Spend por plataforma
- Tabela: Campanhas com spend, leads, CPL, ROAS ordenadas por ROAS desc
- Gráfico de linha: Evolução diária do spend vs receita

**Página 2 — Vendas**
Fonte: `v_resumo_diario`
Widgets:
- Scorecard: Faturamento total
- Scorecard: Ticket médio
- Scorecard: Total de vendas
- Gráfico de linha: Faturamento diário
- Gráfico de pizza: PIX vs Cartão
- Tabela: Top produtos por faturamento (fonte: `v_conversao_por_produto`)

**Página 3 — Funil**
Fonte: `v_funil_completo`
Widgets:
- Funil visual: Compradores → Acessaram → Engajados → Concluídos
- Scorecard: Taxa de acesso (acessaram/compradores %)
- Scorecard: Taxa de conclusão (concluidos/compradores %)
- Tabela: Distribuição de alunos por status (fonte: `v_metricas_dashboard`)
- Gráfico de barras: Conclusão por produto (fonte: `v_conversao_por_produto`)

---

## TAREFA 5 — Atualizar CLAUDE.md e README.md

Adicionar:
- Fluxo 06 — Coleta de Métricas de Tráfego
- Tabela `campanhas_metricas`
- 4 novas views de dashboard
- Instruções de conexão com Looker Studio
- Novas variáveis de ambiente (Meta e Google Ads)
- Seção "Dashboard" na documentação com print do Looker Studio (placeholder)
