-- =============================================================================
-- 01  Running account balance (cumulative running total)
-- -----------------------------------------------------------------------------
-- Business question:
--   For a deposit account, what was the balance after every transaction, so we
--   can plot the balance curve and spot overdrafts or large swings?
--
-- Approach:
--   Order the signed transaction amounts chronologically per account and take a
--   cumulative SUM with a window frame from the first row to the current row.
--   A deterministic tiebreaker (transaction_id) makes the running total stable
--   when two transactions share a timestamp.
--
-- Technique: window function - running total
--   SUM(...) OVER (PARTITION BY ... ORDER BY ... ROWS UNBOUNDED PRECEDING)
--
-- Dialect notes:
--   * ANSI / DuckDB / Postgres / SQLite: as written.
--   * T-SQL: identical; SQL Server supports ROWS UNBOUNDED PRECEDING since 2012.
-- =============================================================================

SELECT
    t.account_id,
    t.txn_date,
    t.txn_ts,
    t.txn_type,
    t.amount,
    SUM(t.amount) OVER (
        PARTITION BY t.account_id
        ORDER BY t.txn_ts, t.transaction_id
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS running_balance
FROM transactions AS t
ORDER BY t.account_id, t.txn_ts, t.transaction_id;
