-- Migration: adicionar status de pagamento aos agendamentos
-- Execute no SQL Editor do Supabase

ALTER TABLE appointments
    ADD COLUMN IF NOT EXISTS payment_status TEXT NOT NULL DEFAULT 'unpaid';

-- Garantir valores válidos (ignorar se constraint já existir)
DO $$
BEGIN
    ALTER TABLE appointments
        ADD CONSTRAINT appointments_payment_status_check
        CHECK (payment_status IN ('paid', 'unpaid'));
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

-- Migrar dados existentes: agendamentos que já contavam na receita ficam como pagos
UPDATE appointments
SET payment_status = 'paid'
WHERE status NOT IN ('cancelled', 'pending')
  AND payment_status = 'unpaid';

CREATE INDEX IF NOT EXISTS idx_appointments_payment_status ON appointments (payment_status);

-- Atualizar view de clientes (total_spent baseado em pagamento)
CREATE OR REPLACE VIEW v_clients AS
SELECT
    c.*,
    COALESCE(a.visits, 0) AS visits,
    COALESCE(a.total_spent, 0) AS total_spent,
    a.last_visit
FROM clients c
LEFT JOIN LATERAL (
    SELECT
        COUNT(*) AS visits,
        COALESCE(SUM(CASE WHEN payment_status = 'paid' THEN price ELSE 0 END), 0) AS total_spent,
        MAX(appointment_date) AS last_visit
    FROM appointments
    WHERE client_id = c.id AND status != 'cancelled'
) a ON true;
