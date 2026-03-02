-- ============================================================
-- Migration: 006_hotmart_product_id.sql
-- Adiciona hotmart_product_id na tabela produtos para
-- permitir sincronização de progresso via API Hotmart (Fluxo 07).
-- ============================================================

ALTER TABLE produtos
ADD COLUMN IF NOT EXISTS hotmart_product_id TEXT;

COMMENT ON COLUMN produtos.hotmart_product_id IS
  'ID do produto na plataforma Hotmart. Usado pelo Fluxo 07 para sincronizar progresso via API.';


-- ============================================================
-- Após rodar esta migration, preencha os IDs no Supabase:
-- (substituir pelos IDs reais obtidos no painel Hotmart)
-- ============================================================

-- UPDATE produtos SET hotmart_product_id = 'XXXXX' WHERE nome = 'Naturalidade Express';
-- UPDATE produtos SET hotmart_product_id = 'XXXXX' WHERE nome = 'Masterclass Naturalidade Sem Segredos';
-- ... repetir para todos os 11 produtos
