-- =============================================================================
-- 08  Product-adoption funnel / conversion analysis
-- -----------------------------------------------------------------------------
-- Business question:
--   How far do customers progress down the product-adoption funnel
--   (signed up -> opened an account -> transacted -> took a card -> took a loan),
--   and where is the biggest drop-off?
--
-- Approach:
--   Build one boolean flag per customer for each funnel stage (using EXISTS so
--   we count distinct customers, never inflate by row fan-out). Stages are
--   strictly nested: each downstream stage implies the upstream ones. Then a
--   single aggregation counts customers at each stage and computes both the
--   overall conversion and the step-to-step conversion.
--
-- Technique: funnel / conversion analysis (staged EXISTS flags + step ratios)
--
-- Dialect notes:
--   * SUM(CASE WHEN flag THEN 1 ELSE 0 END) is portable everywhere.
--   * LAG over the ordered stage list gives the previous stage count for the
--     step conversion rate.
-- =============================================================================

WITH customer_stages AS (
    SELECT
        c.customer_id,
        1 AS reached_signup,
        CASE WHEN EXISTS (SELECT 1 FROM accounts a
                          WHERE a.customer_id = c.customer_id)
             THEN 1 ELSE 0 END AS reached_account,
        CASE WHEN EXISTS (SELECT 1 FROM accounts a
                          JOIN transactions t ON t.account_id = a.account_id
                          WHERE a.customer_id = c.customer_id)
             THEN 1 ELSE 0 END AS reached_transaction,
        CASE WHEN EXISTS (SELECT 1 FROM accounts a
                          JOIN cards ca ON ca.account_id = a.account_id
                          WHERE a.customer_id = c.customer_id)
             THEN 1 ELSE 0 END AS reached_card,
        CASE WHEN EXISTS (SELECT 1 FROM loans l
                          WHERE l.customer_id = c.customer_id)
             THEN 1 ELSE 0 END AS reached_loan
    FROM customers AS c
),
funnel AS (
    SELECT 1 AS stage_no, 'Signed up'        AS stage, SUM(reached_signup)      AS customers FROM customer_stages
    UNION ALL
    SELECT 2,             'Opened account',              SUM(reached_account)      FROM customer_stages
    UNION ALL
    SELECT 3,             'Transacted',                  SUM(reached_transaction)  FROM customer_stages
    UNION ALL
    SELECT 4,             'Holds a card',                SUM(reached_card)         FROM customer_stages
    UNION ALL
    SELECT 5,             'Took a loan',                 SUM(reached_loan)         FROM customer_stages
)
SELECT
    stage_no,
    stage,
    customers,
    ROUND(100.0 * customers
          / FIRST_VALUE(customers) OVER (ORDER BY stage_no), 1)         AS pct_of_top,
    ROUND(100.0 * customers
          / NULLIF(LAG(customers) OVER (ORDER BY stage_no), 0), 1)      AS step_conversion_pct
FROM funnel
ORDER BY stage_no;
