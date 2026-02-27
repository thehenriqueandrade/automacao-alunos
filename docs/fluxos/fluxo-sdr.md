# Fluxo 02 — Vendas: SDR IA

## Gatilhos
- Webhook externo: evento `ABANDONED_CART` ou `PAYMENT_REFUSED` da Pagtrust.
- Trigger manual: reengajamento pontual de leads.

## Etapas

```
[Webhook / Manual Trigger]
      │
      ▼
[Supabase: SELECT aluno]
      │ busca por whatsapp ou order_id
      ▼
[HTTP Request → Dify App SDR]
      │ POST /chat-messages com variáveis do aluno
      ├── [Error Handler] → Z-API: notifica WhatsApp pessoal ("Erro Dify SDR: {erro}")
      ▼
[Z-API: Send Message]
      │ envia resposta do Dify ao aluno
      ├── [Error Handler] → Z-API: notifica WhatsApp pessoal ("Erro Z-API SDR: {erro}")
      ▼
[Supabase: UPDATE aluno]
      │ registra data do último contato SDR
```

## Monitoramento de Erros
Cada nó HTTP deve ter **"Continue On Fail"** ativo e redirecionar para um nó que envia
mensagem ao WhatsApp pessoal do operador com detalhes do erro.
