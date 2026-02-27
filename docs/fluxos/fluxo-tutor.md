# Fluxo 03 — Acompanhamento: Tutor IA

## Gatilhos
- **Cron**: toda segunda-feira às 09h.
- **Webhook**: evento de conclusão ou acesso de aula vindo da plataforma de ensino.

## Etapas

```
[Cron / Webhook Trigger]
      │
      ▼
[Supabase: SELECT v_ultimo_acesso_aluno]
      │ WHERE dias_sem_acesso >= {threshold} (ex: 7 dias)
      ▼
[SplitInBatches — loop por aluno]
      │
      ▼
[HTTP Request → Dify App Tutor]
      │ POST /chat-messages com: nome, ultima_aula, dias_sem_acesso, proxima_aula
      ├── [Error Handler] → Z-API: notifica WhatsApp pessoal ("Erro Dify Tutor: {erro}")
      ▼
[Z-API: Send Message]
      │ envia mensagem de reengajamento ao aluno
      ├── [Error Handler] → Z-API: notifica WhatsApp pessoal ("Erro Z-API Tutor: {erro}")
      ▼
[Supabase: UPDATE aluno]
      │ registra data do último contato do tutor
```

## Parâmetro `threshold`
Definido como variável de ambiente no n8n (`TUTOR_DIAS_SEM_ACESSO`).
Valor padrão sugerido: **7 dias**.
