-- Seed: dados de referência e teste
-- Execute apenas em ambiente de desenvolvimento/staging.

-- ============================================================
-- Produtos reais (11)
-- ============================================================

INSERT INTO produtos (nome) VALUES
  ('Naturalidade Express'),
  ('Masterclass Naturalidade Sem Segredos'),
  ('Molde F1 Premium'),
  ('A EVOLUÇAO DA MANICURE'),
  ('Aplicação Quadrada Detalhada'),
  ('Curso Unha Côncava'),
  ('A Arte das Misturinhas'),
  ('Combo de Carnaval'),
  ('Método Simples e Eficaz'),
  ('Almond Design PRO'),
  ('Lista Materiais Molde F1')
ON CONFLICT (nome) DO NOTHING;

-- ============================================================
-- Alunos de teste
-- ============================================================

INSERT INTO alunos (nome, email, whatsapp) VALUES
  ('Aluno Teste 1', 'teste1@exemplo.com', '5511999990001'),
  ('Aluno Teste 2', 'teste2@exemplo.com', '5511999990002')
ON CONFLICT (email) DO NOTHING;
