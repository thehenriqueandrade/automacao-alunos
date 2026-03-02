# Tarefas — Migração Pagtrust → Hotmart

## Contexto
Substituição completa da integração Pagtrust pela Hotmart. O Fluxo 01 precisa ser atualizado para o novo payload. Um novo Fluxo 07 deve sincronizar progresso e acesso dos alunos via API da Hotmart.

Repositório: https://github.com/thehenriqueandrade/automacao-alunos

---

## TAREFA 1 — Atualizar Fluxo 01 para o payload da Hotmart

**Arquivo:** `n8n/workflows/01-entrada-webhook-receiver.json`

Substituir o nó **"Normalizar Campos"** com o novo mapeamento:

```json
{
  "name": "Normalizar Campos",
  "type": "n8n-nodes-base.set",
  "parameters": {
    "mode": "manual",
    "fields": {
      "values": [
        {
          "name": "nome",
          "type": "stringValue",
          "stringValue": "={{ $json.body.data.buyer.name }}"
        },
        {
          "name": "whatsapp",
          "type": "stringValue",
          "stringValue": "={{ $json.body.data.buyer.checkout_phone?.toString().replace(/\\D/g, '') }}"
        },
        {
          "name": "email",
          "type": "stringValue",
          "stringValue": "={{ $json.body.data.buyer.email }}"
        },
        {
          "name": "cidade",
          "type": "stringValue",
          "stringValue": "={{ $json.body.data.buyer.address?.city ?? null }}"
        },
        {
          "name": "estado",
          "type": "stringValue",
          "stringValue": "={{ $json.body.data.buyer.address?.state ?? null }}"
        },
        {
          "name": "order_id",
          "type": "stringValue",
          "stringValue": "={{ $json.body.data.purchase.transaction }}"
        },
        {
          "name": "valor",
          "type": "numberValue",
          "numberValue": "={{ $json.body.data.purchase.price.value }}"
        },
        {
          "name": "metodo_pagamento",
          "type": "stringValue",
          "stringValue": "={{ $json.body.data.purchase.payment.type }}"
        },
        {
          "name": "status",
          "type": "stringValue",
          "stringValue": "={{ $json.body.data.purchase.status }}"
        },
        {
          "name": "event",
          "type": "stringValue",
          "stringValue": "={{ $json.body.event }}"
        },
        {
          "name": "produto",
          "type": "stringValue",
          "stringValue": "={{ $json.body.data.product.name }}"
        },
        {
          "name": "dados_raw",
          "type": "objectValue",
          "objectValue": "={{ $json.body }}"
        }
      ]
    }
  }
}
```

Atualizar também:
- Nome do nó webhook de `"Pagtrust — Webhook"` para `"Hotmart — Webhook"`
- Path do webhook de `"pagtrust"` para `"hotmart"`
- Nota de configuração no sticky note para refletir a nova integração

Adicionar filtro no início do fluxo para processar apenas eventos relevantes:

```json
{
  "name": "Evento Válido?",
  "type": "n8n-nodes-base.if",
  "parameters": {
    "conditions": {
      "conditions": [
        {
          "leftValue": "={{ $json.body.event }}",
          "operator": { "type": "string", "operation": "equals" },
          "rightValue": "PURCHASE_COMPLETE"
        }
      ]
    }
  }
}
```

Conectar: `Hotmart — Webhook` → `Evento Válido?` → TRUE → `Normalizar Campos`
A saída FALSE do IF não precisa de conexão (ignora outros eventos silenciosamente).

---

## TAREFA 2 — Fluxo 07: Sincronização de Progresso via API Hotmart

**Arquivo:** `n8n/workflows/07-sync-progresso-hotmart.json`

### Lógica:
- Gatilho: Cron diário às 06h (antes do Cron do Tutor às 09h)
- Para cada produto ativo no banco, busca o progresso dos alunos via API Hotmart
- Atualiza `aluno_produtos.progresso_pct` e `aluno_produtos.ultimo_acesso`
- Atualiza `alunos.status_aluno` com base no progresso calculado

### Regras de status por progresso:
```
progresso = 0%          → nunca_acessou (se nunca teve acesso) ou inativo
0% < progresso < 30%    → iniciante
30% <= progresso < 70%  → em_andamento
70% <= progresso < 100% → quase_concluindo
progresso = 100%        → concluido
```

### Estrutura dos nós:

```
Cron — Diário 06h
  → Supabase — Buscar Produtos Ativos
  → Loop por Produto
      → Hotmart — Gerar Access Token
          POST https://api-sec-vlc.hotmart.com/security/oauth/token
          Header: Authorization: Basic {{ $env.HOTMART_BASIC_TOKEN }}
          Body: grant_type=client_credentials
      → Hotmart — Buscar Progresso
          GET https://developers.hotmart.com/club/api/v1/pages/progress
          Header: Authorization: Bearer {{ $json.access_token }}
          Params: product_id={{ $('Supabase — Buscar Produtos Ativos').item.json.hotmart_product_id }}
      → Tem dados? (IF: items > 0)
          ✅ Sim → Loop por Aluno
              → Calcular Status (Code node)
              → Supabase — Buscar Aluno por Email
              → Aluno existe? (IF)
                  ✅ Sim → Supabase — Update aluno_produtos (progresso + ultimo_acesso)
                         → Supabase — Update alunos (status_aluno)
                  ❌ Não → ignorar (aluno não está na base ainda)
          ❌ Não → próximo produto
```

### Nó Code — Calcular Status:
```javascript
const progresso = $json.progress_percentage || 0;
const temAcesso = $json.last_access_date != null;

let status;
if (progresso === 0 && !temAcesso) {
  status = 'nunca_acessou';
} else if (progresso === 0) {
  status = 'inativo';
} else if (progresso < 30) {
  status = 'iniciante';
} else if (progresso < 70) {
  status = 'em_andamento';
} else if (progresso < 100) {
  status = 'quase_concluindo';
} else {
  status = 'concluido';
}

return [{
  json: {
    email: $json.subscriber_email,
    progresso_pct: Math.round(progresso),
    ultimo_acesso: $json.last_access_date || null,
    status_aluno: status
  }
}];
```

### Nó Supabase — Update aluno_produtos:
```
Operation: Update
Table: aluno_produtos
Select Conditions: aluno_id (do Supabase Buscar Aluno) + produto_id (do loop)
Fields to Update:
  progresso_pct: {{ $json.progresso_pct }}
  ultimo_acesso: {{ $json.ultimo_acesso }}
```

### Nó Supabase — Update alunos:
```
Operation: Update
Table: alunos
Select Conditions: email = {{ $json.email }}
Fields to Update:
  status_aluno: {{ $json.status_aluno }}
```

---

## TAREFA 3 — Migration: adicionar hotmart_product_id na tabela produtos

**Arquivo:** `supabase/migrations/006_hotmart_product_id.sql`

```sql
-- Adiciona ID do produto na Hotmart para uso na API de progresso
ALTER TABLE produtos
ADD COLUMN IF NOT EXISTS hotmart_product_id TEXT;

-- Comentário explicativo
COMMENT ON COLUMN produtos.hotmart_product_id IS 
  'ID do produto na plataforma Hotmart. Usado pelo Fluxo 07 para sincronizar progresso via API.';
```

Após rodar a migration, atualizar manualmente os IDs no Supabase:
```sql
-- Exemplo — substituir pelos IDs reais da Hotmart
UPDATE produtos SET hotmart_product_id = 'XXXXX' WHERE nome = 'Naturalidade Express';
UPDATE produtos SET hotmart_product_id = 'XXXXX' WHERE nome = 'Masterclass Naturalidade Sem Segredos';
-- ... repetir para todos os 11 produtos
```

---

## TAREFA 4 — Payload de teste para Thunder Client

**Arquivo:** `scripts/test-webhook-hotmart.sh`

```bash
#!/bin/bash
# Teste do webhook Hotmart no Thunder Client
# URL: https://webhook.ohenriqueandrade.com.br/webhook/hotmart
# Método: POST
# Header: Content-Type: application/json

cat << 'EOF'
{
  "event": "PURCHASE_COMPLETE",
  "id": "evt_hotmart_test_001",
  "creation_date": 1709400000000,
  "data": {
    "product": {
      "id": 12345678,
      "name": "Naturalidade Express",
      "ucode": "abc123test"
    },
    "buyer": {
      "name": "Aluna Teste Hotmart",
      "email": "aluna.hotmart@email.com",
      "checkout_phone": "5511999990002",
      "address": {
        "city": "São Paulo",
        "state": "SP"
      }
    },
    "purchase": {
      "transaction": "HP00000000000001",
      "order_date": "2024-03-02T10:00:00.000Z",
      "approved_date": "2024-03-02T10:01:00.000Z",
      "status": "COMPLETE",
      "payment": {
        "type": "PIX",
        "installments_number": 1
      },
      "price": {
        "value": 97.0,
        "currency_value": "BRL"
      }
    }
  }
}
EOF
```

---

## TAREFA 5 — Atualizar CLAUDE.md e README.md

Refletir:
- Migração completa da Pagtrust para Hotmart
- Novo mapeamento de campos no Fluxo 01
- Fluxo 07 de sincronização de progresso
- Migration 006 com hotmart_product_id
- Novas variáveis de ambiente (HOTMART_CLIENT_ID, HOTMART_CLIENT_SECRET, HOTMART_BASIC_TOKEN)
- Remover todas as referências à Pagtrust
- Atualizar a URL do webhook de /pagtrust para /hotmart

---

## Ordem de execução

1. Rodar `006_hotmart_product_id.sql` no Supabase
2. Atualizar os `hotmart_product_id` dos 11 produtos no Supabase
3. Importar o Fluxo 01 atualizado no n8n
4. Importar o Fluxo 07 no n8n
5. Cadastrar variáveis de ambiente da Hotmart no n8n
6. Configurar webhook na Hotmart com a nova URL
7. Testar com o payload de teste via Thunder Client
8. Validar que Supabase recebeu os dados corretamente
