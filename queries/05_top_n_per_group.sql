-- =============================================================================
-- 05  Top-N per group: top 3 merchant categories of spend per customer
-- -----------------------------------------------------------------------------
-- Business question:
--   For each customer, what are their top 3 spending categories by dollar
--   amount? This drives personalized offers and category-level insights.
--
-- Approach:
--   Aggregate spend by (customer, merchant_category), assign a per-customer
--   ROW_NUMBER ordered by spend descending, then keep ranks <= 3 in the outer
--   query. ROW_NUMBER (not RANK) guarantees exactly N rows even with ties.
--
-- Technique: top-N per group via windowed ROW_NUMBER
--   (The classic alternative is a correlated subquery with a COUNT(*) < N
--    filter; the window version is the modern, more efficient pattern.)
--
-- Dialect notes:
--   * Works on DuckDB / Postgres / SQLite 3.25+ / T-SQL unchanged.
--   * T-SQL also offers CROSS APPLY (SELECT TOP 3 ...) as an idiomatic variant.
-- =============================================================================

WITH category_spend AS (
    SELECT
        a.customer_id,
        t.merchant_category,
        SUM(ABS(t.amount)) AS category_spend
    FROM transactions AS t
    JOIN accounts     AS a ON a.account_id = t.account_id
    WHERE t.amount < 0
      AND t.merchant_category IS NOT NULL
    GROUP BY a.customer_id, t.merchant_category
),
ranked AS (
    SELECT
        customer_id,
        merchant_category,
        category_spend,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id
            ORDER BY category_spend DESC, merchant_category
        ) AS spend_rank
    FROM category_spend
)
SELECT
    customer_id,
    spend_rank,
    merchant_category,
    category_spend
FROM ranked
WHERE spend_rank <= 3
ORDER BY customer_id, spend_rank;
