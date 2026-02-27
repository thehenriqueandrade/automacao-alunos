# Fluxo 01 — Entrada: Webhook Receiver

## Gatilho
`POST /webhook/pagtrust` — evento `PURCHASE_APPROVED` enviado pela Pagtrust.

## Etapas

```
[Webhook Trigger]
      │ payload bruto da Pagtrust
      ▼
[Edit Fields]
      │ campos normalizados: nome, whatsapp, email, order_id, valor, status
      ▼
[Supabase: Upsert alunos]
      │ chave de conflito: whatsapp
      ▼
[Supabase: Insert transacoes]
      │ registra order_id, valor, status, dados_raw
      ▼
[HTTP Request] (opcional)
      │ dispara Fluxo SDR ou Tutor se necessário
```

## Campos esperados no payload Pagtrust
| Campo Pagtrust | Campo interno |
|----------------|---------------|
| `customer.name` | `nome` |
| `customer.phone` | `whatsapp` |
| `customer.email` | `email` |
| `order.id` | `order_id` |
| `order.amount` | `valor` |
| `order.status` | `status` |
