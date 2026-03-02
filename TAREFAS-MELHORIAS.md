# Tarefas de Melhoria — Automação de Alunos

## Contexto
Sistema de automação para cursos de nail design com dois agentes de IA (SDR e Tutor) comunicando com alunos via WhatsApp. Stack: n8n + Dify + Supabase + Z-API.

Repositório: https://github.com/thehenriqueandrade/automacao-alunos

---

## TAREFA 1 — Cooldown anti-spam nas views (PRIORIDADE MÁXIMA)

Atualizar as views `v_alunos_sdr_prioridade` e `v_alunos_tutor_acompanhamento` para nunca retornar alunos que já foram contatados nos últimos 7 dias.

**Arquivo:** `supabase/migrations/002_cooldown_antispam.sql`

```sql
-- View SDR com cooldown de 7 dias
DROP VIEW IF EXISTS v_alunos_sdr_prioridade;
CREATE VIEW v_alunos_sdr_prioridade AS
SELECT
  a.id,
  a.nome,
  a.email,
  a.whatsapp,
  a.status_aluno,
  a.ultimo_contato_sdr,
  STRING_AGG(p.nome, ', ') AS produto,
  MIN(ap.progresso_pct) AS menor_progresso,
  SUM(t.valor) AS valor_total,
  MIN(t.data_compra) AS data_compra
FROM alunos a
JOIN aluno_produtos ap ON ap.aluno_id = a.id
JOIN produtos p ON p.id = ap.produto_id
LEFT JOIN transacoes t ON t.aluno_id = a.id
WHERE
  a.status_aluno IN ('nunca_acessou', 'inativo')
  AND a.whatsapp IS NOT NULL
  AND a.bloqueado_antipirataria = false
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

-- View Tutor com cooldown de 7 dias e ordenação por prioridade
DROP VIEW IF EXISTS v_alunos_tutor_acompanhamento;
CREATE VIEW v_alunos_tutor_acompanhamento AS
SELECT
  a.id,
  a.nome,
  a.email,
  a.whatsapp,
  a.status_aluno,
  a.ultimo_contato_tutor,
  STRING_AGG(p.nome, ', ') AS produto,
  MIN(ap.progresso_pct) AS progresso_pct,
  MAX(ap.ultimo_acesso) AS ultimo_acesso,
  EXTRACT(DAY FROM now() - MAX(ap.ultimo_acesso)) AS dias_sem_acesso,
  CASE a.status_aluno
    WHEN 'quase_concluindo' THEN 1
    WHEN 'em_andamento'     THEN 2
    WHEN 'iniciante'        THEN 3
  END AS prioridade
FROM alunos a
JOIN aluno_produtos ap ON ap.aluno_id = a.id
JOIN produtos p ON p.id = ap.produto_id
WHERE
  a.status_aluno IN ('iniciante', 'em_andamento', 'quase_concluindo')
  AND a.whatsapp IS NOT NULL
  AND a.bloqueado_antipirataria = false
  AND (
    a.ultimo_contato_tutor IS NULL
    OR a.ultimo_contato_tutor < now() - interval '7 days'
  )
  AND (
    a.ultimo_contato_sdr IS NULL
    OR a.ultimo_contato_sdr < now() - interval '7 days'
  )
GROUP BY a.id, a.nome, a.email, a.whatsapp, a.status_aluno, a.ultimo_contato_tutor
ORDER BY prioridade ASC, progresso_pct DESC;
```

---

## TAREFA 2 — Fluxo 04: Carrinho Abandonado

Criar o arquivo `n8n/workflows/04-carrinho-abandonado.json`.

**Lógica:**
- Gatilho: Cron a cada hora
- Busca no Supabase transações com `metodo_pagamento = 'PIX'` criadas há mais de 1h onde NÃO existe outra transação do mesmo `aluno_id` com `status = 'PURCHASE_APPROVED'`
- Envia para o Dify SDR IA com query de urgência sobre PIX expirado
- Envia mensagem via Z-API
- Registra `ultimo_contato_sdr` no aluno

**Query SQL para o nó Supabase (usar nó HTTP Request com Supabase REST API):**
```sql
SELECT DISTINCT
  a.id,
  a.nome,
  a.whatsapp,
  a.email,
  p.nome AS produto,
  t.valor,
  t.criado_em AS data_pix
FROM transacoes t
JOIN alunos a ON a.id = t.aluno_id
JOIN aluno_produtos ap ON ap.aluno_id = a.id
JOIN produtos p ON p.id = ap.produto_id
WHERE
  t.metodo_pagamento = 'PIX'
  AND t.status != 'PURCHASE_APPROVED'
  AND t.criado_em < now() - interval '1 hour'
  AND t.criado_em > now() - interval '24 hours'
  AND a.whatsapp IS NOT NULL
  AND (
    a.ultimo_contato_sdr IS NULL
    OR a.ultimo_contato_sdr < now() - interval '24 hours'
  )
LIMIT 50;
```

**Estrutura dos nós:**
```
Cron (a cada hora)
  → Supabase HTTP — Buscar PIX Abandonados
  → Tem resultados? (IF: items length > 0)
      ✅ Sim → Loop por Aluno
          → Dify — SDR IA (query: urgência PIX expirado)
          → Dify respondeu?
              ✅ Sim → Z-API — Enviar Aluno → Supabase — Update ultimo_contato_sdr
              ❌ Não → Z-API — Notificar Operador
      ❌ Não → fim
```

**Body do Dify para carrinho abandonado:**
```json
{
  "inputs": {
    "nome_cliente": "{{ $json.nome }}",
    "produto": "{{ $json.produto }}"
  },
  "query": "O aluno tentou comprar mas o PIX expirou. Gere uma mensagem de recuperação urgente oferecendo ajuda para finalizar a compra.",
  "response_mode": "blocking",
  "conversation_id": "",
  "user": "{{ $json.whatsapp }}"
}
```

---

## TAREFA 3 — Tabela de histórico de contatos

**Arquivo:** `supabase/migrations/003_historico_contatos.sql`

```sql
CREATE TABLE IF NOT EXISTS historico_contatos (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  aluno_id BIGINT REFERENCES alunos(id) ON DELETE CASCADE,
  tipo TEXT NOT NULL CHECK (tipo IN ('sdr', 'tutor', 'carrinho_abandonado', 'upsell')),
  mensagem_enviada TEXT,
  respondeu BOOLEAN DEFAULT false,
  criado_em TIMESTAMPTZ DEFAULT now()
);

-- Index para consultas por aluno e tipo
CREATE INDEX idx_historico_aluno_id ON historico_contatos(aluno_id);
CREATE INDEX idx_historico_tipo ON historico_contatos(tipo);
CREATE INDEX idx_historico_criado_em ON historico_contatos(criado_em);

-- RLS
ALTER TABLE historico_contatos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Service role full access" ON historico_contatos
  FOR ALL USING (true);
```

Atualizar os workflows 02 e 03 para inserir registro em `historico_contatos` após cada envio bem-sucedido.

---

## TAREFA 4 — View de métricas para dashboard

**Arquivo:** `supabase/migrations/004_view_metricas.sql`

```sql
CREATE OR REPLACE VIEW v_metricas_dashboard AS
SELECT
  -- Distribuição de status
  COUNT(*) FILTER (WHERE status_aluno = 'nunca_acessou') AS total_nunca_acessou,
  COUNT(*) FILTER (WHERE status_aluno = 'inativo') AS total_inativo,
  COUNT(*) FILTER (WHERE status_aluno = 'iniciante') AS total_iniciante,
  COUNT(*) FILTER (WHERE status_aluno = 'em_andamento') AS total_em_andamento,
  COUNT(*) FILTER (WHERE status_aluno = 'quase_concluindo') AS total_quase_concluindo,
  COUNT(*) FILTER (WHERE status_aluno = 'concluido') AS total_concluido,

  -- Contatos da semana
  COUNT(*) FILTER (
    WHERE ultimo_contato_sdr > now() - interval '7 days'
  ) AS contatados_sdr_semana,
  COUNT(*) FILTER (
    WHERE ultimo_contato_tutor > now() - interval '7 days'
  ) AS contatados_tutor_semana,

  -- Totais gerais
  COUNT(*) AS total_alunos,
  COUNT(*) FILTER (WHERE whatsapp IS NOT NULL) AS alunos_com_whatsapp
FROM alunos;

-- View de conversão por produto
CREATE OR REPLACE VIEW v_conversao_por_produto AS
SELECT
  p.nome AS produto,
  COUNT(DISTINCT ap.aluno_id) AS total_alunos,
  COUNT(DISTINCT ap.aluno_id) FILTER (
    WHERE a.status_aluno = 'concluido'
  ) AS concluidos,
  ROUND(
    COUNT(DISTINCT ap.aluno_id) FILTER (WHERE a.status_aluno = 'concluido')::numeric /
    NULLIF(COUNT(DISTINCT ap.aluno_id), 0) * 100, 1
  ) AS taxa_conclusao_pct,
  ROUND(AVG(ap.progresso_pct), 1) AS progresso_medio
FROM produtos p
JOIN aluno_produtos ap ON ap.produto_id = p.id
JOIN alunos a ON a.id = ap.aluno_id
GROUP BY p.nome
ORDER BY total_alunos DESC;
```

---

## TAREFA 5 — Fluxo 05: Upsell pós-conclusão

Criar o arquivo `n8n/workflows/05-upsell-concluidos.json`.

**Lógica:**
- Gatilho: Webhook manual (`/webhook/upsell-trigger`) — ativado manualmente pelo operador antes de um lançamento
- Busca alunos da view `v_alunos_upsell` que concluíram pelo menos 1 curso
- Envia mensagem personalizada via Dify SDR IA com foco em oferta exclusiva
- Limit: 30 alunos por disparo

**Estrutura dos nós:**
```
Webhook — Upsell Trigger
  → Supabase — Buscar v_alunos_upsell (limit 30)
  → Loop por Aluno
      → Dify — SDR IA (query: oferta exclusiva para quem concluiu)
      → Dify respondeu?
          ✅ Sim → Z-API — Enviar Aluno → Supabase — Update ultimo_contato_sdr
          ❌ Não → Z-API — Notificar Operador
```

**Body do Dify para upsell:**
```json
{
  "inputs": {
    "nome_cliente": "{{ $json.nome }}",
    "produto": "{{ $json.produto }}"
  },
  "query": "A aluna concluiu o curso. Gere uma mensagem de parabéns e apresente uma oferta exclusiva para o próximo nível de evolução profissional.",
  "response_mode": "blocking",
  "conversation_id": "",
  "user": "{{ $json.whatsapp }}"
}
```

---

## TAREFA 6 — Atualizar CLAUDE.md e README.md

Atualizar os dois arquivos para refletir:
- 5 workflows ativos (01 ao 05)
- 3 novas migrations (002, 003, 004)
- Tabela `historico_contatos`
- 4 novas views (`v_metricas_dashboard`, `v_conversao_por_produto` + views atualizadas)
- Instrução de cooldown anti-spam
- Variáveis de ambiente adicionais se necessário

---

## Ordem de execução sugerida

1. `002_cooldown_antispam.sql` → rodar no Supabase
2. `003_historico_contatos.sql` → rodar no Supabase
3. `004_view_metricas.sql` → rodar no Supabase
4. Criar `04-carrinho-abandonado.json` no n8n
5. Criar `05-upsell-concluidos.json` no n8n
6. Atualizar workflows 02 e 03 para registrar em `historico_contatos`
7. Atualizar `CLAUDE.md` e `README.md`
