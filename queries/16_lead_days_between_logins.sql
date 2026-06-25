-- =============================================================================
-- 16  LEAD: expected days to a customer's NEXT transaction
-- -----------------------------------------------------------------------------
-- Business question:
--   How long does each customer typically wait between transactions, and what
--   was the single longest dormant gap inside their active life? This feeds
--   engagement scoring and "we miss you" re-activation triggers.
--
-- Approach:
--   LEAD looks forward to each customer's next transaction date; the difference
--   is the forward gap. We then aggregate per customer to get the average and
--   maximum forward gap. (LEAD is the forward-looking twin of query 10's LAG.)
--
-- Technique: window function - LEAD (look-ahead inter-event gaps)
--
-- Dialect notes:
--   * LEAD(col, 1) OVER (PARTITION BY ... ORDER BY ...): ANSI, all four engines
--     (SQLite 3.25+). T-SQL identical.
--   * Date subtraction -> integer days (DuckDB/Postgres); T-SQL DATEDIFF(DAY,...).
-- =============================================================================

WITH txn_seq AS (
    SELECT
        a.customer_id,
        t.txn_date,
        LEAD(t.txn_date) OVER (
            PARTITION BY a.customer_id
            ORDER BY t.txn_date, t.transaction_id
        ) AS next_txn_date
    FROM transactions AS t
    JOIN accounts     AS a ON a.account_id = t.account_id
),
gaps AS (
    SELECT
        customer_id,
        txn_date,
        next_txn_date,
        CAST(next_txn_date - txn_date AS INTEGER) AS days_to_next_txn
    FROM txn_seq
    WHERE next_txn_date IS NOT NULL          -- drop the final txn (no "next")
)
SELECT
    g.customer_id,
    c.first_name,
    c.last_name,
    COUNT(*)                          AS gaps_observed,
    ROUND(AVG(days_to_next_txn), 1)   AS avg_days_between_txns,
    MAX(days_to_next_txn)             AS longest_gap_days
FROM gaps      AS g
JOIN customers AS c ON c.customer_id = g.customer_id
GROUP BY g.customer_id, c.first_name, c.last_name
ORDER BY longest_gap_days DESC, avg_days_between_txns DESC;
