# automacao-alunos

Sistema de automação de comunicação com alunos via WhatsApp, usando IA generativa para recuperação de vendas e retenção de alunos ativos.

**Stack:** n8n · Dify · Supabase · Z-API · Pagtrust

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

Cinco fluxos n8n trabalham de forma autônoma:

| Fluxo | Gatilho | O que faz |
|-------|---------|-----------|
| **01 — Webhook Receiver** | POST da Pagtrust | Registra compra, aluno e produto no Supabase |
| **02 — SDR IA** | Webhook externo | Aborda leads que nunca acessaram ou ficaram inativos |
| **03 — Tutor IA** | Cron — toda segunda 09h | Reengaja alunos em progresso que pararam de acessar |
| **04 — Carrinho Abandonado** | Cron — a cada hora | Recupera PIX expirados entre 1h e 24h |
| **05 — Upsell** | Webhook manual | Oferece o próximo curso para quem já concluiu |

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

### Views principais

| View | Uso |
|------|-----|
| `v_alunos_sdr_prioridade` | Leads para o Fluxo 02 — cooldown 7 dias |
| `v_alunos_tutor_acompanhamento` | Alunos para o Fluxo 03 — cooldown 7 dias, ordenados por prioridade |
| `v_pix_abandonados` | PIX expirados para o Fluxo 04 — cooldown 24h |
| `v_alunos_upsell` | Alunos com curso(s) concluídos para o Fluxo 05 |
| `v_metricas_dashboard` | Totais por status e atividade semanal |
| `v_conversao_por_produto` | Taxa de conclusão e progresso médio por produto |

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
```

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

### 4. Credencial Supabase no n8n

Em **Settings → Credentials → Add → Supabase**:
- Nome: `Supabase — jornada_alunos`
- URL: URL do seu projeto Supabase
- Service Role Key: sua service role key

### 5. Importar e ativar os fluxos

Importe os 5 arquivos de `n8n/workflows/` no n8n e ative cada um.

### 6. Configurar webhook na Pagtrust

Aponte o webhook da Pagtrust para:
```
https://[seu-n8n]/webhook/pagtrust
```

---

## Estrutura do repositório

```
n8n/workflows/
  01-entrada-webhook-receiver.json
  02-vendas-sdr.json
  03-acompanhamento-tutor.json
  04-carrinho-abandonado.json
  05-upsell-concluidos.json

supabase/migrations/
  001_schema.sql
  002_cooldown_antispam.sql
  003_historico_contatos.sql
  004_view_metricas.sql

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
