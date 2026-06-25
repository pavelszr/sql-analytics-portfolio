# Entity-Relationship Diagram

The schema models a retail-banking relationship: customers hold deposit
**accounts**, accounts generate **transactions** and carry payment **cards**,
and customers separately hold **loans** that amortize through **loan_payments**.

```mermaid
erDiagram
    customers ||--o{ accounts : "holds"
    customers ||--o{ loans : "borrows"
    accounts  ||--o{ transactions : "records"
    accounts  ||--o{ cards : "issues"
    loans     ||--o{ loan_payments : "amortizes"

    customers {
        int     customer_id PK
        varchar first_name
        varchar last_name
        varchar email
        date    date_of_birth
        date    signup_date "cohort anchor"
        varchar home_state
        varchar risk_segment "low|medium|high"
    }

    accounts {
        int     account_id PK
        int     customer_id FK
        varchar account_type "checking|savings|money_market"
        date    opened_date
        date    closed_date "null while open"
        varchar status "active|dormant|closed"
    }

    transactions {
        bigint    transaction_id PK
        int       account_id FK
        date      txn_date
        timestamp txn_ts
        decimal   amount "signed: + credit / - debit"
        varchar   txn_type "deposit|withdrawal|purchase|transfer|fee|interest"
        varchar   merchant_category "null for non-purchase"
        varchar   channel "atm|pos|online|branch|ach"
    }

    cards {
        int     card_id PK
        int     account_id FK
        varchar card_type "debit|credit"
        date    issued_date
        date    expiry_date
        decimal credit_limit "null for debit"
        int     is_active "1|0"
    }

    loans {
        int     loan_id PK
        int     customer_id FK
        varchar loan_type "personal|auto|mortgage|student"
        date    origination_date "vintage anchor"
        decimal principal_amount
        decimal interest_rate "annual, e.g. 0.0650"
        int     term_months
        decimal monthly_payment
        varchar status "current|delinquent|paid_off|default|charged_off"
    }

    loan_payments {
        bigint  payment_id PK
        int     loan_id FK
        date    due_date
        date    paid_date "null = unpaid"
        decimal amount_due
        decimal amount_paid "0 when missed"
        int     installment_no "1..term_months (months-on-book)"
    }
```

## Grain notes

| Table          | Grain (one row per ...)                          |
|----------------|--------------------------------------------------|
| `customers`    | customer / household head                        |
| `accounts`     | deposit product held by a customer               |
| `transactions` | posted money movement on an account              |
| `cards`        | payment card linked to an account                |
| `loans`        | originated loan held by a customer               |
| `loan_payments`| scheduled installment for a loan                 |

## Sign convention

`transactions.amount` is **signed**: positive = credit / inflow (deposit,
interest), negative = debit / outflow (withdrawal, purchase, fee). Running
balances simply cumulatively sum the signed amount; spend metrics take
`ABS(amount)` filtered to `amount < 0`.
