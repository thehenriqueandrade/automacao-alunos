#!/usr/bin/env bash
# Aplica todas as migrations no Supabase via CLI.
# Requer: supabase CLI instalado e projeto linkado (supabase link --project-ref <REF>).

set -euo pipefail

echo "Aplicando migrations no Supabase..."

for file in "$(dirname "$0")/../supabase/migrations"/*.sql; do
  echo "  → $file"
  supabase db push --file "$file"
done

echo "Migrations aplicadas com sucesso."
