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

## Mapeamento de campos — payload Pagtrust → campos internos

| Caminho no JSON Pagtrust | Campo interno |
|--------------------------|---------------|
| `body.data.buyer.name` | `nome` |
| `body.data.buyer.checkout_phone` (só dígitos) | `whatsapp` |
| `body.data.buyer.email` | `email` |
| `body.data.purchase.transaction` | `order_id` |
| `body.data.purchase.full_price.value` | `valor` |
| `body.data.purchase.status` | `status` |
| `body.event` | `event` |
| `body.data.product.name` | `produto` |
| `body` (inteiro, JSON string) | `dados_raw` |

## Eventos Pagtrust conhecidos
| `event` | Significado |
|---------|-------------|
| `PURCHASE_APPROVED` | Compra aprovada (cartão/boleto pago) |
| `PIX_GENERATED` | Pix gerado — aguardando pagamento |
| `PURCHASE_REFUSED` | Pagamento recusado |
| `PURCHASE_REFUNDED` | Reembolso efetuado |
