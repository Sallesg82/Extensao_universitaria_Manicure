-- ══════════════════════════════════════════════════════════════════════════════
-- Realtime PostgreSQL triggers via pg_notify
-- ══════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION notify_pgevents() RETURNS trigger AS $$
DECLARE
  rec_id text;
  payload text;
BEGIN
  IF (TG_OP = 'DELETE') THEN
    BEGIN
      rec_id := OLD.id::text;
    EXCEPTION WHEN OTHERS THEN
      rec_id := NULL;
    END;
  ELSE
    BEGIN
      rec_id := NEW.id::text;
    EXCEPTION WHEN OTHERS THEN
      rec_id := NULL;
    END;
  END IF;

  payload := json_build_object(
    'table', TG_TABLE_NAME,
    'action', TG_OP,
    'id', rec_id
  )::text;

  PERFORM pg_notify('pgevents', payload);
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_realtime_appointments ON appointments;
CREATE TRIGGER trg_realtime_appointments
  AFTER INSERT OR UPDATE OR DELETE ON appointments
  FOR EACH ROW EXECUTE FUNCTION notify_pgevents();

DROP TRIGGER IF EXISTS trg_realtime_transactions ON transactions;
CREATE TRIGGER trg_realtime_transactions
  AFTER INSERT OR UPDATE OR DELETE ON transactions
  FOR EACH ROW EXECUTE FUNCTION notify_pgevents();

DROP TRIGGER IF EXISTS trg_realtime_clients ON clients;
CREATE TRIGGER trg_realtime_clients
  AFTER INSERT OR UPDATE OR DELETE ON clients
  FOR EACH ROW EXECUTE FUNCTION notify_pgevents();

DROP TRIGGER IF EXISTS trg_realtime_services ON services;
CREATE TRIGGER trg_realtime_services
  AFTER INSERT OR UPDATE OR DELETE ON services
  FOR EACH ROW EXECUTE FUNCTION notify_pgevents();

DROP TRIGGER IF EXISTS trg_realtime_settings ON settings;
CREATE TRIGGER trg_realtime_settings
  AFTER INSERT OR UPDATE OR DELETE ON settings
  FOR EACH ROW EXECUTE FUNCTION notify_pgevents();

DROP TRIGGER IF EXISTS trg_realtime_business_hours ON business_hours;
CREATE TRIGGER trg_realtime_business_hours
  AFTER INSERT OR UPDATE OR DELETE ON business_hours
  FOR EACH ROW EXECUTE FUNCTION notify_pgevents();

DROP TRIGGER IF EXISTS trg_realtime_notifications ON notifications;
CREATE TRIGGER trg_realtime_notifications
  AFTER INSERT OR UPDATE OR DELETE ON notifications
  FOR EACH ROW EXECUTE FUNCTION notify_pgevents();

DROP TRIGGER IF EXISTS trg_realtime_users ON users;
CREATE TRIGGER trg_realtime_users
  AFTER INSERT OR UPDATE OR DELETE ON users
  FOR EACH ROW EXECUTE FUNCTION notify_pgevents();

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'products') THEN
    DROP TRIGGER IF EXISTS trg_realtime_products ON products;
    CREATE TRIGGER trg_realtime_products
      AFTER INSERT OR UPDATE OR DELETE ON products
      FOR EACH ROW EXECUTE FUNCTION notify_pgevents();
  END IF;
END $$;
