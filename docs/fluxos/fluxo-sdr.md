# Fluxo 02 — Vendas: SDR IA

## Gatilho

`POST /webhook/sdr-trigger`

Payload esperado:
```json
{
  "whatsapp": "5511999990001",
  "link_checkout": "https://..."
}
```

## Diagrama

```
[SDR — Webhook]
       │
       ▼
[Supabase — Buscar Aluno SDR]        ← view v_alunos_sdr_prioridade
       │ nome, whatsapp, produtos, status_aluno, menor_progresso
       ▼
[Dify — SDR IA]
       │
       ▼
[Dify respondeu?]
       │ sim                          │ não
       ▼                              ▼
[Z-API — Enviar Aluno]     [Z-API — Erro Dify (notificar operador)]
       │
       ▼
[Z-API enviou?]
       │ sim                          │ não
       ▼                              ▼
[Supabase — Update SDR]    [Z-API — Erro Z-API (notificar operador)]
  ultimo_contato_sdr = now()
```

## Fonte dos alunos

O nó **Supabase — Buscar Aluno SDR** consulta a view `v_alunos_sdr_prioridade`, que retorna:

| Campo | Descrição |
|-------|-----------|
| `id` | UUID do aluno |
| `nome` | Nome completo |
| `email` | Email |
| `whatsapp` | Número (sem DDI) |
| `status_aluno` | `nunca_acessou` ou `inativo` |
| `ultimo_contato_sdr` | Data do último disparo SDR |
| `produtos` | Produtos do aluno agregados com STRING_AGG |
| `menor_progresso` | Menor progresso entre todos os produtos (%) |
| `maior_valor` | Valor da maior transação |
| `ultima_compra` | Data da compra mais recente |

Apenas alunos com `whatsapp` preenchido e `bloqueado_antipirataria = false` aparecem na view.

## Inputs enviados ao Dify

```json
{
  "inputs": {
    "nome": "...",
    "whatsapp": "...",
    "produtos": "Naturalidade Express, Molde F1 Premium",
    "status_aluno": "nunca_acessou",
    "menor_progresso": "0",
    "link_checkout": "..."
  },
  "query": "Gere uma mensagem de recuperação de vendas personalizada para este lead.",
  "response_mode": "blocking",
  "conversation_id": "",
  "user": "whatsapp_do_aluno"
}
```

O Dify recebe a lista de produtos como string e gera **uma única mensagem** personalizada para o aluno.

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
SET ultimo_contato_sdr = NOW()
WHERE whatsapp = '{whatsapp}'
```

## Monitoramento de erros

| Situação | Ação |
|----------|------|
| Dify não retorna `answer` | Z-API notifica `OPERADOR_WHATSAPP` com payload bruto da resposta Dify |
| Z-API não retorna `zaapId`/`messageId` | Z-API notifica `OPERADOR_WHATSAPP` com payload bruto da resposta Z-API |

## Variáveis de ambiente necessárias

| Variável | Descrição |
|----------|-----------|
| `DIFY_BASE_URL` | URL base da API Dify (ex: `https://dify.seudominio.com/v1`) |
| `DIFY_API_KEY_SDR` | API Key do App SDR no Dify |
| `ZAPI_INSTANCE_ID` | ID da instância Z-API |
| `ZAPI_TOKEN` | Token da instância Z-API |
| `ZAPI_CLIENT_TOKEN` | Client-Token da conta Z-API |
| `OPERADOR_WHATSAPP` | WhatsApp pessoal do operador com DDI (ex: `5511999990000`) |
