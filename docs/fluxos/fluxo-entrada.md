# Fluxo 01 — Entrada: Webhook Receiver

## Gatilho

`POST /webhook/pagtrust` — eventos enviados pela Pagtrust (PURCHASE_APPROVED, PIX_GENERATED, PURCHASE_REFUSED, PURCHASE_REFUNDED, etc.).

## Diagrama

```
[Pagtrust — Webhook]
       │ payload bruto
       ▼
[Normalizar Campos]
       │ nome, email, whatsapp, order_id, valor, status, event, produto, dados_raw
       ▼
[Supabase — Create Aluno]  ──onError──►  [Aluno Criado?]
                                              │ sim (id existe)        │ não (409)
                                              ▼                        ▼
                                      [Merge — Aluno] ◄── [Supabase — Buscar Aluno]
                                              │
                                              ▼
                                   [Supabase — Create Transação]
                                              │
                                              ▼
                                   [Supabase — Create Produto]  ──onError──►  [Produto Criado?]
                                                                                    │ sim       │ não (409)
                                                                                    ▼           ▼
                                                                            [Merge — Produto] ◄── [Supabase — Buscar Produto]
                                                                                    │
                                                                                    ▼
                                                                       [Supabase — Create aluno_produtos]
```

## Mapeamento de campos — payload Pagtrust → campos internos

| Caminho no JSON Pagtrust | Campo interno |
|--------------------------|---------------|
| `body.data.buyer.name` | `nome` |
| `body.data.buyer.checkout_phone` (só dígitos) | `whatsapp` |
| `body.data.buyer.email` | `email` |
| `body.orderId` | `order_id` |
| `body.data.purchase.full_price.value` | `valor` |
| `body.data.purchase.status` | `status` |
| `body.event` | `event` |
| `body.data.product.name` | `produto` |
| `body` (objeto inteiro) | `dados_raw` |

> **Atenção:** `order_id` vem de `body.orderId` (raiz do payload), não de `body.data.purchase.transaction`.

## Lógica de upsert

O nó nativo Supabase não suporta `ON CONFLICT`. O upsert é feito manualmente:

1. **Tenta criar** o registro.
2. Se **sucesso** (resposta contém `id`) → segue adiante.
3. Se **409 / sem id** → busca o registro existente pela chave única.
4. **Merge** une as duas branches garantindo que o `id` sempre segue para a próxima etapa.

| Entidade | Chave única | Nó de busca |
|----------|-------------|-------------|
| Aluno    | `email`     | Supabase — Buscar Aluno |
| Produto  | `nome`      | Supabase — Buscar Produto |

## Eventos Pagtrust conhecidos

| `event` | Significado |
|---------|-------------|
| `PURCHASE_APPROVED` | Compra aprovada (cartão/boleto pago) |
| `PIX_GENERATED` | Pix gerado — aguardando pagamento |
| `PURCHASE_REFUSED` | Pagamento recusado |
| `PURCHASE_REFUNDED` | Reembolso efetuado |

## Tabelas gravadas

| Tabela | Operação | Observação |
|--------|----------|------------|
| `alunos` | INSERT (ou leitura se 409) | Upsert por `email` |
| `transacoes` | INSERT | `onError: continueRegularOutput` — duplicatas ignoradas via `order_id` UNIQUE |
| `produtos` | INSERT (ou leitura se 409) | Upsert por `nome` |
| `aluno_produtos` | INSERT | `onError: continueRegularOutput` — duplicatas ignoradas via UNIQUE(aluno_id, produto_id) |
