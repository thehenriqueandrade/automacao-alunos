# Arquitetura — Automação de Alunos (SDR + Tutor)

## Visão Geral

```
Pagtrust ──────► n8n (Fluxo 01 — Webhook Receiver)
                          │
                          ▼
                  Supabase (jornada_alunos)
                 /                         \
    n8n (Fluxo 02 — SDR)       n8n (Fluxo 03 — Tutor)
               │                            │
         Dify App SDR                 Dify App Tutor
               │                            │
               └──────────────┬─────────────┘
                               ▼
                            Z-API
                               │
                               ▼
                           WhatsApp
```

## Camadas

| Camada         | Tecnologia     | Função                                            |
|----------------|----------------|---------------------------------------------------|
| Orquestração   | n8n            | Gerencia fluxos, webhooks e lógica de negócio     |
| IA             | Dify           | Geração de mensagens personalizadas por agente    |
| Banco de dados | Supabase       | Estado, histórico e segmentação dos alunos        |
| Comunicação    | Z-API          | Envio de mensagens via WhatsApp                   |
| Infraestrutura | Easypanel/VPS  | Hospedagem dos containers (Dify + n8n)            |
| Pagamentos     | Pagtrust       | Fonte dos eventos de compra via webhook           |

## Fluxos n8n

| # | Nome | Gatilho | Responsabilidade |
|---|------|---------|-----------------|
| 01 | Webhook Receiver | POST `/webhook/pagtrust` | Normaliza payload, upsert aluno/produto, persiste transação e vínculo aluno_produtos |
| 02 | SDR IA | POST `/webhook/sdr-trigger` | Recuperação de vendas: busca aluno na view SDR, gera mensagem via Dify, envia via Z-API |
| 03 | Tutor IA | Cron — toda segunda 09h | Retenção: detecta ausência via view Tutor, gera mensagem via Dify, envia via Z-API |

## Banco de Dados (jornada_alunos)

### Tabelas

| Tabela | Chave única | Descrição |
|--------|-------------|-----------|
| `produtos` | `nome` | 11 produtos reais do catálogo |
| `alunos` | `email` | Cadastro único por email; inclui status, contatos e flag antipirataria |
| `transacoes` | `order_id` | Compras recebidas via Pagtrust; payload bruto em `dados_raw` (JSONB) |
| `aluno_produtos` | `(aluno_id, produto_id)` | N:N entre alunos e produtos; rastreia `progresso_pct` e `ultimo_acesso` |

### Views

| View | Consumida por | Lógica |
|------|--------------|--------|
| `v_alunos_sdr_prioridade` | Fluxo 02 — SDR | `status IN (nunca_acessou, inativo)`, com whatsapp, 1 linha/aluno, produtos agregados |
| `v_alunos_tutor_acompanhamento` | Fluxo 03 — Tutor | `status IN (iniciante, em_andamento, quase_concluindo)`, com whatsapp, 1 linha/aluno, `dias_sem_acesso` calculado |
| `v_alunos_upsell` | Uso futuro | Alunos com ao menos 1 produto 100%; cursos concluídos agregados |

### Enums

- **`status_aluno`**: `nunca_acessou` → `inativo` → `iniciante` → `em_andamento` → `quase_concluindo` → `concluido`
- **`metodo_pagamento`**: `PIX` | `Cartao Credito` | `Boleto` | `Outro`

## Dados reais (base de produção)

- **876** alunos cadastrados (871 com WhatsApp)
- **11** produtos no catálogo
- **871** transações registradas
- **R$ 23.548,30** em faturamento total

## Produtos cadastrados

1. Naturalidade Express
2. Masterclass Naturalidade Sem Segredos
3. Molde F1 Premium
4. A EVOLUÇAO DA MANICURE
5. Aplicação Quadrada Detalhada
6. Curso Unha Côncava
7. A Arte das Misturinhas
8. Combo de Carnaval
9. Método Simples e Eficaz
10. Almond Design PRO
11. Lista Materiais Molde F1

## Padrão de monitoramento de erros

Em todo nó HTTP Request dos fluxos (Dify e Z-API):
1. Ativar **"Continue On Fail"**.
2. Branch de erro envia mensagem ao `OPERADOR_WHATSAPP`:
   `"⚠️ Erro no Fluxo [NOME]: [nó] retornou [código/mensagem]"`.
