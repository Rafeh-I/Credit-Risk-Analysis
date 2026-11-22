-- =====================================================================
-- 04_features.sql
-- One row per loan. EVERY feature uses only information strictly
-- BEFORE the loan date (trans_date < loan_date), so there is no leakage.
--
-- Design notes
--  * Balance features come from a DAILY balance series (last known
--    balance carried forward), so averages are time-weighted, not
--    transaction-weighted.
--  * Windows: 3m = 90 days, 6m = 180 days, 12m = 365 days before the loan.
--    If an account has less history than the window, the feature uses the
--    history that exists; history_months tells the model how much that is.
--  * Not used on purpose: perm_order (standing orders have no date, and
--    include the loan repayment order itself -> leakage) and the 1996
--    district columns (measured after many loans were granted).
--  * Debits = type VYDAJ or VYBER; credits = PRIJEM.
-- =====================================================================

DROP TABLE IF EXISTS loan_features;

CREATE TABLE loan_features AS
WITH loan_base AS (
    SELECT
        l.loan_id, l.account_id, l.loan_date,
        l.amount AS loan_amount, l.duration, l.payments,
        l.status, l.default_flag,
        a.frequency, a.opened_date, a.district_id,
        c.gender, c.birth_date,
        (SELECT MIN(t.trans_date)
           FROM trans t
          WHERE t.account_id = l.account_id
            AND t.trans_date < l.loan_date)                     AS first_trans_date
    FROM loan_labeled l
    JOIN account a ON a.account_id = l.account_id
    JOIN disp    d ON d.account_id = l.account_id AND d.disp_type = 'OWNER'
    JOIN client  c ON c.client_id  = d.client_id
),

-- Daily end-of-day balance for the 365 days before each loan (n = 1 is the day before)
daily AS (
    SELECT lb.loan_id, g.n, b.balance
    FROM loan_base lb
    CROSS JOIN generate_series(1, 365) AS g(n)
    LEFT JOIN LATERAL (
        SELECT t.balance
        FROM trans t
        WHERE t.account_id = lb.account_id
          AND t.trans_date <= lb.loan_date - g.n
        ORDER BY t.trans_date DESC, t.trans_id DESC
        LIMIT 1
    ) b ON TRUE
),

bal AS (
    SELECT
        loan_id,
        AVG(balance)         FILTER (WHERE n <= 90)  AS avg_balance_3m,
        AVG(balance)         FILTER (WHERE n <= 180) AS avg_balance_6m,
        AVG(balance)         FILTER (WHERE n <= 365) AS avg_balance_12m,
        STDDEV_SAMP(balance) FILTER (WHERE n <= 90)  AS sd_balance_3m,
        STDDEV_SAMP(balance) FILTER (WHERE n <= 180) AS sd_balance_6m,
        MIN(balance)         FILTER (WHERE n <= 90)  AS min_balance_3m,
        MIN(balance)         FILTER (WHERE n <= 180) AS min_balance_6m,
        COUNT(*) FILTER (WHERE n <= 180 AND balance < 0)::NUMERIC
            / NULLIF(COUNT(balance) FILTER (WHERE n <= 180), 0) AS pct_days_negative_6m,
        MAX(balance) FILTER (WHERE n = 1)  AS balance_at_grant,
        MAX(balance) FILTER (WHERE n = 90) AS balance_90d_before
    FROM daily
    GROUP BY loan_id
),

-- Cash-flow features from the transactions themselves
flows AS (
    SELECT
        lb.loan_id,
        SUM(t.amount) FILTER (WHERE t.type = 'PRIJEM'
                              AND t.trans_date >= lb.loan_date - 90)  AS inflow_3m,
        SUM(t.amount) FILTER (WHERE t.type IN ('VYDAJ','VYBER')
                              AND t.trans_date >= lb.loan_date - 90)  AS outflow_3m,
        SUM(t.amount) FILTER (WHERE t.type = 'PRIJEM'
                              AND t.trans_date >= lb.loan_date - 180) AS inflow_6m,
        SUM(t.amount) FILTER (WHERE t.type IN ('VYDAJ','VYBER')
                              AND t.trans_date >= lb.loan_date - 180) AS outflow_6m,
        COUNT(*) FILTER (WHERE t.type = 'PRIJEM'
                         AND t.trans_date >= lb.loan_date - 180)      AS n_credits_6m,
        COUNT(*) FILTER (WHERE t.type IN ('VYDAJ','VYBER')
                         AND t.trans_date >= lb.loan_date - 180)      AS n_debits_6m,
        SUM(t.amount) FILTER (WHERE t.operation IN ('VYBER','VYBER KARTOU')
                              AND t.trans_date >= lb.loan_date - 180) AS cash_out_6m,
        COUNT(*) FILTER (WHERE t.k_symbol = 'SANKC. UROK')            AS n_penalty_interest_12m,
        (COUNT(*) FILTER (WHERE t.k_symbol = 'DUCHOD') > 0)::INT      AS has_pension_12m
    FROM loan_base lb
    JOIN trans t
      ON t.account_id = lb.account_id
     AND t.trans_date <  lb.loan_date
     AND t.trans_date >= lb.loan_date - 365
    GROUP BY lb.loan_id
),

feats AS (
    SELECT
        lb.loan_id, lb.account_id, lb.loan_date, lb.status, lb.default_flag,

        -- loan terms
        lb.loan_amount, lb.duration, lb.payments,

        -- applicant and account
        DATE_PART('year', AGE(lb.loan_date, lb.birth_date))::INT       AS age_at_loan,
        lb.gender,
        lb.frequency                                                   AS statement_frequency,
        ROUND((lb.loan_date - lb.opened_date) / 30.4375, 1)            AS account_age_months,
        ROUND((lb.loan_date - lb.first_trans_date) / 30.4375, 1)       AS history_months,
        EXISTS (SELECT 1 FROM card cd
                  JOIN disp d2 ON d2.disp_id = cd.disp_id
                 WHERE d2.account_id = lb.account_id
                   AND cd.issued_date < lb.loan_date)::INT             AS has_card_at_grant,

        -- district (1995 values only)
        dist.avg_salary, dist.unemployment_rate_95, dist.entrepreneurs_per_1000,
        dist.crimes_95, dist.urban_ratio, dist.inhabitants,

        -- balance behaviour
        b.avg_balance_3m, b.avg_balance_6m, b.avg_balance_12m,
        b.sd_balance_3m,  b.sd_balance_6m,
        b.min_balance_3m, b.min_balance_6m,
        b.pct_days_negative_6m,
        b.balance_at_grant,
        b.balance_at_grant - b.balance_90d_before                      AS balance_change_90d,

        -- monthly cash flows (divided by months of history actually available, capped at window)
        COALESCE(f.inflow_3m, 0)  / 3.0                                AS monthly_inflow_3m,
        COALESCE(f.outflow_3m, 0) / 3.0                                AS monthly_outflow_3m,
        COALESCE(f.inflow_6m, 0)
            / LEAST(6.0, (lb.loan_date - lb.first_trans_date) / 30.4375) AS monthly_inflow_6m,
        COALESCE(f.outflow_6m, 0)
            / LEAST(6.0, (lb.loan_date - lb.first_trans_date) / 30.4375) AS monthly_outflow_6m,
        COALESCE(f.n_credits_6m, 0)                                    AS n_credits_6m,
        COALESCE(f.n_debits_6m, 0)                                     AS n_debits_6m,
        COALESCE(f.cash_out_6m, 0)                                     AS cash_out_6m,
        COALESCE(f.n_penalty_interest_12m, 0)                          AS n_penalty_interest_12m,
        COALESCE(f.has_pension_12m, 0)                                 AS has_pension_12m
    FROM loan_base lb
    JOIN district dist ON dist.district_id = lb.district_id
    JOIN bal b         ON b.loan_id = lb.loan_id
    LEFT JOIN flows f  ON f.loan_id = lb.loan_id
)

-- Derived ratios (economically meaningful for credit risk)
SELECT
    feats.*,
    payments / NULLIF(monthly_inflow_6m, 0)                  AS payment_to_inflow_6m,
    loan_amount / NULLIF(avg_salary * 12.0, 0)               AS loan_to_annual_salary,
    monthly_inflow_6m / NULLIF(monthly_outflow_6m, 0)        AS inflow_outflow_ratio_6m,
    cash_out_6m / NULLIF(monthly_outflow_6m * 6.0, 0)        AS cash_share_of_outflow_6m,
    balance_at_grant / NULLIF(loan_amount, 0)                AS balance_to_loan
FROM feats;

ALTER TABLE loan_features ADD PRIMARY KEY (loan_id);

-- =====================================================================
-- Checks (run after the build)
-- =====================================================================

-- 1. Row count, expected 682, and defaults, expected 76
SELECT COUNT(*) AS loans, SUM(default_flag) AS defaults FROM loan_features;

-- 2. Leakage spot-check: both columns must be identical
SELECT lf.loan_id, lf.balance_at_grant,
       (SELECT t.balance FROM trans t
         WHERE t.account_id = lf.account_id AND t.trans_date < lf.loan_date
         ORDER BY t.trans_date DESC, t.trans_id DESC LIMIT 1) AS check_balance
FROM loan_features lf
ORDER BY lf.loan_id
LIMIT 5;

-- 3. Missing values per key column (ideally all 0)
SELECT
    COUNT(*) FILTER (WHERE age_at_loan IS NULL)            AS null_age,
    COUNT(*) FILTER (WHERE avg_balance_6m IS NULL)         AS null_avg_bal_6m,
    COUNT(*) FILTER (WHERE sd_balance_6m IS NULL)          AS null_sd_bal_6m,
    COUNT(*) FILTER (WHERE payment_to_inflow_6m IS NULL)   AS null_pay_to_inflow,
    COUNT(*) FILTER (WHERE unemployment_rate_95 IS NULL)   AS null_unemp
FROM loan_features;

-- 4. Plausibility: applicant ages
SELECT MIN(age_at_loan) AS min_age, MAX(age_at_loan) AS max_age,
       ROUND(AVG(age_at_loan), 1) AS mean_age
FROM loan_features;

-- 5. First signal: default rate by whether the account was ever overdrawn
SELECT (pct_days_negative_6m > 0) AS ever_negative_6m,
       COUNT(*) AS loans, ROUND(AVG(default_flag), 3) AS default_rate
FROM loan_features
GROUP BY 1;