-- =====================================================================
-- 05_descriptives.sql
-- Descriptive statistics for the loan sample (682 loans).
-- Run with Alt+X, compare each result tab with the notes above it.
-- =====================================================================

-- 1. Sample overview: size, outcome and time span
SELECT
    COUNT(*)                                   AS loans,
    SUM(default_flag)                          AS defaults,
    ROUND(AVG(default_flag) * 100, 1)          AS default_rate_pct,
    SUM(CASE WHEN status IN ('C','D') THEN 1 ELSE 0 END) AS running_loans,
    MIN(loan_date)                             AS first_loan,
    MAX(loan_date)                             AS last_loan
FROM loan_features;

-- 2. Outcome breakdown by status (A/B finished, C/D running)
SELECT status,
       CASE WHEN status IN ('B','D') THEN 'default' ELSE 'no default' END AS outcome,
       COUNT(*) AS loans,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM loan_features
GROUP BY status
ORDER BY status;

-- 3. Loan terms: distribution of amount, duration and instalment
SELECT
    'loan_amount' AS variable,
    ROUND(AVG(loan_amount))                                   AS mean,
    ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY loan_amount)) AS median,
    ROUND(MIN(loan_amount))                                   AS min,
    ROUND(MAX(loan_amount))                                   AS max
FROM loan_features
UNION ALL
SELECT 'duration_months', ROUND(AVG(duration),1),
       percentile_cont(0.5) WITHIN GROUP (ORDER BY duration), MIN(duration), MAX(duration)
FROM loan_features
UNION ALL
SELECT 'monthly_payment', ROUND(AVG(payments)),
       ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY payments)), ROUND(MIN(payments)), ROUND(MAX(payments))
FROM loan_features;

-- 4. Default rate by loan duration
SELECT duration AS duration_months,
       COUNT(*) AS loans, SUM(default_flag) AS defaults,
       ROUND(AVG(default_flag) * 100, 1) AS default_rate_pct
FROM loan_features
GROUP BY duration
ORDER BY duration;

-- 5. Default rate by loan size band
SELECT CASE WHEN loan_amount < 100000 THEN '1. under 100k'
            WHEN loan_amount < 200000 THEN '2. 100k-200k'
            WHEN loan_amount < 300000 THEN '3. 200k-300k'
            ELSE '4. 300k+' END AS loan_size_band,
       COUNT(*) AS loans, SUM(default_flag) AS defaults,
       ROUND(AVG(default_flag) * 100, 1) AS default_rate_pct
FROM loan_features
GROUP BY 1
ORDER BY 1;

-- 6. Default rate by client gender
SELECT gender, COUNT(*) AS loans, SUM(default_flag) AS defaults,
       ROUND(AVG(default_flag) * 100, 1) AS default_rate_pct
FROM loan_features
GROUP BY gender
ORDER BY gender;


-- 7. Default rate by region (district region, via account)
SELECT d.region, COUNT(*) AS loans, SUM(lf.default_flag) AS defaults,
       ROUND(AVG(lf.default_flag) * 100, 1) AS default_rate_pct
FROM loan_features lf
JOIN account  a ON a.account_id  = lf.account_id
JOIN district d ON d.district_id = a.district_id
GROUP BY d.region
ORDER BY default_rate_pct DESC;

-- 8. Feature summary split by outcome: mean and median for each key variable.
--    This is the table that tells you which features separate defaulters.
SELECT
    variable,
    ROUND(AVG(v) FILTER (WHERE default_flag = 0), 2)  AS mean_no_default,
    ROUND(AVG(v) FILTER (WHERE default_flag = 1), 2)  AS mean_default,
    ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY v)
          FILTER (WHERE default_flag = 0)::NUMERIC, 2) AS median_no_default,
    ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY v)
          FILTER (WHERE default_flag = 1)::NUMERIC, 2) AS median_default
FROM (
    SELECT default_flag, 'age_at_loan' AS variable, age_at_loan::NUMERIC AS v FROM loan_features
    UNION ALL SELECT default_flag, 'history_months', history_months FROM loan_features
    UNION ALL SELECT default_flag, 'avg_balance_6m', avg_balance_6m FROM loan_features
    UNION ALL SELECT default_flag, 'min_balance_6m', min_balance_6m FROM loan_features
    UNION ALL SELECT default_flag, 'sd_balance_6m', sd_balance_6m FROM loan_features
    UNION ALL SELECT default_flag, 'pct_days_negative_6m', pct_days_negative_6m FROM loan_features
    UNION ALL SELECT default_flag, 'monthly_inflow_6m', monthly_inflow_6m FROM loan_features
    UNION ALL SELECT default_flag, 'monthly_outflow_6m', monthly_outflow_6m FROM loan_features
    UNION ALL SELECT default_flag, 'payment_to_inflow_6m', payment_to_inflow_6m FROM loan_features
    UNION ALL SELECT default_flag, 'loan_to_annual_salary', loan_to_annual_salary FROM loan_features
    UNION ALL SELECT default_flag, 'balance_to_loan', balance_to_loan FROM loan_features
    UNION ALL SELECT default_flag, 'n_penalty_interest_12m', n_penalty_interest_12m FROM loan_features
    UNION ALL SELECT default_flag, 'avg_salary_district', avg_salary FROM loan_features
    UNION ALL SELECT default_flag, 'unemployment_rate_95', unemployment_rate_95 FROM loan_features
) x
GROUP BY variable
ORDER BY variable;

-- 9. Default rate by the two distress flags (for the README's "distress" split)
SELECT
    (pct_days_negative_6m > 0)        AS overdrawn_6m,
    (n_penalty_interest_12m > 0)      AS penalty_interest_12m,
    COUNT(*)                          AS loans,
    SUM(default_flag)                 AS defaults,
    ROUND(AVG(default_flag) * 100, 1) AS default_rate_pct
FROM loan_features
GROUP BY 1, 2
ORDER BY 1, 2;

-- 10. Loans per year (sample coverage over time)
SELECT EXTRACT(YEAR FROM loan_date)::INT AS loan_year,
       COUNT(*) AS loans, SUM(default_flag) AS defaults
FROM loan_features
GROUP BY 1
ORDER BY 1;
