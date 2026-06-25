-- =============================================================================
-- 04  Ranking customers by spend (RANK / DENSE_RANK / ROW_NUMBER / NTILE)
-- -----------------------------------------------------------------------------
-- Business question:
--   Who are our highest-spending customers, how do they rank, and which decile
--   of the customer base does each one fall into?
--
-- Approach:
--   Aggregate lifetime debit spend per customer, then apply four ranking window
--   functions side by side to contrast their semantics:
--     ROW_NUMBER - unique sequential, arbitrary tiebreak
--     RANK       - ties share a rank, leaves gaps
--     DENSE_RANK - ties share a rank, no gaps
--     NTILE(10)  - splits the population into 10 equal-size deciles
--
-- Technique: window functions - RANK / DENSE_RANK / ROW_NUMBER / NTILE
--
-- Dialect notes:
--   * All four are ANSI and supported by DuckDB / Postgres / SQLite 3.25+ / T-SQL.
-- =============================================================================

WITH customer_spend AS (
    SELECT
        a.customer_id,
        SUM(ABS(t.amount)) AS total_spend,
        COUNT(*)           AS txn_count
    FROM transactions AS t
    JOIN accounts     AS a ON a.account_id = t.account_id
    WHERE t.amount < 0
    GROUP BY a.customer_id
)
SELECT
    cs.customer_id,
    c.first_name,
    c.last_name,
    cs.total_spend,
    cs.txn_count,
    ROW_NUMBER() OVER (ORDER BY cs.total_spend DESC) AS spend_row_number,
    RANK()       OVER (ORDER BY cs.total_spend DESC) AS spend_rank,
    DENSE_RANK() OVER (ORDER BY cs.total_spend DESC) AS spend_dense_rank,
    NTILE(10)    OVER (ORDER BY cs.total_spend DESC) AS spend_decile
FROM customer_spend AS cs
JOIN customers       AS c ON c.customer_id = cs.customer_id
ORDER BY cs.total_spend DESC;
