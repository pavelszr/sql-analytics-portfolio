-- =============================================================================
-- 10  Churn detection (inactivity-based) with inter-transaction gaps
-- -----------------------------------------------------------------------------
-- Business question:
--   Which customers have churned, defined as no transaction for more than 90
--   days as of the latest data date? And among active customers, who is showing
--   warning signs (a recent gap longer than their usual cadence)?
--
-- Approach:
--   1) Per customer: last transaction date and lifetime transaction count.
--   2) Compare the gap between the last activity and the dataset's max date to a
--      90-day churn threshold.
--   3) Use LAG to measure each customer's typical days-between-transactions
--      (average gap) so we can flag those whose silence exceeds their norm.
--
-- Technique: churn detection (inactivity threshold + LAG inter-event gaps)
--
-- Dialect notes:
--   * Date subtraction returns an integer day count in DuckDB/Postgres.
--     T-SQL: DATEDIFF(DAY, last_txn, as_of_date).
-- =============================================================================

WITH bounds AS (
    SELECT MAX(txn_date) AS as_of_date FROM transactions
),
txn_with_gap AS (                      -- gap (in days) to each customer's prior txn
    SELECT
        a.customer_id,
        t.txn_date,
        CAST(t.txn_date
             - LAG(t.txn_date) OVER (PARTITION BY a.customer_id ORDER BY t.txn_date)
             AS INTEGER) AS days_since_prev_txn
    FROM transactions AS t
    JOIN accounts     AS a ON a.account_id = t.account_id
),
customer_activity AS (
    SELECT
        customer_id,
        MAX(txn_date)                 AS last_txn_date,
        COUNT(*)                      AS txn_count,
        AVG(days_since_prev_txn)      AS avg_gap_days   -- NULLs (first txn) ignored by AVG
    FROM txn_with_gap
    GROUP BY customer_id
)
SELECT
    ca.customer_id,
    c.first_name,
    c.last_name,
    c.signup_date,
    ca.last_txn_date,
    ca.txn_count,
    ROUND(ca.avg_gap_days, 1)                                       AS avg_gap_days,
    CAST((SELECT as_of_date FROM bounds) - ca.last_txn_date AS INTEGER) AS days_inactive,
    CASE
        WHEN CAST((SELECT as_of_date FROM bounds) - ca.last_txn_date AS INTEGER) > 90
            THEN 'Churned'
        WHEN CAST((SELECT as_of_date FROM bounds) - ca.last_txn_date AS INTEGER)
             > 2 * ca.avg_gap_days
            THEN 'At Risk'
        ELSE 'Active'
    END AS churn_status
FROM customer_activity AS ca
JOIN customers         AS c ON c.customer_id = ca.customer_id
ORDER BY days_inactive DESC;
