# Arquitetura — Automação de Alunos (SDR + Tutor)

## Visão Geral

```
Pagtrust ──────► n8n (Webhook Receiver)
                      │
                      ▼
                  Supabase (jornada_alunos)
                 /         \
        n8n (SDR)           n8n (Tutor)
             │                   │
       Dify App SDR         Dify App Tutor
             │                   │
             └────────┬──────────┘
                      ▼
                   Z-API
                      │
                      ▼
                  WhatsApp
```

## Camadas

| Camada         | Tecnologia     | Função                                          |
|----------------|----------------|-------------------------------------------------|
| Orquestração   | n8n            | Gerencia fluxos, webhooks e lógica de negócio   |
| IA             | Dify           | Geração de mensagens personalizadas             |
| Banco de dados | Supabase       | Estado e histórico dos alunos                   |
| Comunicação    | Z-API          | Envio de mensagens via WhatsApp                 |
| Infraestrutura | Easypanel/VPS  | Hospedagem dos containers (Dify + n8n)          |

## Fluxos n8n

1. **01 — Webhook Receiver**: porta de entrada para eventos da Pagtrust.
2. **02 — SDR**: recuperação de vendas ativada por abandono ou recusa de pagamento.
3. **03 — Tutor**: retenção de alunos ativada por Cron ou evento de acesso.

Detalhes em `docs/fluxos/`.

## Banco de Dados (jornada_alunos)

- `alunos` — cadastro único por WhatsApp.
- `transacoes` — registro de compras com payload original da Pagtrust.
- `progresso_aulas` — histórico de acessos para calcular `dias_sem_acesso`.
- `v_ultimo_acesso_aluno` — view agregada usada pelo Fluxo Tutor.
