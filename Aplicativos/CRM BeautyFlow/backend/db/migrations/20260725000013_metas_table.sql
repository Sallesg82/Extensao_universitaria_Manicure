-- ══════════════════════════════════════════════════════════════════════════════
-- Migration: Tabela de Metas Mensais Individuais
-- ══════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.metas (
    id SERIAL PRIMARY KEY,
    mes VARCHAR(7) NOT NULL,          -- Formato 'YYYY-MM' (ex: '2026-09')
    meta NUMERIC(12, 2) NOT NULL DEFAULT 7000.00,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    CONSTRAINT metas_mes_unique UNIQUE (mes)
);

-- Trigger em tempo real para disparar pgevents
DROP TRIGGER IF EXISTS trg_realtime_metas ON public.metas;
CREATE TRIGGER trg_realtime_metas
  AFTER INSERT OR UPDATE OR DELETE ON public.metas
  FOR EACH ROW EXECUTE FUNCTION notify_pgevents();

-- Inicializa o mês atual caso a tabela esteja vazia
DO $$
DECLARE
  current_m VARCHAR(7);
  default_meta NUMERIC(12, 2) := 7000.00;
  sett_val TEXT;
BEGIN
  current_m := to_char(CURRENT_DATE, 'YYYY-MM');
  
  -- Se houver meta configurada em settings, aproveita o valor
  SELECT value INTO sett_val FROM public.settings WHERE key = 'meta_mensal' LIMIT 1;
  IF sett_val IS NOT NULL AND sett_val ~ '^[0-9]+(\.[0-9]+)?$' THEN
    default_meta := sett_val::NUMERIC;
  END IF;

  INSERT INTO public.metas (mes, meta)
  VALUES (current_m, default_meta)
  ON CONFLICT (mes) DO NOTHING;
END $$;
