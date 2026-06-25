-- =============================================================================
-- 07  RFM customer segmentation
-- -----------------------------------------------------------------------------
-- Business question:
--   Which customers are our best, which are slipping away, and which are new?
--   Score every customer on Recency, Frequency, and Monetary value and map the
--   scores to actionable marketing segments.
--
-- Approach:
--   1) Per customer compute:
--        recency_days = days since last transaction (relative to the dataset's
--                       max date so results are reproducible),
--        frequency    = number of transactions,
--        monetary     = total absolute spend.
--   2) NTILE(5) turns each metric into a 1-5 score. Recency is reversed
--      (more recent = higher score) by ordering recency_days ascending.
--   3) Concatenate to an R-F-M code and bucket into named segments.
--
-- Technique: RFM segmentation (NTILE quintiles + CASE bucketing)
--
-- Dialect notes:
--   * Reference date uses MAX(txn_date) so the query is deterministic; in
--     production substitute CURRENT_DATE.
--   * String concat: || is ANSI (DuckDB/Postgres/SQLite). T-SQL uses + or
--     CONCAT(); CAST scores to varchar first there.
-- =============================================================================

WITH bounds AS (
    SELECT MAX(txn_date) AS as_of_date FROM transactions
),
rfm_base AS (
    SELECT
        a.customer_id,
        CAST((SELECT as_of_date FROM bounds) - MAX(t.txn_date) AS INTEGER) AS recency_days,
        COUNT(*)            AS frequency,
        SUM(ABS(t.amount))  AS monetary
    FROM transactions AS t
    JOIN accounts     AS a ON a.account_id = t.account_id
    GROUP BY a.customer_id
),
rfm_scored AS (
    SELECT
        customer_id,
        recency_days,
        frequency,
        monetary,
        -- recency: smaller gap => higher score, so order ascending
        NTILE(5) OVER (ORDER BY recency_days ASC)  AS r_score,
        NTILE(5) OVER (ORDER BY frequency ASC)     AS f_score,
        NTILE(5) OVER (ORDER BY monetary  ASC)     AS m_score
    FROM rfm_base
)
SELECT
    customer_id,
    recency_days,
    frequency,
    monetary,
    r_score,
    f_score,
    m_score,
    (r_score || f_score || m_score) AS rfm_cell,
    CASE
        WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
        WHEN r_score >= 4 AND f_score >= 3                  THEN 'Loyal'
        WHEN r_score >= 4 AND f_score <= 2                  THEN 'New / Promising'
        WHEN r_score = 3                                    THEN 'Needs Attention'
        WHEN r_score <= 2 AND f_score >= 4                  THEN 'At Risk (was valuable)'
        WHEN r_score <= 2 AND m_score >= 4                  THEN 'Cannot Lose Them'
        ELSE 'Hibernating / Lost'
    END AS rfm_segment
FROM rfm_scored
ORDER BY r_score DESC, f_score DESC, m_score DESC;
