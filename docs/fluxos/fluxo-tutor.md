# Fluxo 03 — Acompanhamento: Tutor IA

## Gatilho

**Cron — toda segunda-feira às 09h** (sem intervenção manual).

## Diagrama

```
[Cron — Segunda 09h]
       │
       ▼
[Supabase — Alunos Ausentes]         ← view v_alunos_tutor_acompanhamento
       │ filtra dias_sem_acesso >= TUTOR_DIAS_SEM_ACESSO
       ▼
[Loop por Aluno — SplitInBatches 1]
       │ processa um aluno por vez
       ▼
[Dify — Tutor IA]
       │
       ▼
[Dify respondeu?]
       │ sim                              │ não
       ▼                                  ▼
[Z-API — Enviar Aluno]       [Z-API — Erro Dify (notificar operador)]
       │                                  │
       ▼                                  └──► [Loop por Aluno] (próximo)
[Z-API enviou?]
       │ sim                              │ não
       ▼                                  ▼
[Supabase — Update Tutor]    [Z-API — Erro Z-API (notificar operador)]
  ultimo_contato_tutor = now()            │
       │                                  └──► [Loop por Aluno] (próximo)
       └──► [Loop por Aluno] (próximo)
```

## Fonte dos alunos

O nó **Supabase — Alunos Ausentes** usa o nó nativo Supabase (`getAll`, `returnAll: true`) na view `v_alunos_tutor_acompanhamento`, com filtro `dias_sem_acesso >= $env.TUTOR_DIAS_SEM_ACESSO`.

Campos retornados pela view:

| Campo | Descrição |
|-------|-----------|
| `id` | UUID do aluno |
| `nome` | Nome completo |
| `email` | Email |
| `whatsapp` | Número (sem DDI) |
| `status_aluno` | `iniciante`, `em_andamento` ou `quase_concluindo` |
| `ultimo_contato_tutor` | Data do último disparo Tutor |
| `produtos` | Produtos do aluno agregados com STRING_AGG |
| `menor_progresso` | Menor progresso entre todos os produtos (%) |
| `ultimo_acesso` | Data do acesso mais recente (MAX entre todos os produtos) |
| `dias_sem_acesso` | Dias desde `ultimo_acesso` até hoje |

Apenas alunos com `whatsapp` preenchido e `bloqueado_antipirataria = false` aparecem na view.

## Inputs enviados ao Dify

```json
{
  "inputs": {
    "nome": "...",
    "whatsapp": "...",
    "status_aluno": "em_andamento",
    "produtos": "Naturalidade Express, Molde F1 Premium",
    "menor_progresso": "42",
    "ultimo_acesso": "2026-02-10T14:30:00Z",
    "dias_sem_acesso": "18"
  },
  "query": "Gere uma mensagem motivacional de reengajamento para este aluno que está ausente há 18 dias.",
  "response_mode": "blocking",
  "conversation_id": "",
  "user": "whatsapp_do_aluno"
}
```

O Dify recebe a lista de produtos e o menor progresso e gera **uma única mensagem** motivacional personalizada por aluno.

## Envio via Z-API

```json
{
  "phone": "55{whatsapp}",
  "message": "{resposta do Dify}"
}
```

## Update pós-envio

Após confirmação de envio pela Z-API (`zaapId` ou `messageId` presentes na resposta):

```sql
UPDATE alunos
SET ultimo_contato_tutor = NOW()
WHERE whatsapp = '{whatsapp}'
```

Após o update, o fluxo retorna ao **Loop por Aluno** para processar o próximo.

## Parâmetro de ausência

| Variável | Padrão | Descrição |
|----------|--------|-----------|
| `TUTOR_DIAS_SEM_ACESSO` | `7` | Dias mínimos sem acesso para incluir o aluno no disparo |

## Monitoramento de erros

| Situação | Ação |
|----------|------|
| Dify não retorna `answer` | Z-API notifica `OPERADOR_WHATSAPP` com payload bruto da resposta Dify → loop continua |
| Z-API não retorna `zaapId`/`messageId` | Z-API notifica `OPERADOR_WHATSAPP` com payload bruto da resposta Z-API → loop continua |

O loop sempre avança para o próximo aluno independentemente de erros no aluno atual.

## Variáveis de ambiente necessárias

| Variável | Descrição |
|----------|-----------|
| `DIFY_BASE_URL` | URL base da API Dify (ex: `https://dify.seudominio.com/v1`) |
| `DIFY_API_KEY_TUTOR` | API Key do App Tutor no Dify |
| `ZAPI_INSTANCE_ID` | ID da instância Z-API |
| `ZAPI_TOKEN` | Token da instância Z-API |
| `ZAPI_CLIENT_TOKEN` | Client-Token da conta Z-API |
| `OPERADOR_WHATSAPP` | WhatsApp pessoal do operador com DDI (ex: `5511999990000`) |
| `TUTOR_DIAS_SEM_ACESSO` | Dias mínimos de ausência para disparar (padrão: `7`) |
