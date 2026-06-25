#!/usr/bin/env python3
"""
Deterministic seed generator for the fintech analytics portfolio.

Produces schema/seed.sql with INSERT statements only (portable across
DuckDB / SQLite / Postgres). Run:  python schema/_gen_seed.py

Design goals (so every analytical query returns meaningful output):
  * 60 customers signing up across 12 monthly cohorts (Jan 2023 .. Dec 2023),
    so cohort-retention and MoM/YoY growth have shape.
  * Each customer has 1-2 accounts; transactions span ~18 months so running
    balances, moving averages, sessionization and churn all have signal.
  * Activity intentionally decays for some cohorts (retention curve) and some
    customers go silent for a stretch (churn / gaps-and-islands).
  * 30 loans across 4 vintages with realistic delinquency / DPD spread.
"""

import random
from datetime import date, timedelta, datetime

random.seed(42)  # deterministic

FIRST_NAMES = ["James","Mary","John","Patricia","Robert","Jennifer","Michael",
    "Linda","David","Elizabeth","William","Barbara","Richard","Susan","Joseph",
    "Jessica","Thomas","Sarah","Charles","Karen","Chris","Nancy","Daniel","Lisa",
    "Matthew","Betty","Anthony","Sandra","Mark","Ashley","Paul","Kimberly",
    "Steven","Donna","Andrew","Carol","Joshua","Michelle","Kenneth","Amanda",
    "Kevin","Dorothy","Brian","Melissa","George","Deborah","Edward","Stephanie",
    "Ronald","Rebecca","Tim","Laura","Jason","Helen","Jeff","Amy","Ryan","Anna",
    "Gary","Brenda"]
LAST_NAMES = ["Smith","Johnson","Williams","Brown","Jones","Garcia","Miller",
    "Davis","Rodriguez","Martinez","Hernandez","Lopez","Gonzalez","Wilson",
    "Anderson","Thomas","Taylor","Moore","Jackson","Martin","Lee","Perez",
    "Thompson","White","Harris","Sanchez","Clark","Ramirez","Lewis","Robinson",
    "Walker","Young","Allen","King","Wright","Scott","Torres","Nguyen","Hill",
    "Flores","Green","Adams","Nelson","Baker","Hall","Rivera","Campbell",
    "Mitchell","Carter","Roberts","Gomez","Phillips","Evans","Turner","Diaz",
    "Parker","Cruz","Edwards","Collins","Reyes"]
STATES = ["CA","TX","FL","NY","IL","PA","OH","GA","NC","MI","NJ","VA","WA","AZ","MA"]
RISK = ["low","medium","high"]
MERCHANT_CATS = ["grocery","dining","fuel","travel","retail","utilities",
    "entertainment","healthcare","electronics","subscription"]
PURCHASE_CHANNELS = ["pos","online"]

def d(dt):
    return dt.strftime("%Y-%m-%d")

def ts(dt, hh, mm):
    return datetime(dt.year, dt.month, dt.day, hh, mm, 0).strftime("%Y-%m-%d %H:%M:%S")

def add_months(dt, n):
    m = dt.month - 1 + n
    y = dt.year + m // 12
    m = m % 12 + 1
    day = min(dt.day, [31,29 if y%4==0 and (y%100!=0 or y%400==0) else 28,31,30,31,30,31,31,30,31,30,31][m-1])
    return date(y, m, day)

# ---------------------------------------------------------------------------
# CUSTOMERS  -  60 customers, 5 per month across 12 cohorts of 2023.
# ---------------------------------------------------------------------------
customers = []
cid = 1
for month in range(1, 13):
    cohort_anchor = date(2023, month, 1)
    for _ in range(5):
        signup = cohort_anchor + timedelta(days=random.randint(0, 24))
        fn = FIRST_NAMES[(cid - 1) % len(FIRST_NAMES)]
        ln = LAST_NAMES[(cid * 7) % len(LAST_NAMES)]
        dob = date(random.randint(1960, 2000), random.randint(1, 12), random.randint(1, 28))
        customers.append({
            "id": cid,
            "first": fn,
            "last": ln,
            "email": f"{fn.lower()}.{ln.lower()}{cid}@example.com",
            "dob": dob,
            "signup": signup,
            "state": STATES[(cid * 3) % len(STATES)],
            "risk": RISK[cid % 3],
            "cohort_month": cohort_anchor,
        })
        cid += 1

# ---------------------------------------------------------------------------
# ACCOUNTS  -  each customer gets a checking; ~45% also get a savings/MM.
# ---------------------------------------------------------------------------
accounts = []
aid = 1
for c in customers:
    accounts.append({
        "id": aid, "customer_id": c["id"], "type": "checking",
        "opened": c["signup"], "closed": None, "status": "active",
    })
    c["primary_account"] = aid
    aid += 1
    if c["id"] % 100 in range(0, 100) and random.random() < 0.45:
        second_type = random.choice(["savings", "money_market"])
        accounts.append({
            "id": aid, "customer_id": c["id"], "type": second_type,
            "opened": c["signup"] + timedelta(days=random.randint(10, 120)),
            "closed": None, "status": "active",
        })
        aid += 1

# Mark churned customers and assign each a single, customer-level churn offset
# (months after signup at which ALL their accounts go silent). Spreading the
# offset across 1..7 months produces a realistic decaying retention curve;
# later cohorts churn a bit more often so newer cohorts retain visibly worse.
churned_ids = set()
churn_offset_by_customer = {}   # customer_id -> months-after-signup to go silent
for c in customers:
    cohort_idx = c["cohort_month"].month
    churn_prob = 0.30 + 0.02 * cohort_idx          # ~32%..54% across the year
    if random.random() < churn_prob:
        churned_ids.add(c["id"])
        # weight toward mid-life churn (months 2..6) with a few early/late
        churn_offset_by_customer[c["id"]] = random.choices(
            population=[1, 2, 3, 4, 5, 6, 7],
            weights=[1, 3, 4, 4, 3, 2, 1],
            k=1,
        )[0]

# ---------------------------------------------------------------------------
# TRANSACTIONS  -  monthly activity per account from open month to data end.
#   * recurring salary deposit (credit) near month start
#   * several purchases (debits) through the month
#   * monthly fee + occasional interest credit on savings
#   * churned customers stop after a churn month -> activity gaps
# Data window ends 2024-06-30.
# ---------------------------------------------------------------------------
DATA_END = date(2024, 6, 30)
transactions = []
txid = 1

for a in accounts:
    cust = next(x for x in customers if x["id"] == a["customer_id"])
    is_churned = cust["id"] in churned_ids
    # Customer-level churn offset (same for all of a customer's accounts), measured
    # from the customer's signup month so the retention matrix decays cleanly.
    if is_churned:
        signup_month = date(cust["signup"].year, cust["signup"].month, 1)
        churn_cutoff = add_months(signup_month, churn_offset_by_customer[cust["id"]])
    else:
        churn_cutoff = None

    opened = a["opened"]
    # No transaction may predate the account-open date.
    def in_window(dt):
        return opened <= dt <= DATA_END

    month_cursor = date(opened.year, opened.month, 1)
    salary_base = random.choice([2800, 3200, 3600, 4200, 5000, 6000])
    while month_cursor <= DATA_END:
        if churn_cutoff and month_cursor >= churn_cutoff:
            break
        # ---- salary / inflow (checking only) ----
        if a["type"] == "checking":
            pay_day = month_cursor + timedelta(days=random.randint(0, 3))
            if in_window(pay_day):
                amt = salary_base + random.randint(-150, 150)
                transactions.append((txid, a["id"], d(pay_day), ts(pay_day, 6, 0),
                    f"{amt:.2f}", "deposit", None, "ach"))
                txid += 1
        else:
            # interest credit on savings / money market
            interest_day = month_cursor + timedelta(days=2)
            if in_window(interest_day):
                amt = round(random.uniform(3, 28), 2)
                transactions.append((txid, a["id"], d(interest_day), ts(interest_day, 0, 5),
                    f"{amt:.2f}", "interest", None, "ach"))
                txid += 1

        # ---- purchases / withdrawals (debits) ----
        n_purch = random.randint(3, 9) if a["type"] == "checking" else random.randint(0, 2)
        for _ in range(n_purch):
            day_off = random.randint(0, 27)
            pdate = month_cursor + timedelta(days=day_off)
            if not in_window(pdate):
                continue
            amt = -round(random.uniform(8, 320), 2)
            cat = random.choice(MERCHANT_CATS)
            chan = random.choice(PURCHASE_CHANNELS + ["atm"])
            ttype = "withdrawal" if chan == "atm" else "purchase"
            mcat = None if ttype == "withdrawal" else cat
            transactions.append((txid, a["id"], d(pdate), ts(pdate, random.randint(8, 21), random.randint(0, 59)),
                f"{amt:.2f}", ttype, mcat, chan))
            txid += 1

        # ---- monthly maintenance fee ----
        fee_day = month_cursor + timedelta(days=27)
        if in_window(fee_day) and random.random() < 0.7:
            transactions.append((txid, a["id"], d(fee_day), ts(fee_day, 23, 0),
                "-12.00", "fee", None, "branch"))
            txid += 1

        month_cursor = add_months(month_cursor, 1)

# ---------------------------------------------------------------------------
# CARDS  -  every checking account gets a debit card; some get a credit card.
# ---------------------------------------------------------------------------
cards = []
card_id = 1
for a in accounts:
    if a["type"] == "checking":
        issued = a["opened"] + timedelta(days=3)
        cards.append((card_id, a["id"], "debit", d(issued),
            d(add_months(issued, 48)), None, 1))
        card_id += 1
        if random.random() < 0.4:
            issued2 = a["opened"] + timedelta(days=random.randint(30, 200))
            limit = random.choice([2000, 5000, 7500, 10000, 15000])
            active = 1 if a["customer_id"] not in churned_ids else 0
            cards.append((card_id, a["id"], "credit", d(issued2),
                d(add_months(issued2, 48)), f"{limit:.2f}", active))
            card_id += 1

# ---------------------------------------------------------------------------
# LOANS  -  30 loans across 4 vintages (origination quarters) with a spread
# of statuses and delinquency for portfolio metrics + vintage analysis.
# ---------------------------------------------------------------------------
LOAN_TYPES = {
    "personal": (5000, 25000, 0.0899, 0.1599, [24, 36, 48]),
    "auto":     (12000, 45000, 0.0499, 0.0899, [48, 60, 72]),
    "mortgage": (150000, 400000, 0.0399, 0.0649, [360]),
    "student":  (8000, 40000, 0.0399, 0.0699, [120, 180]),
}
# vintage origination months (one per quarter) to make vintage curves comparable.
# Keep all loans of a vintage in the SAME calendar month for clean cohorts.
VINTAGES = [date(2023, 1, 5), date(2023, 4, 5), date(2023, 7, 5), date(2023, 10, 5)]

def monthly_pmt(principal, annual_rate, term):
    r = annual_rate / 12.0
    if r == 0:
        return principal / term
    return principal * r * (1 + r) ** term / ((1 + r) ** term - 1)

loans = []
loan_payments = []
lid = 1
pay_id = 1
loan_customers = [c["id"] for c in customers]  # any customer may hold a loan

for i in range(30):
    ltype = list(LOAN_TYPES.keys())[i % 4]
    lo, hi, rlo, rhi, terms = LOAN_TYPES[ltype]
    principal = round(random.uniform(lo, hi), 2)
    rate = round(random.uniform(rlo, rhi), 4)
    term = random.choice(terms)
    orig = VINTAGES[i % 4] + timedelta(days=random.randint(0, 9))  # stay within the vintage month
    pmt = round(monthly_pmt(principal, rate, term), 2)
    cust_id = loan_customers[(i * 13) % len(loan_customers)]

    # Decide a behavior profile that yields varied DPD / status.
    # First 6 loans get a fixed spread so every status enum is represented
    # deterministically; the rest are randomized.
    FIXED = ["current", "late", "delinquent", "paid_off", "default", "current"]
    if i < len(FIXED):
        profile = FIXED[i]
    else:
        roll = random.random()
        if roll < 0.50:
            profile = "current"        # pays on time
        elif roll < 0.70:
            profile = "late"           # chronically a few days late
        elif roll < 0.84:
            profile = "delinquent"     # recently missed, growing DPD
        elif roll < 0.93:
            profile = "paid_off"       # finished early
        else:
            profile = "default"        # stopped paying, charged off

    # paid_off loans are modeled as fully-amortized short notes (so the label is
    # honest): cap the term so all installments fall before DATA_END.
    if profile == "paid_off":
        term = 12
        pmt = round(monthly_pmt(principal, rate, term), 2)
        orig = date(2023, 1, 5) + timedelta(days=random.randint(0, 9))

    # Generate installments from origination up to DATA_END (or term).
    n_periods = 0
    cur_status = "current"
    delinq_flag = False
    first_due = add_months(orig, 1)
    for n in range(1, term + 1):
        due = add_months(first_due, n - 1)
        if due > DATA_END:
            break
        n_periods += 1

        amount_due = pmt
        if profile == "current":
            paid = due + timedelta(days=random.randint(-2, 2))
            amount_paid = pmt
        elif profile == "late":
            paid = due + timedelta(days=random.randint(5, 20))
            amount_paid = pmt
        elif profile == "paid_off":
            paid = due + timedelta(days=random.randint(-2, 3))
            amount_paid = pmt
        elif profile == "delinquent":
            # on time for a while then last 2-3 installments missed
            months_from_now = (DATA_END.year - due.year) * 12 + (DATA_END.month - due.month)
            if months_from_now <= 2:
                paid = None
                amount_paid = 0.0
                delinq_flag = True
            else:
                paid = due + timedelta(days=random.randint(0, 8))
                amount_paid = pmt
        else:  # default
            months_paid = 4
            if n <= months_paid:
                paid = due + timedelta(days=random.randint(0, 10))
                amount_paid = pmt
            else:
                paid = None
                amount_paid = 0.0
                delinq_flag = True

        paid_str = "NULL" if paid is None else f"'{d(paid)}'"
        loan_payments.append((pay_id, lid, d(due), paid_str,
            f"{amount_due:.2f}", f"{amount_paid:.2f}", n))
        pay_id += 1

    # Final loan status
    if profile == "paid_off" and n_periods >= 1:
        cur_status = "paid_off"
    elif profile == "default":
        cur_status = "charged_off"
    elif profile == "delinquent" or delinq_flag:
        cur_status = "delinquent"
    else:
        cur_status = "current"

    loans.append((lid, cust_id, ltype, d(orig), f"{principal:.2f}",
        f"{rate:.4f}", term, f"{pmt:.2f}", cur_status))
    lid += 1

# ---------------------------------------------------------------------------
# Emit SQL
# ---------------------------------------------------------------------------
out = []
out.append("-- =============================================================================")
out.append("-- seed.sql  -  Deterministic seed data (generated by _gen_seed.py, seed=42)")
out.append("-- Portable INSERTs for DuckDB / SQLite / PostgreSQL.")
out.append("-- T-SQL note: identical syntax; booleans are stored as 0/1 (BIT) and")
out.append("--   timestamps as 'YYYY-MM-DD HH:MM:SS' literals (cast to DATETIME2 if needed).")
out.append("-- =============================================================================")
out.append("")

def vals_customers(c):
    return (f"({c['id']}, '{c['first']}', '{c['last']}', '{c['email']}', "
            f"'{d(c['dob'])}', '{d(c['signup'])}', '{c['state']}', '{c['risk']}')")

out.append("INSERT INTO customers (customer_id, first_name, last_name, email, date_of_birth, signup_date, home_state, risk_segment) VALUES")
out.append(",\n".join("  " + vals_customers(c) for c in customers) + ";")
out.append("")

def vals_accounts(a):
    closed = "NULL" if a["closed"] is None else f"'{d(a['closed'])}'"
    return (f"({a['id']}, {a['customer_id']}, '{a['type']}', '{d(a['opened'])}', "
            f"{closed}, '{a['status']}')")

out.append("INSERT INTO accounts (account_id, customer_id, account_type, opened_date, closed_date, status) VALUES")
out.append(",\n".join("  " + vals_accounts(a) for a in accounts) + ";")
out.append("")

# transactions in batches of 500 for engine friendliness
out.append("INSERT INTO transactions (transaction_id, account_id, txn_date, txn_ts, amount, txn_type, merchant_category, channel) VALUES")
def vals_txn(t):
    mcat = "NULL" if t[6] is None else f"'{t[6]}'"
    return (f"({t[0]}, {t[1]}, '{t[2]}', '{t[3]}', {t[4]}, '{t[5]}', {mcat}, '{t[7]}')")
out.append(",\n".join("  " + vals_txn(t) for t in transactions) + ";")
out.append("")

out.append("INSERT INTO cards (card_id, account_id, card_type, issued_date, expiry_date, credit_limit, is_active) VALUES")
def vals_card(c):
    lim = "NULL" if c[5] is None else c[5]
    return (f"({c[0]}, {c[1]}, '{c[2]}', '{c[3]}', '{c[4]}', {lim}, {c[6]})")
out.append(",\n".join("  " + vals_card(c) for c in cards) + ";")
out.append("")

out.append("INSERT INTO loans (loan_id, customer_id, loan_type, origination_date, principal_amount, interest_rate, term_months, monthly_payment, status) VALUES")
def vals_loan(l):
    return (f"({l[0]}, {l[1]}, '{l[2]}', '{l[3]}', {l[4]}, {l[5]}, {l[6]}, {l[7]}, '{l[8]}')")
out.append(",\n".join("  " + vals_loan(l) for l in loans) + ";")
out.append("")

out.append("INSERT INTO loan_payments (payment_id, loan_id, due_date, paid_date, amount_due, amount_paid, installment_no) VALUES")
def vals_lp(p):
    return (f"({p[0]}, {p[1]}, '{p[2]}', {p[3]}, {p[4]}, {p[5]}, {p[6]})")
out.append(",\n".join("  " + vals_lp(p) for p in loan_payments) + ";")
out.append("")

with open("schema/seed.sql", "w", encoding="utf-8") as f:
    f.write("\n".join(out))

print(f"customers={len(customers)} accounts={len(accounts)} "
      f"transactions={len(transactions)} cards={len(cards)} "
      f"loans={len(loans)} loan_payments={len(loan_payments)} churned={len(churned_ids)}")
