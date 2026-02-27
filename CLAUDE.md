# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Projeto

**automacao-alunos** — sistema de automação de comunicação com alunos usando IA, composto por dois agentes distintos (SDR e Tutor) orquestrados via n8n, com Dify como backend de IA e Supabase como banco de dados de estado.

## Infraestrutura

- **VPS Hostinger / Easypanel** — hospeda os containers de Dify e n8n.
- **Dify** — backend de IA; dois Apps independentes (`sdr-ia`, `tutor-ia`).
- **n8n** — orquestrador de fluxos e receptor de webhooks.
- **Supabase** — banco `jornada_alunos` com as tabelas `alunos`, `transacoes`, `progresso_aulas`.
- **Z-API** — canal único de saída via WhatsApp.
- **Pagtrust** — fonte dos eventos de compra (`PURCHASE_APPROVED`, `ABANDONED_CART`, `PAYMENT_REFUSED`).

## Arquitetura em camadas

```
Pagtrust ──► n8n Fluxo 01 (Webhook Receiver)
                     │
                 Supabase
                /         \
  n8n Fluxo 02 (SDR)    n8n Fluxo 03 (Tutor)
        │                       │
  Dify App SDR             Dify App Tutor
        └──────────┬────────────┘
                   ▼
                Z-API → WhatsApp
```

## Estrutura do repositório

```
dify/apps/sdr-ia/           # Prompt e knowledge base do agente de vendas
dify/apps/tutor-ia/         # Prompt e knowledge base do agente tutor
n8n/workflows/              # Exports JSON dos 3 fluxos (templates comentados)
supabase/migrations/        # SQL para criar as tabelas e views
supabase/seeds/             # Dados de teste para desenvolvimento
docs/fluxos/                # Documentação detalhada de cada fluxo n8n
scripts/                    # Utilitários de setup e teste
```

## Fluxos n8n

| Arquivo | Gatilho | Função |
|---------|---------|--------|
| `01-entrada-webhook-receiver.json` | POST da Pagtrust | Normaliza e persiste dados no Supabase |
| `02-vendas-sdr.json` | Webhook (abandono/recusa) | Consulta Dify SDR e envia via Z-API |
| `03-acompanhamento-tutor.json` | Cron (toda segunda 09h) | Detecta ausência, consulta Dify Tutor e envia via Z-API |

## Banco de dados

- `alunos` — chave única: `whatsapp`.
- `transacoes` — chave única: `order_id`; campo `dados_raw` (JSONB) guarda o payload bruto da Pagtrust.
- `progresso_aulas` — rastreia cada acesso; view `v_ultimo_acesso_aluno` expõe `dias_sem_acesso`.

## Comandos úteis

```bash
# Aplicar migrations no Supabase (requer CLI linkado ao projeto)
./scripts/apply-migrations.sh

# Simular evento PURCHASE_APPROVED para testar o Fluxo 01
./scripts/test-webhook.sh http://localhost:5678/webhook/pagtrust
```

## Configuração de ambiente

Copie `.env.example` para `.env` e preencha:
- `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY`
- `DIFY_API_KEY_SDR` + `DIFY_API_KEY_TUTOR`
- `ZAPI_INSTANCE_ID` + `ZAPI_TOKEN`
- `OPERADOR_WHATSAPP` — WhatsApp pessoal que recebe alertas de erro dos fluxos

## Monitoramento de erros (padrão obrigatório)

Em todo nó HTTP Request dos fluxos n8n (chamadas ao Dify e à Z-API):
1. Ativar **"Continue On Fail"**.
2. Adicionar nó de erro que envia mensagem ao `OPERADOR_WHATSAPP` com o texto:
   `"Erro no fluxo [NOME]: [nó] retornou [código/mensagem]"`.
