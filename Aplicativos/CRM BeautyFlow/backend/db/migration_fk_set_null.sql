-- Migration: alterar FK de appointments.client_id de CASCADE para SET NULL
-- Motivo: excluir um cliente NÃO deve remover seus agendamentos/receitas.
-- Execute no SQL Editor do Supabase.

-- 1. Remover a FK existente (descobrir o nome real primeiro)
DO $$
DECLARE
    fk_name TEXT;
BEGIN
    SELECT con.conname INTO fk_name
    FROM pg_constraint con
    JOIN pg_class rel ON rel.oid = con.conrelid
    WHERE rel.relname = 'appointments'
      AND con.contype = 'f'
      AND con.confrelid = (SELECT oid FROM pg_class WHERE relname = 'clients');

    IF fk_name IS NOT NULL THEN
        EXECUTE 'ALTER TABLE appointments DROP CONSTRAINT ' || fk_name;
    END IF;
END $$;

-- 2. Tornar client_id opcional (permitir NULL)
ALTER TABLE appointments ALTER COLUMN client_id DROP NOT NULL;

-- 3. Recriar a FK com ON DELETE SET NULL
ALTER TABLE appointments
    ADD CONSTRAINT appointments_client_id_fkey
    FOREIGN KEY (client_id) REFERENCES clients(id) ON DELETE SET NULL;

-- 4. Atualizar view v_clients para ignorar clientes com client_id nulo
CREATE OR REPLACE VIEW v_clients AS
SELECT c.*,
    COALESCE(a.visits, 0) AS visits,
    COALESCE(a.total_spent, 0) AS total_spent,
    a.last_visit
FROM clients c
LEFT JOIN LATERAL (
    SELECT
        COUNT(*) AS visits,
        COALESCE(SUM(CASE WHEN a2.payment_status = 'paid' THEN a2.price ELSE 0 END), 0) AS total_spent,
        MAX(a2.appointment_date) AS last_visit
    FROM appointments a2
    WHERE a2.client_id = c.id AND a2.status != 'cancelled'
) a ON true;
