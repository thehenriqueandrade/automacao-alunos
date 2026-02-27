#!/usr/bin/env bash
# Simula um evento PURCHASE_APPROVED da Pagtrust para o n8n local.
# Uso: ./scripts/test-webhook.sh [URL_DO_WEBHOOK]

set -euo pipefail

WEBHOOK_URL="${1:-http://localhost:5678/webhook/pagtrust}"

echo "Disparando evento de teste para: $WEBHOOK_URL"

curl -s -X POST "$WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d '{
    "event": "PURCHASE_APPROVED",
    "order": {
      "id": "TEST-ORDER-001",
      "amount": 297.00,
      "status": "APPROVED"
    },
    "customer": {
      "name": "Aluno Teste",
      "phone": "5511999990001",
      "email": "teste@exemplo.com"
    }
  }' | jq .

echo ""
echo "Evento enviado."
