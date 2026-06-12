-- Migration: adicionar CPF aos clientes
ALTER TABLE clients ADD COLUMN IF NOT EXISTS cpf TEXT DEFAULT '';
