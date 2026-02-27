-- Seed: dados de teste para desenvolvimento local
-- Execute apenas em ambiente de desenvolvimento/staging.

INSERT INTO alunos (nome, whatsapp, email) VALUES
    ('Aluno Teste 1', '5511999990001', 'teste1@exemplo.com'),
    ('Aluno Teste 2', '5511999990002', 'teste2@exemplo.com')
ON CONFLICT (whatsapp) DO NOTHING;
