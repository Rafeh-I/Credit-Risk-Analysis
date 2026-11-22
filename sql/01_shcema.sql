-- =====================================================================
-- 01_schema.sql
-- Berka bank dataset: production schema (re-runnable)
-- Column names are translated to readable English; Czech codes are
-- translated during load (02_load.sql) where it helps analysis.
-- =====================================================================

DROP TABLE IF EXISTS trans      CASCADE;
DROP TABLE IF EXISTS loan       CASCADE;
DROP TABLE IF EXISTS card       CASCADE;
DROP TABLE IF EXISTS perm_order CASCADE;
DROP TABLE IF EXISTS disp       CASCADE;
DROP TABLE IF EXISTS account    CASCADE;
DROP TABLE IF EXISTS client     CASCADE;
DROP TABLE IF EXISTS district   CASCADE;

CREATE TABLE district (
    district_id              INTEGER PRIMARY KEY,
    district_name            TEXT NOT NULL,
    region                   TEXT NOT NULL,
    inhabitants              INTEGER,
    n_municipalities_lt_500  INTEGER,
    n_municipalities_500_1999 INTEGER,
    n_municipalities_2000_9999 INTEGER,
    n_municipalities_ge_10000 INTEGER,
    n_cities                 INTEGER,
    urban_ratio              NUMERIC(5,1),
    avg_salary               INTEGER,
    unemployment_rate_95     NUMERIC(4,2),   -- missing for one district
    unemployment_rate_96     NUMERIC(4,2),
    entrepreneurs_per_1000   INTEGER,
    crimes_95                INTEGER,        -- missing for one district
    crimes_96                INTEGER
);

CREATE TABLE client (
    client_id    INTEGER PRIMARY KEY,
    birth_date   DATE    NOT NULL,
    gender       CHAR(1) NOT NULL CHECK (gender IN ('M','F')),
    district_id  INTEGER NOT NULL REFERENCES district(district_id)
);

CREATE TABLE account (
    account_id   INTEGER PRIMARY KEY,
    district_id  INTEGER NOT NULL REFERENCES district(district_id),
    frequency    TEXT    NOT NULL CHECK (frequency IN ('monthly','weekly','after_transaction')),
    opened_date  DATE    NOT NULL
);

CREATE TABLE disp (
    disp_id      INTEGER PRIMARY KEY,
    client_id    INTEGER NOT NULL REFERENCES client(client_id),
    account_id   INTEGER NOT NULL REFERENCES account(account_id),
    disp_type    TEXT    NOT NULL CHECK (disp_type IN ('OWNER','DISPONENT'))
);

CREATE TABLE perm_order (
    order_id     INTEGER PRIMARY KEY,
    account_id   INTEGER NOT NULL REFERENCES account(account_id),
    bank_to      TEXT,
    account_to   BIGINT,
    amount       NUMERIC(12,2) NOT NULL,
    k_symbol     TEXT           -- NULL when blank
);

CREATE TABLE card (
    card_id      INTEGER PRIMARY KEY,
    disp_id      INTEGER NOT NULL REFERENCES disp(disp_id),
    card_type    TEXT    NOT NULL,
    issued_date  DATE    NOT NULL
);

CREATE TABLE loan (
    loan_id      INTEGER PRIMARY KEY,
    account_id   INTEGER NOT NULL UNIQUE REFERENCES account(account_id),
    loan_date    DATE    NOT NULL,
    amount       NUMERIC(12,2) NOT NULL,
    duration     INTEGER NOT NULL,          -- months
    payments     NUMERIC(12,2) NOT NULL,    -- monthly instalment
    status       CHAR(1) NOT NULL CHECK (status IN ('A','B','C','D'))
    -- A = finished, paid | B = finished, NOT paid
    -- C = running, OK    | D = running, in debt
);

CREATE TABLE trans (
    trans_id     INTEGER PRIMARY KEY,
    account_id   INTEGER NOT NULL REFERENCES account(account_id),
    trans_date   DATE    NOT NULL,
    type         TEXT,       -- PRIJEM = credit, VYDAJ = debit, VYBER = cash withdrawal
    operation    TEXT,       -- NULL when blank
    amount       NUMERIC(12,2) NOT NULL,
    balance      NUMERIC(12,2) NOT NULL,
    k_symbol     TEXT,       -- NULL when blank
    bank         TEXT,       -- NULL when blank
    account_to   BIGINT
);

-- Indexes: the point-in-time feature build filters trans by account + date
CREATE INDEX idx_trans_account_date ON trans (account_id, trans_date);
CREATE INDEX idx_disp_account       ON disp  (account_id);
CREATE INDEX idx_disp_client        ON disp  (client_id);