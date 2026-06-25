-- =============================================================================
-- 02  3-month moving average of customer spend
-- -----------------------------------------------------------------------------
-- Business question:
--   How is each customer's monthly debit spend trending once we smooth out
--   month-to-month noise with a trailing 3-month moving average?
--
-- Approach:
--   1) Aggregate signed debits (amount < 0) to absolute monthly spend per
--      customer via the account -> customer join.
--   2) Apply a trailing 3-row moving average window
--      (ROWS BETWEEN 2 PRECEDING AND CURRENT ROW). Early months average over
--      fewer rows, which is the desired "warm-up" behavior.
--
-- Technique: window function - moving average
--   AVG(...) OVER (PARTITION BY ... ORDER BY ... ROWS BETWEEN 2 PRECEDING ...)
--
-- Dialect notes:
--   * DATE_TRUNC('month', d): Postgres/DuckDB. SQLite -> strftime('%Y-%m-01', d).
--     T-SQL -> DATEFROMPARTS(YEAR(d), MONTH(d), 1).
-- =============================================================================

WITH monthly_spend AS (
    SELECT
        a.customer_id,
        DATE_TRUNC('month', t.txn_date)          AS spend_month,
        SUM(ABS(t.amount))                       AS total_spend
    FROM transactions AS t
    JOIN accounts     AS a ON a.account_id = t.account_id
    WHERE t.amount < 0                            -- debits only (outflows)
    GROUP BY a.customer_id, DATE_TRUNC('month', t.txn_date)
)
SELECT
    customer_id,
    spend_month,
    total_spend,
    ROUND(
        AVG(total_spend) OVER (
            PARTITION BY customer_id
            ORDER BY spend_month
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ), 2
    ) AS spend_3mo_moving_avg
FROM monthly_spend
ORDER BY customer_id, spend_month;
