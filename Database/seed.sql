-- only for the   the  currency exchange center :-

INSERT INTO currency_rates (currency, rate_to_inr) VALUES
 ('INR', 1), ('USD', 83.50), ('EUR', 90.20), ('GBP', 105.80), ('AED', 22.73)
ON CONFLICT (currency) DO UPDATE SET rate_to_inr = EXCLUDED.rate_to_inr, updated_at = NOW();
