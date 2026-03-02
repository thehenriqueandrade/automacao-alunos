#!/bin/bash
# Teste do webhook Hotmart
# URL: https://webhook.ohenriqueandrade.com.br/webhook/hotmart
# Método: POST
# Header: Content-Type: application/json
#
# Uso:
#   ./scripts/test-webhook-hotmart.sh                          # imprime payload
#   ./scripts/test-webhook-hotmart.sh http://localhost:5678    # envia para n8n local

PAYLOAD=$(cat <<'EOF'
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
)

if [ -z "$1" ]; then
  echo "$PAYLOAD"
else
  N8N_URL="${1}/webhook/hotmart"
  echo "Enviando para: $N8N_URL"
  curl -s -X POST "$N8N_URL" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" | jq . 2>/dev/null || echo "(resposta recebida)"
fi
