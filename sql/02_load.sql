-- =====================================================================
-- 02_load.sql
-- Load Berka CSVs via all-TEXT staging tables, then cast into the
-- typed production tables created in 01_schema.sql.
--
-- Requires: files in C:/berka_data (semicolon-delimited).
-- COPY reads from the SERVER's filesystem. If you get a permission
-- error, use psql's client-side \copy instead (same options).
-- Re-runnable only after re-running 01_schema.sql.
-- =====================================================================

BEGIN;

-- 1. Staging (everything TEXT so a dirty row can't crash the load)
CREATE TEMP TABLE stg_district (
    a1 TEXT, a2 TEXT, a3 TEXT, a4 TEXT, a5 TEXT, a6 TEXT, a7 TEXT, a8 TEXT,
    a9 TEXT, a10 TEXT, a11 TEXT, a12 TEXT, a13 TEXT, a14 TEXT, a15 TEXT, a16 TEXT
);
CREATE TEMP TABLE stg_client  (client_id TEXT, birth_number TEXT, district_id TEXT);
CREATE TEMP TABLE stg_account (account_id TEXT, district_id TEXT, frequency TEXT, date TEXT);
CREATE TEMP TABLE stg_disp    (disp_id TEXT, client_id TEXT, account_id TEXT, type TEXT);
CREATE TEMP TABLE stg_order   (order_id TEXT, account_id TEXT, bank_to TEXT, account_to TEXT, amount TEXT, k_symbol TEXT);
CREATE TEMP TABLE stg_trans   (trans_id TEXT, account_id TEXT, date TEXT, type TEXT, operation TEXT,
                               amount TEXT, balance TEXT, k_symbol TEXT, bank TEXT, account_to TEXT);
CREATE TEMP TABLE stg_loan    (loan_id TEXT, account_id TEXT, date TEXT, amount TEXT, duration TEXT,
                               payments TEXT, status TEXT);
CREATE TEMP TABLE stg_card    (card_id TEXT, disp_id TEXT, type TEXT, issued TEXT);

-- 2. Bulk load
COPY stg_district FROM 'C:/berka_data/district.csv' WITH (FORMAT csv, HEADER true, DELIMITER ';', NULL '?');
COPY stg_client   FROM 'C:/berka_data/client.csv'   WITH (FORMAT csv, HEADER true, DELIMITER ';', NULL '?');
COPY stg_account  FROM 'C:/berka_data/account.csv'  WITH (FORMAT csv, HEADER true, DELIMITER ';', NULL '?');
COPY stg_disp     FROM 'C:/berka_data/disp.csv'     WITH (FORMAT csv, HEADER true, DELIMITER ';', NULL '?');
COPY stg_order    FROM 'C:/berka_data/order.csv'    WITH (FORMAT csv, HEADER true, DELIMITER ';', NULL '?');
COPY stg_trans    FROM 'C:/berka_data/trans.csv'    WITH (FORMAT csv, HEADER true, DELIMITER ';', NULL '?');
COPY stg_loan     FROM 'C:/berka_data/loan.csv'     WITH (FORMAT csv, HEADER true, DELIMITER ';', NULL '?');
COPY stg_card     FROM 'C:/berka_data/card.csv'     WITH (FORMAT csv, HEADER true, DELIMITER ';', NULL '?');

-- 3. Cast + clean into production tables (parents before children)

INSERT INTO district
SELECT a1::INTEGER, TRIM(a2), TRIM(a3), a4::INTEGER, a5::INTEGER, a6::INTEGER, a7::INTEGER,
       a8::INTEGER, a9::INTEGER, a10::NUMERIC, a11::INTEGER,
       NULLIF(TRIM(a12), '')::NUMERIC, NULLIF(TRIM(a13), '')::NUMERIC,
       a14::INTEGER, NULLIF(TRIM(a15), '')::INTEGER, NULLIF(TRIM(a16), '')::INTEGER
FROM stg_district;

-- birth_number = YYMMDD; the month has +50 added for women
INSERT INTO client
SELECT client_id::INTEGER,
       make_date(
           1900 + SUBSTR(birth_number, 1, 2)::INT,
           SUBSTR(birth_number, 3, 2)::INT - CASE WHEN SUBSTR(birth_number, 3, 2)::INT > 50 THEN 50 ELSE 0 END,
           SUBSTR(birth_number, 5, 2)::INT
       ),
       CASE WHEN SUBSTR(birth_number, 3, 2)::INT > 50 THEN 'F' ELSE 'M' END,
       district_id::INTEGER
FROM stg_client;

INSERT INTO account
SELECT account_id::INTEGER,
       district_id::INTEGER,
       CASE TRIM(frequency)
            WHEN 'POPLATEK MESICNE'   THEN 'monthly'
            WHEN 'POPLATEK TYDNE'     THEN 'weekly'
            WHEN 'POPLATEK PO OBRATU' THEN 'after_transaction'
       END,
       TO_DATE('19' || TRIM(date), 'YYYYMMDD')
FROM stg_account;

INSERT INTO disp
SELECT disp_id::INTEGER, client_id::INTEGER, account_id::INTEGER, TRIM(type)
FROM stg_disp;

INSERT INTO perm_order
SELECT order_id::INTEGER, account_id::INTEGER, NULLIF(TRIM(bank_to), ''),
       NULLIF(TRIM(account_to), '')::BIGINT, amount::NUMERIC, NULLIF(TRIM(k_symbol), '')
FROM stg_order;

-- issued looks like '930107 00:00:00' -> keep the first 6 chars
INSERT INTO card
SELECT card_id::INTEGER, disp_id::INTEGER, TRIM(type),
       TO_DATE('19' || LEFT(TRIM(issued), 6), 'YYYYMMDD')
FROM stg_card;

INSERT INTO loan
SELECT loan_id::INTEGER, account_id::INTEGER, TO_DATE('19' || TRIM(date), 'YYYYMMDD'),
       amount::NUMERIC, duration::INTEGER, payments::NUMERIC, TRIM(status)
FROM stg_loan;

INSERT INTO trans
SELECT trans_id::INTEGER, account_id::INTEGER, TO_DATE('19' || TRIM(date), 'YYYYMMDD'),
       NULLIF(TRIM(type), ''), NULLIF(TRIM(operation), ''), amount::NUMERIC, balance::NUMERIC,
       NULLIF(TRIM(k_symbol), ''), NULLIF(TRIM(bank), ''), NULLIF(TRIM(account_to), '')::BIGINT
FROM stg_trans;

COMMIT;

ANALYZE;  -- refresh planner statistics after the bulk load