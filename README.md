# Fintech SQL Analytics Portfolio

A focused portfolio of **senior-level analytical SQL** built on a realistic
retail-banking dataset (customers, accounts, transactions, cards, loans, and
loan payments). Every query answers a concrete business question and showcases a
specific technique — window functions, cohort retention, RFM segmentation,
funnel analysis, gaps-and-islands, churn detection, loan-portfolio credit
metrics, pivots, recursive CTEs, and percentiles.

**Author:** Pavel Salazar — ex-banking BI analyst (SQL Server / T-SQL), now
building toward Analytics Engineering. The queries prefer ANSI SQL and CTE-based
composition; wherever a dialect-specific function appears, the inline comment
gives the **T-SQL equivalent** (my primary stack).

> All 16 queries are **verified to run** against the included schema + seed on
> DuckDB 1.5. The seed is deterministic (fixed RNG seed), so results are
> reproducible.

---

## Dataset at a glance

| Table           | Rows  | Grain                                   |
|-----------------|------:|-----------------------------------------|
| `customers`     |    60 | one banking customer (12 monthly cohorts of 2023) |
| `accounts`      |    88 | deposit product (checking / savings / money market) |
| `transactions`  | 4,389 | posted money movement, Jan 2023 – Jun 2024 |
| `cards`         |    76 | debit / credit card linked to an account |
| `loans`         |    30 | originated loan across 4 quarterly vintages |
| `loan_payments` |   377 | scheduled installment with pay/miss behavior |

The seed deliberately bakes in **shape** so analytics are meaningful: monthly
signup cohorts with decaying retention, churned customers who go silent, a
deposit-growth trend with seasonality, and loans spanning the full delinquency
spectrum (current → late → delinquent → charged-off).

See [`docs/er-diagram.md`](docs/er-diagram.md) for the ER diagram and grain notes.

---

## How to run

The queries target the **ANSI / DuckDB / PostgreSQL** dialect family (they share
`DATE_TRUNC`, `EXTRACT`, `PERCENTILE_CONT ... WITHIN GROUP`, `GREATEST`,
`INTERVAL`, and recursive CTEs). DuckDB is the fastest way to run the whole set
with zero setup.

### Option A — DuckDB (recommended, zero-config)

```bash
pip install duckdb            # or: brew install duckdb
duckdb portfolio.db           # opens a CLI; .db is gitignored

-- inside the DuckDB shell:
.read schema/schema.sql
.read schema/seed.sql
.read queries/01_running_account_balance.sql
```

Or run everything from Python:

```python
import duckdb, glob
con = duckdb.connect("portfolio.db")
con.execute(open("schema/schema.sql").read())
con.execute(open("schema/seed.sql").read())
for f in sorted(glob.glob("queries/*.sql")):
    print(f)
    print(con.execute(open(f).read()).fetchdf())
```

### Option B — PostgreSQL

```bash
createdb fintech_portfolio
psql fintech_portfolio -f schema/schema.sql
psql fintech_portfolio -f schema/seed.sql
psql fintech_portfolio -f queries/07_rfm_segmentation.sql
```

Everything runs unchanged on Postgres 12+.

### Option C — SQLite (partial)

Stock SQLite runs the schema, the seed, and **8 of 16** queries as-is. The
remaining 8 use functions SQLite lacks; each query header documents the swap.
Substitutions:

| DuckDB / Postgres            | SQLite replacement                                   |
|------------------------------|------------------------------------------------------|
| `DATE_TRUNC('month', d)`     | `strftime('%Y-%m-01', d)`                             |
| `EXTRACT(YEAR FROM d)` etc.  | `CAST(strftime('%Y', d) AS INT)`                      |
| `GREATEST(a, b)`             | `MAX(a, b)` (SQLite's scalar `MAX` of N args)         |
| `d + INTERVAL '1 day'`       | `date(d, '+1 day')`                                   |
| `PERCENTILE_CONT(p) WITHIN GROUP (ORDER BY x)` | no native equivalent — emulate with `NTILE`/ordered `ROW_NUMBER`, or use the DuckDB/Postgres path |

Queries that run on SQLite unchanged: 01, 04, 05, 07, 08, 09, 10, 16.

### Option D — SQL Server / T-SQL (my home stack)

The schema and logic port directly. Type/function deltas are noted inline in
each file; the headline ones:

- `TIMESTAMP` → `DATETIME2`, `BOOLEAN` → `BIT`, `VARCHAR` → `NVARCHAR` for unicode.
- `DATE_TRUNC('month', d)` → `DATEFROMPARTS(YEAR(d), MONTH(d), 1)`.
- `EXTRACT(part FROM d)` → `DATEPART(part, d)`; date subtraction → `DATEDIFF(DAY, a, b)`.
- `GREATEST` → `CASE` / `IIF` (or `GREATEST` on SQL Server 2022+).
- `a || b` string concat → `a + b` or `CONCAT(a, b)`.
- `PERCENTILE_CONT` is a **window** function in T-SQL (returns one value per row)
  rather than an aggregate — wrap in `SELECT DISTINCT` / `AVG` to collapse to one
  row per group. `OFFSET ... FETCH` replaces `LIMIT`.
- Recursive CTE: same syntax (`WITH ...`), add `OPTION (MAXRECURSION 0)` for long
  date spines (default cap is 100).

---

## Query index

Each file opens with a header block: **business question**, **approach**, and
**technique**, plus dialect notes. Grouped by analytical theme.

### Window functions

| # | File | Business question | Technique showcased |
|---|------|-------------------|---------------------|
| 01 | [`01_running_account_balance.sql`](queries/01_running_account_balance.sql) | What was the balance after every transaction on an account? | Running total — `SUM() OVER (... ROWS UNBOUNDED PRECEDING)` |
| 02 | [`02_moving_average_spend.sql`](queries/02_moving_average_spend.sql) | How is each customer's monthly spend trending once smoothed? | Trailing 3-month moving average window frame |
| 03 | [`03_mom_yoy_growth.sql`](queries/03_mom_yoy_growth.sql) | How fast are deposits growing MoM and YoY? | `LAG(...,1)` / `LAG(...,12)` growth rates |
| 04 | [`04_rank_customers_by_spend.sql`](queries/04_rank_customers_by_spend.sql) | Who are the top spenders and which decile is each in? | `ROW_NUMBER` / `RANK` / `DENSE_RANK` / `NTILE` contrast |
| 05 | [`05_top_n_per_group.sql`](queries/05_top_n_per_group.sql) | What are each customer's top 3 spend categories? | Top-N per group via partitioned `ROW_NUMBER` |
| 16 | [`16_lead_days_between_logins.sql`](queries/16_lead_days_between_logins.sql) | How long until a customer's next transaction, on average and at worst? | `LEAD` look-ahead inter-event gaps |

### Customer analytics

| # | File | Business question | Technique showcased |
|---|------|-------------------|---------------------|
| 06 | [`06_cohort_retention.sql`](queries/06_cohort_retention.sql) | Do newer signup cohorts retain better or worse over their first 6 months? | Monthly cohort retention matrix (cohort + activity + offset pivot) |
| 07 | [`07_rfm_segmentation.sql`](queries/07_rfm_segmentation.sql) | Which customers are Champions, At Risk, or Hibernating? | RFM segmentation — `NTILE(5)` quintiles + segment bucketing |
| 08 | [`08_funnel_conversion.sql`](queries/08_funnel_conversion.sql) | Where do customers drop off in the product-adoption funnel? | Funnel / conversion — staged `EXISTS` flags + step ratios |
| 09 | [`09_gaps_and_islands_active_days.sql`](queries/09_gaps_and_islands_active_days.sql) | What is each account's longest consecutive-active-day streak? | Gaps-and-islands / sessionization (row-number differencing) |
| 10 | [`10_churn_detection.sql`](queries/10_churn_detection.sql) | Who has churned, and who is at risk relative to their own cadence? | Churn detection — inactivity threshold + `LAG` gaps |

### Time-series & reporting

| # | File | Business question | Technique showcased |
|---|------|-------------------|---------------------|
| 13 | [`13_pivot_transactions_by_channel.sql`](queries/13_pivot_transactions_by_channel.sql) | How does monthly volume split across ATM / POS / online / branch / ACH? | Pivot via conditional aggregation (`SUM(CASE ...)`) |
| 14 | [`14_recursive_date_spine.sql`](queries/14_recursive_date_spine.sql) | How do we report zero-deposit days without silently skipping them? | Recursive CTE date spine + outer-join densification |
| 15 | [`15_percentiles_median_balances.sql`](queries/15_percentiles_median_balances.sql) | What is the spend distribution (median / IQR / p90) by risk segment? | Percentiles / median — `PERCENTILE_CONT ... WITHIN GROUP` |

### Loan / credit-risk analytics

| # | File | Business question | Technique showcased |
|---|------|-------------------|---------------------|
| 11 | [`11_loan_delinquency_dpd_buckets.sql`](queries/11_loan_delinquency_dpd_buckets.sql) | What is the delinquency rate and DPD-bucket exposure of the portfolio? | Delinquency rate + Days-Past-Due aging buckets |
| 12 | [`12_loan_vintage_analysis.sql`](queries/12_loan_vintage_analysis.sql) | Do later origination vintages go bad faster? | Vintage analysis — cumulative 30+ DPD by months-on-book |

---

## Techniques coverage map

Every technique requested for a senior SQL portfolio is represented:

- **Running totals** — 01
- **Moving averages** — 02, 14
- **LAG / LEAD** — 03, 10, 16
- **RANK / DENSE_RANK / ROW_NUMBER** — 04, 05, 09
- **NTILE** — 04, 07
- **Cohort retention matrix** — 06
- **RFM segmentation** — 07
- **MoM / YoY growth** — 03
- **Funnel / conversion** — 08
- **Gaps-and-islands / sessionization** — 09
- **Churn detection** — 10
- **Loan delinquency rate & DPD buckets** — 11
- **Loan vintage analysis** — 12
- **Pivot (conditional aggregation)** — 13
- **Recursive CTE** — 14
- **Percentiles / median (`PERCENTILE_CONT`)** — 15
- **Top-N per group** — 05

---

## Skills demonstrated

- **Analytical SQL**: window functions (frames, ranking, offset), ordered-set
  aggregates, recursive CTEs, conditional aggregation, correlated existence checks.
- **Analytics patterns**: cohort retention, RFM, funnels, churn, sessionization,
  growth decomposition (MoM/YoY), distribution analysis (median vs mean skew).
- **Domain — banking / fintech**: deposit-balance mechanics, transaction channel
  mix, credit-risk reporting (delinquency rate, DPD aging, vintage curves).
- **Engineering discipline**: clean grain at every step, CTEs over nested
  subqueries, deterministic and reproducible seed data, divide-by-zero guards
  (`NULLIF`), gap-free time series via date spines, and portability across
  DuckDB / PostgreSQL / SQLite / SQL Server with documented dialect deltas.
- **Data modeling**: a normalized 6-table schema with primary/foreign keys,
  sensible types, and supporting indexes.

---

## Repository layout

```
sql-analytics-portfolio/
├── README.md
├── .gitignore
├── schema/
│   ├── schema.sql        # DDL: 6 tables, PK/FK, indexes, comments
│   ├── seed.sql          # deterministic INSERT seed data
│   └── _gen_seed.py      # generator that produced seed.sql (seed=42)
├── docs/
│   └── er-diagram.md     # mermaid ER diagram + grain notes
└── queries/
    ├── 01_running_account_balance.sql
    ├── 02_moving_average_spend.sql
    ├── ... (16 numbered analytical queries)
    └── 16_lead_days_between_logins.sql
```

The seed generator (`schema/_gen_seed.py`) is included for transparency; you only
need `schema.sql` + `seed.sql` to run the portfolio.
