-- migrate:up
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

-- migrate:down
DROP VIEW IF EXISTS v_clients;
