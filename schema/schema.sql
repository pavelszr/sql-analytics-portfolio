-- =============================================================================
-- schema.sql  -  Fintech / retail-banking analytics schema
-- =============================================================================
-- Portable ANSI SQL DDL. Verified to run on DuckDB, SQLite, and PostgreSQL.
--
-- Portability notes:
--   * Types used (INTEGER, BIGINT, VARCHAR, DATE, TIMESTAMP, DECIMAL, BOOLEAN)
--     are accepted by DuckDB / Postgres / SQLite. SQLite stores them with
--     dynamic typing but the declarations are honored by the other engines.
--   * BOOLEAN: SQLite has no native boolean; it stores 0/1. Seed data uses
--     0/1 so it is portable everywhere.
--   * SQL Server (T-SQL) differences:
--       - Use DATETIME2 instead of TIMESTAMP.
--       - Use BIT instead of BOOLEAN (values 0/1).
--       - Use NVARCHAR instead of VARCHAR for unicode text.
--       - DECIMAL(p,s) is identical.
--       - "-- " line comments and standard FK syntax are identical.
-- =============================================================================

-- Drop in dependency order so the script is re-runnable.
DROP TABLE IF EXISTS loan_payments;
DROP TABLE IF EXISTS loans;
DROP TABLE IF EXISTS cards;
DROP TABLE IF EXISTS transactions;
DROP TABLE IF EXISTS accounts;
DROP TABLE IF EXISTS customers;

-- -----------------------------------------------------------------------------
-- customers : one row per banking customer (the person / household head).
-- -----------------------------------------------------------------------------
CREATE TABLE customers (
    customer_id     INTEGER       NOT NULL,           -- surrogate key
    first_name      VARCHAR(50)   NOT NULL,
    last_name       VARCHAR(50)   NOT NULL,
    email           VARCHAR(120)  NOT NULL,
    date_of_birth   DATE          NOT NULL,
    signup_date     DATE          NOT NULL,           -- first relationship date (cohort anchor)
    home_state      VARCHAR(2)    NOT NULL,           -- US 2-letter state code
    risk_segment    VARCHAR(10)   NOT NULL,           -- 'low' | 'medium' | 'high' (credit risk band)
    CONSTRAINT pk_customers PRIMARY KEY (customer_id)
);

-- -----------------------------------------------------------------------------
-- accounts : deposit products held by a customer. A customer can hold many.
-- -----------------------------------------------------------------------------
CREATE TABLE accounts (
    account_id      INTEGER       NOT NULL,
    customer_id     INTEGER       NOT NULL,
    account_type    VARCHAR(15)   NOT NULL,           -- 'checking' | 'savings' | 'money_market'
    opened_date     DATE          NOT NULL,
    closed_date     DATE          NULL,               -- NULL while account is open
    status          VARCHAR(10)   NOT NULL,           -- 'active' | 'dormant' | 'closed'
    CONSTRAINT pk_accounts PRIMARY KEY (account_id),
    CONSTRAINT fk_accounts_customer
        FOREIGN KEY (customer_id) REFERENCES customers (customer_id)
);

-- -----------------------------------------------------------------------------
-- transactions : money movement on a deposit account.
--   amount > 0  => credit (deposit / inflow)
--   amount < 0  => debit  (withdrawal / purchase / outflow)
-- -----------------------------------------------------------------------------
CREATE TABLE transactions (
    transaction_id   BIGINT        NOT NULL,
    account_id       INTEGER       NOT NULL,
    txn_date         DATE          NOT NULL,          -- posting date
    txn_ts           TIMESTAMP     NOT NULL,          -- full posting timestamp
    amount           DECIMAL(12,2) NOT NULL,          -- signed: + credit, - debit
    txn_type         VARCHAR(20)   NOT NULL,          -- 'deposit'|'withdrawal'|'purchase'|'transfer'|'fee'|'interest'
    merchant_category VARCHAR(30)  NULL,              -- NULL for non-purchase txns
    channel          VARCHAR(15)   NOT NULL,          -- 'atm'|'pos'|'online'|'branch'|'ach'
    CONSTRAINT pk_transactions PRIMARY KEY (transaction_id),
    CONSTRAINT fk_transactions_account
        FOREIGN KEY (account_id) REFERENCES accounts (account_id)
);

-- -----------------------------------------------------------------------------
-- cards : payment cards linked to a deposit account.
-- -----------------------------------------------------------------------------
CREATE TABLE cards (
    card_id         INTEGER       NOT NULL,
    account_id      INTEGER       NOT NULL,
    card_type       VARCHAR(10)   NOT NULL,           -- 'debit' | 'credit'
    issued_date     DATE          NOT NULL,
    expiry_date     DATE          NOT NULL,
    credit_limit    DECIMAL(12,2) NULL,               -- NULL for debit cards
    is_active       INTEGER       NOT NULL,           -- 1 = active, 0 = blocked/expired (BIT in T-SQL)
    CONSTRAINT pk_cards PRIMARY KEY (card_id),
    CONSTRAINT fk_cards_account
        FOREIGN KEY (account_id) REFERENCES accounts (account_id)
);

-- -----------------------------------------------------------------------------
-- loans : an originated loan held by a customer.
-- -----------------------------------------------------------------------------
CREATE TABLE loans (
    loan_id          INTEGER       NOT NULL,
    customer_id      INTEGER       NOT NULL,
    loan_type        VARCHAR(15)   NOT NULL,          -- 'personal'|'auto'|'mortgage'|'student'
    origination_date DATE          NOT NULL,          -- vintage anchor
    principal_amount DECIMAL(12,2) NOT NULL,          -- original disbursed amount
    interest_rate    DECIMAL(5,4)  NOT NULL,          -- annual rate, e.g. 0.0650 = 6.50%
    term_months      INTEGER       NOT NULL,
    monthly_payment  DECIMAL(12,2) NOT NULL,          -- scheduled installment
    status           VARCHAR(12)   NOT NULL,          -- 'current'|'delinquent'|'paid_off'|'default'|'charged_off'
    CONSTRAINT pk_loans PRIMARY KEY (loan_id),
    CONSTRAINT fk_loans_customer
        FOREIGN KEY (customer_id) REFERENCES customers (customer_id)
);

-- -----------------------------------------------------------------------------
-- loan_payments : one row per scheduled installment for a loan.
--   amount_due   = scheduled installment for the period
--   amount_paid  = what was actually received (0 if missed)
--   paid_date    = NULL if not yet / never paid
-- Days-past-due is derived as (paid_date - due_date), or (as_of - due_date)
-- when still unpaid.
-- -----------------------------------------------------------------------------
CREATE TABLE loan_payments (
    payment_id       BIGINT        NOT NULL,
    loan_id          INTEGER       NOT NULL,
    due_date         DATE          NOT NULL,          -- scheduled due date
    paid_date        DATE          NULL,              -- actual payment date (NULL = unpaid)
    amount_due       DECIMAL(12,2) NOT NULL,
    amount_paid      DECIMAL(12,2) NOT NULL,          -- 0.00 when missed
    installment_no   INTEGER       NOT NULL,          -- 1..term_months
    CONSTRAINT pk_loan_payments PRIMARY KEY (payment_id),
    CONSTRAINT fk_loan_payments_loan
        FOREIGN KEY (loan_id) REFERENCES loans (loan_id)
);

-- -----------------------------------------------------------------------------
-- Helpful secondary indexes for the analytical queries (optional but realistic).
-- SQLite/DuckDB/Postgres all accept this CREATE INDEX syntax.
-- -----------------------------------------------------------------------------
CREATE INDEX ix_accounts_customer    ON accounts (customer_id);
CREATE INDEX ix_transactions_account ON transactions (account_id);
CREATE INDEX ix_transactions_date    ON transactions (txn_date);
CREATE INDEX ix_cards_account        ON cards (account_id);
CREATE INDEX ix_loans_customer       ON loans (customer_id);
CREATE INDEX ix_loan_payments_loan   ON loan_payments (loan_id);
CREATE INDEX ix_loan_payments_due    ON loan_payments (due_date);
