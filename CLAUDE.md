# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Projeto

**automacao-alunos** — sistema de automação de comunicação com alunos usando IA, composto por agentes SDR e Tutor orquestrados via n8n, com Dify como backend de IA e Supabase como banco de dados de estado. Integrado com Hotmart (checkout e progresso via API).

**Dados reais (base de produção):**
- 876 alunos cadastrados (871 com WhatsApp)
- 11 produtos
- 871 transações
- Total faturado: R$ 23.548,30

## Infraestrutura

- **VPS Hostinger / Easypanel** — hospeda os containers de Dify e n8n.
- **Dify** — backend de IA; dois Apps independentes (`sdr-ia`, `tutor-ia`).
- **n8n** — orquestrador de fluxos e receptor de webhooks.
- **Supabase** — banco `jornada_alunos`.
- **Z-API** — canal único de saída via WhatsApp.
- **Hotmart** — fonte dos eventos de compra (webhook `PURCHASE_COMPLETE`) e API de progresso de alunos.

## Arquitetura em camadas

```
Pagtrust ──► n8n Fluxo 01 (Webhook Receiver)
                     │
                 Supabase
           ┌─────────┼──────────┐─────────────┐
  Fluxo 02 (SDR) Fluxo 03 (Tutor) Fluxo 04 (PIX) Fluxo 05 (Upsell)
        │              │               │                │
  Dify App SDR    Dify App Tutor  Dify App SDR    Dify App SDR
        └──────────────┴───────────────┴────────────────┘
                                 ▼
                              Z-API → WhatsApp
```

## Estrutura do repositório

```
dify/apps/sdr-ia/           # Prompt e knowledge base do agente SDR
dify/apps/tutor-ia/         # Prompt e knowledge base do agente Tutor
n8n/workflows/              # Exports JSON dos 7 fluxos
supabase/migrations/        # 6 migrations SQL em ordem de execução
supabase/seeds/             # Dados de referência (11 produtos) e teste
docs/fluxos/                # Documentação detalhada de cada fluxo n8n
scripts/                    # Utilitários de setup e teste
```

## Fluxos n8n

| Arquivo | Gatilho | Função |
|---------|---------|--------|
| `01-entrada-webhook-receiver.json` | POST da Hotmart (`PURCHASE_COMPLETE`) | Filtra evento, upsert aluno (por email) e produto (por nome), persiste transação com `metodo_pagamento`, cria aluno_produtos |
| `02-vendas-sdr.json` | Webhook `/sdr-trigger` | Consulta `v_alunos_sdr_prioridade`, chama Dify SDR, envia via Z-API, registra em `historico_contatos` |
| `03-acompanhamento-tutor.json` | Cron — toda segunda 09h | Consulta `v_alunos_tutor_acompanhamento`, chama Dify Tutor, envia via Z-API, registra em `historico_contatos` |
| `04-carrinho-abandonado.json` | Cron — a cada hora | Consulta `v_pix_abandonados`, chama Dify SDR com urgência PIX, envia via Z-API |
| `05-upsell-concluidos.json` | Webhook manual `/upsell-trigger` | Consulta `v_alunos_upsell` (máx 30), chama Dify SDR com oferta exclusiva, envia via Z-API |
| `06-metricas-trafego.json` | Cron — todo dia 08h | Coleta métricas do dia anterior no Meta Ads e Google Ads, faz upsert em `campanhas_metricas`, notifica operador |
| `07-sync-progresso-hotmart.json` | Cron — todo dia 06h | Para cada produto com `hotmart_product_id`, busca progresso via API Hotmart, atualiza `aluno_produtos` e `status_aluno` |

## Banco de dados

### Tabelas

- **`produtos`** — 11 produtos reais; chave única: `nome`.
- **`alunos`** — chave única: `email` (obrigatório no checkout Pagtrust); campos: nome, whatsapp, cidade, estado, status_aluno (enum), ultimo_contato_sdr, ultimo_contato_tutor, bloqueado_antipirataria.
- **`transacoes`** — chave única: `order_id`; `dados_raw` (JSONB) guarda payload bruto; `metodo_pagamento` (enum).
- **`aluno_produtos`** — N:N entre alunos e produtos; `progresso_pct` (0–100), `ultimo_acesso`; UNIQUE(aluno_id, produto_id). Substitui `progresso_aulas`.
- **`historico_contatos`** — log de mensagens enviadas; campos: aluno_id, tipo (sdr | tutor | carrinho_abandonado | upsell), mensagem_enviada, respondeu.
- **`campanhas_metricas`** — métricas diárias de tráfego pago; chave única: (plataforma, campanha_id, data_referencia); campos: spend, impressions, clicks, leads, conversoes.

> **Campo adicional em `produtos`:** `hotmart_product_id TEXT` (migration 006). Obrigatório para o Fluxo 07 sincronizar progresso.

### Enums

- **`status_aluno`**: `nunca_acessou` | `inativo` | `iniciante` | `em_andamento` | `quase_concluindo` | `concluido`
- **`metodo_pagamento`**: `PIX` | `Cartao Credito` | `Boleto` | `Outro`

### Views

| View | Consumida por | Lógica |
|------|--------------|--------|
| `v_alunos_sdr_prioridade` | Fluxo 02 | `nunca_acessou` ou `inativo`, com whatsapp, cooldown 7 dias, 1 linha/aluno |
| `v_alunos_tutor_acompanhamento` | Fluxo 03 | em progresso, com whatsapp, cooldown 7 dias, ordenada por prioridade, 1 linha/aluno |
| `v_alunos_upsell` | Fluxo 05 | Alunos com ao menos 1 produto 100%, cursos agregados |
| `v_pix_abandonados` | Fluxo 04 | PIX não aprovados entre 1h–24h, aluno não contatado nas últimas 24h |
| `v_metricas_dashboard` | Dashboard | Snapshot de totais por status e contatos da semana |
| `v_conversao_por_produto` | Dashboard | Taxa de conclusão e progresso médio por produto |
| `v_roas_por_campanha` | Looker Studio | Spend, CPL, CPA e ROAS por campanha e dia |
| `v_funil_completo` | Looker Studio | Funil compra → acesso → engajamento → conclusão por dia |
| `v_resumo_diario` | Looker Studio | Vendas, faturamento, investimento e ROAS geral por dia |

### Cooldown anti-spam

As views SDR e Tutor aplicam **cross-cooldown de 7 dias**: um aluno é excluído se foi contatado por qualquer agente (SDR ou Tutor) nos últimos 7 dias. A view PIX usa cooldown de 24h exclusivo para o campo `ultimo_contato_sdr`.

### Payload da Hotmart (`PURCHASE_COMPLETE`)

| Campo no payload | Campo interno |
|------------------|---------------|
| `body.data.buyer.name` | `nome` |
| `body.data.buyer.checkout_phone` (só dígitos) | `whatsapp` |
| `body.data.buyer.email` | `email` |
| `body.data.buyer.address.city` | `cidade` |
| `body.data.buyer.address.state` | `estado` |
| `body.data.purchase.transaction` | `order_id` |
| `body.data.purchase.price.value` | `valor` |
| `body.data.purchase.payment.type` | `metodo_pagamento` |
| `body.data.purchase.status` | `status` |
| `body.event` | `event` |
| `body.data.product.name` | `produto` |
| `body` (objeto inteiro) | `dados_raw` |

> **Atenção:** O fluxo filtra apenas `event = PURCHASE_COMPLETE`. Outros eventos são ignorados silenciosamente.

## Migrations (ordem de execução)

```
001_schema.sql              # Schema completo: enums, 4 tabelas, 3 views base
002_cooldown_antispam.sql   # Reescreve views SDR/Tutor com cooldown; add v_pix_abandonados
003_historico_contatos.sql  # Tabela historico_contatos com RLS
004_view_metricas.sql       # Views de dashboard: v_metricas_dashboard, v_conversao_por_produto
005_trafego_dashboard.sql   # Tabela campanhas_metricas + views de tráfego para Looker Studio
006_hotmart_product_id.sql  # ALTER TABLE produtos ADD COLUMN hotmart_product_id TEXT
```

## Comandos úteis

```bash
# Aplicar migrations no Supabase (requer CLI linkado ao projeto)
./scripts/apply-migrations.sh

# Simular evento PURCHASE_APPROVED para testar o Fluxo 01
./scripts/test-webhook.sh http://localhost:5678/webhook/pagtrust
```

## Configuração de ambiente

Copie `.env.example` para `.env` e preencha:

**Core (todos os fluxos):**
- `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY`
- `DIFY_BASE_URL` + `DIFY_API_KEY_SDR` + `DIFY_API_KEY_TUTOR`
- `ZAPI_INSTANCE_ID` + `ZAPI_TOKEN` + `ZAPI_CLIENT_TOKEN`
- `OPERADOR_WHATSAPP` — WhatsApp pessoal que recebe alertas de erro dos fluxos
- `TUTOR_DIAS_SEM_ACESSO` — mínimo de dias de ausência para o Tutor disparar (padrão: 7)

**Fluxo 07 — Sync Hotmart:**

| Variável | Como obter |
|----------|-----------|
| `HOTMART_BASIC_TOKEN` | Base64 de `client_id:client_secret` — Hotmart → Ferramentas → Credenciais API |

**Fluxo 06 — Tráfego (Meta Ads + Google Ads):**

| Variável | Como obter |
|----------|-----------|
| `META_ACCESS_TOKEN` | Meta for Developers → Explorador API Graph |
| `META_AD_ACCOUNT_ID` | Business Manager → URL do Ads Manager (`act_XXXXXXXXX`) |
| `GOOGLE_ADS_ACCESS_TOKEN` | OAuth2 já configurado — access_token da conta |
| `GOOGLE_ADS_DEVELOPER_TOKEN` | Google Ads API Center → conta MCC |
| `GOOGLE_ADS_CUSTOMER_ID` | ID da conta Google Ads (sem hífens) |
| `GOOGLE_ADS_MCC_ID` | ID da conta MCC (se usar conta de administrador) |

## Monitoramento de erros (padrão obrigatório)

Em todo nó HTTP Request dos fluxos n8n (chamadas ao Dify e à Z-API):
1. Ativar **"Continue On Fail"**.
2. Branch de erro envia mensagem ao `OPERADOR_WHATSAPP`:
   `"⚠️ Erro no fluxo [NOME]: [nó] retornou [código/mensagem]"`.
