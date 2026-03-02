# automacao-alunos

Sistema de automação de comunicação com alunos via WhatsApp, usando IA generativa para recuperação de vendas e retenção de alunos ativos. Integrado com Hotmart para receber compras e sincronizar progresso. Inclui coleta de métricas de tráfego pago e dashboard no Looker Studio.

**Stack:** n8n · Dify · Supabase · Z-API · Hotmart · Meta Ads API · Google Ads API · Looker Studio

---

## Como funciona

```
Pagtrust ──► n8n (Webhook Receiver)
                 │
             Supabase
        ┌────────┼────────┬──────────┐
   SDR IA    Tutor IA   PIX      Upsell
        └────────┴────────┴──────────┘
                     │
                  Z-API → WhatsApp
```

Seis fluxos n8n trabalham de forma autônoma:

| Fluxo | Gatilho | O que faz |
|-------|---------|-----------|
| **01 — Webhook Receiver** | POST da Hotmart (`PURCHASE_COMPLETE`) | Registra compra, aluno (com cidade/estado) e produto no Supabase |
| **02 — SDR IA** | Webhook externo | Aborda leads que nunca acessaram ou ficaram inativos |
| **03 — Tutor IA** | Cron — toda segunda 09h | Reengaja alunos em progresso que pararam de acessar |
| **04 — Carrinho Abandonado** | Cron — a cada hora | Recupera PIX expirados entre 1h e 24h |
| **05 — Upsell** | Webhook manual | Oferece o próximo curso para quem já concluiu |
| **06 — Métricas de Tráfego** | Cron — todo dia 08h | Coleta campanhas do Meta Ads e Google Ads; upsert em `campanhas_metricas` |
| **07 — Sync Progresso Hotmart** | Cron — todo dia 06h | Sincroniza progresso de alunos via API Hotmart; atualiza `aluno_produtos` e `status_aluno` |

---

## Banco de dados (Supabase)

### Tabelas

| Tabela | Descrição |
|--------|-----------|
| `produtos` | 11 produtos do catálogo; chave: `nome` |
| `alunos` | Cadastro único por `email`; rastreia status e datas de contato |
| `transacoes` | Compras da Pagtrust; payload bruto em `dados_raw` |
| `aluno_produtos` | N:N aluno ↔ produto; rastreia `progresso_pct` e `ultimo_acesso` |
| `historico_contatos` | Log de mensagens enviadas por fluxo (sdr, tutor, carrinho_abandonado, upsell) |
| `campanhas_metricas` | Métricas diárias de Meta Ads e Google Ads; chave: (plataforma, campanha_id, data_referencia) |

### Views principais

| View | Uso |
|------|-----|
| `v_alunos_sdr_prioridade` | Leads para o Fluxo 02 — cooldown 7 dias |
| `v_alunos_tutor_acompanhamento` | Alunos para o Fluxo 03 — cooldown 7 dias, ordenados por prioridade |
| `v_pix_abandonados` | PIX expirados para o Fluxo 04 — cooldown 24h |
| `v_alunos_upsell` | Alunos com curso(s) concluídos para o Fluxo 05 |
| `v_metricas_dashboard` | Totais por status e atividade semanal |
| `v_conversao_por_produto` | Taxa de conclusão e progresso médio por produto |
| `v_roas_por_campanha` | Spend, CPL, CPA e ROAS por campanha e dia — Looker Studio |
| `v_funil_completo` | Funil compra → acesso → engajamento → conclusão por dia — Looker Studio |
| `v_resumo_diario` | Vendas, faturamento, investimento e ROAS geral por dia — Looker Studio |

### Status do aluno

```
nunca_acessou → inativo → iniciante → em_andamento → quase_concluindo → concluido
```

---

## Setup

### 1. Pré-requisitos

- n8n rodando (self-hosted ou cloud)
- Dify com dois Apps criados: `sdr-ia` e `tutor-ia`
- Projeto Supabase criado
- Instância Z-API ativa
- Conta Pagtrust com webhook configurado

### 2. Banco de dados

Execute as migrations em ordem no Supabase SQL Editor:

```
supabase/migrations/001_schema.sql
supabase/migrations/002_cooldown_antispam.sql
supabase/migrations/003_historico_contatos.sql
supabase/migrations/004_view_metricas.sql
supabase/migrations/005_trafego_dashboard.sql
supabase/migrations/006_hotmart_product_id.sql
```

Após a migration 006, preencha o `hotmart_product_id` dos 11 produtos no Supabase (IDs obtidos no painel Hotmart).

Depois execute o seed com os produtos reais:

```
supabase/seeds/seed.sql
```

### 3. Variáveis de ambiente no n8n

Em **Settings → Variables**, configure:

| Variável | Descrição |
|----------|-----------|
| `DIFY_BASE_URL` | URL base da API Dify (ex: `https://dify.seudominio.com/v1`) |
| `DIFY_API_KEY_SDR` | API Key do App SDR |
| `DIFY_API_KEY_TUTOR` | API Key do App Tutor |
| `ZAPI_INSTANCE_ID` | ID da instância Z-API |
| `ZAPI_TOKEN` | Token da instância Z-API |
| `ZAPI_CLIENT_TOKEN` | Client-Token da conta Z-API |
| `OPERADOR_WHATSAPP` | Seu WhatsApp com DDI (ex: `5511999990000`) |
| `TUTOR_DIAS_SEM_ACESSO` | Dias mínimos de ausência para o Tutor disparar (padrão: `7`) |
| `HOTMART_BASIC_TOKEN` | Base64 de `client_id:client_secret` (Hotmart → Ferramentas → Credenciais API) |
| `SUPABASE_URL` | URL do projeto Supabase (ex: `https://xxx.supabase.co`) |
| `SUPABASE_SERVICE_ROLE_KEY` | Service Role Key do Supabase (para upsert via REST no Fluxo 06) |
| `META_ACCESS_TOKEN` | Meta for Developers → Explorador API Graph |
| `META_AD_ACCOUNT_ID` | Business Manager → URL do Ads Manager (`act_XXXXXXXXX`) |
| `GOOGLE_ADS_ACCESS_TOKEN` | OAuth2 access token da conta Google Ads |
| `GOOGLE_ADS_DEVELOPER_TOKEN` | Google Ads API Center → conta MCC |
| `GOOGLE_ADS_CUSTOMER_ID` | ID da conta Google Ads (sem hífens) |
| `GOOGLE_ADS_MCC_ID` | ID da conta MCC (se gerenciar múltiplas contas) |

### 4. Credencial Supabase no n8n

Em **Settings → Credentials → Add → Supabase**:
- Nome: `Supabase — jornada_alunos`
- URL: URL do seu projeto Supabase
- Service Role Key: sua service role key

### 5. Importar e ativar os fluxos

Importe os 7 arquivos de `n8n/workflows/` no n8n e ative cada um.

### 6. Configurar webhook na Hotmart

Aponte o webhook da Hotmart para:
```
https://[seu-n8n]/webhook/hotmart
```

Em **Hotmart → Ferramentas → Webhooks**, selecione o evento `PURCHASE_COMPLETE`.

---

## Estrutura do repositório

```
n8n/workflows/
  01-entrada-webhook-receiver.json
  02-vendas-sdr.json
  03-acompanhamento-tutor.json
  04-carrinho-abandonado.json
  05-upsell-concluidos.json
  06-metricas-trafego.json
  07-sync-progresso-hotmart.json

supabase/migrations/
  001_schema.sql
  002_cooldown_antispam.sql
  003_historico_contatos.sql
  004_view_metricas.sql
  005_trafego_dashboard.sql
  006_hotmart_product_id.sql

supabase/seeds/
  seed.sql

dify/apps/
  sdr-ia/   (prompt + knowledge base)
  tutor-ia/ (prompt + knowledge base)

docs/
  arquitetura.md
  fluxos/
    fluxo-entrada.md
    fluxo-sdr.md
    fluxo-tutor.md
```

---

## Dashboard (Google Looker Studio)

O Looker Studio conecta diretamente no Supabase via PostgreSQL.

**Passos para conectar:**
1. Acesse [lookerstudio.google.com](https://lookerstudio.google.com) → **Criar** → **Fonte de dados**
2. Selecione o conector **PostgreSQL**
3. Preencha com as credenciais do Supabase (Supabase → Settings → Database):
   - Host: `db.XXXX.supabase.co`
   - Porta: `5432` · Database: `postgres`
   - Username: `postgres` · Password: sua senha
4. Selecione as views como tabelas: `v_resumo_diario`, `v_roas_por_campanha`, `v_funil_completo`, `v_metricas_dashboard`, `v_conversao_por_produto`

> **Atenção:** Certifique-se de que o IP do Looker Studio está liberado em Supabase → Settings → Database → Connection Pooling.

**Estrutura do dashboard (3 páginas):**

| Página | Fonte principal | Widgets |
|--------|----------------|---------|
| **Tráfego** | `v_roas_por_campanha` | Investimento total, CPL médio, ROAS, spend por plataforma, tabela de campanhas, evolução diária |
| **Vendas** | `v_resumo_diario` | Faturamento, ticket médio, total de vendas, gráfico diário, PIX vs Cartão |
| **Funil** | `v_funil_completo` | Funil compradores → acessaram → engajados → concluídos, taxas de acesso e conclusão |

---

## Proteção anti-spam

Todas as views aplicam **cooldown cruzado**: um aluno não recebe mensagem de nenhum fluxo se já foi contatado recentemente.

| View | Cooldown SDR | Cooldown Tutor |
|------|-------------|----------------|
| `v_alunos_sdr_prioridade` | 7 dias | 7 dias |
| `v_alunos_tutor_acompanhamento` | 7 dias | 7 dias |
| `v_pix_abandonados` | 24 horas | — |

---

## Dados reais

- **876** alunos · **871** com WhatsApp
- **11** produtos no catálogo
- **871** transações · **R$ 23.548,30** faturados
