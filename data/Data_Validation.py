import pandas as pd
import numpy as np
from datetime import datetime

# ── Load Data ────────────────────────────────────────────────────
print("=" * 55)
print("   FINTECH LOAN DATASET — DATA QUALITY REPORT")
print("=" * 55)

df = pd.read_csv('loan_data.csv')
print(f"\n  Loaded {len(df):,} rows and {len(df.columns)} columns successfully.")
print(f"  Columns found: {list(df.columns)}\n")

total_issues = 0

# ════════════════════════════════════════════════════════════════
# CHECK 1 — NULL VALUES
# ════════════════════════════════════════════════════════════════
print("─" * 55)
print("  CHECK 1: NULL VALUE ANALYSIS")
print("─" * 55)

null_counts = df.isnull().sum()
expected_nulls = ['payment_date']  # only this column should have nulls

for col in df.columns:
    null_count = null_counts[col]
    if col in expected_nulls:
        print(f"  ✔  {col:<25} {null_count:>5} nulls  (expected — unpaid loans)")
    elif null_count > 0:
        print(f"  ✘  {col:<25} {null_count:>5} nulls  ← ISSUE FOUND")
        total_issues += 1
    else:
        print(f"  ✔  {col:<25} {null_count:>5} nulls")

# ════════════════════════════════════════════════════════════════
# CHECK 2 — DUPLICATE LOAN IDs
# ════════════════════════════════════════════════════════════════
print("\n" + "─" * 55)
print("  CHECK 2: DUPLICATE LOAN ID CHECK")
print("─" * 55)

duplicate_count = df['loan_id'].duplicated().sum()

if duplicate_count == 0:
    print(f"  ✔  No duplicate loan_ids found. All {len(df):,} IDs are unique.")
else:
    print(f"  ✘  {duplicate_count} duplicate loan_ids found ← ISSUE FOUND")
    print(f"     Duplicates: {df[df['loan_id'].duplicated()]['loan_id'].tolist()}")
    total_issues += 1

# ════════════════════════════════════════════════════════════════
# CHECK 3 — DPD vs LOAN STATUS LOGIC
# ════════════════════════════════════════════════════════════════
print("\n" + "─" * 55)
print("  CHECK 3: DPD vs LOAN STATUS CONSISTENCY")
print("─" * 55)

# Rule 1: NPA loans must have DPD >= 91
npa_rows         = df[df['loan_status'] == 'NPA']
npa_dpd_issues   = npa_rows[npa_rows['dpd'] < 91]

if len(npa_dpd_issues) == 0:
    print(f"  ✔  All {len(npa_rows):,} NPA loans have DPD >= 91. Logic consistent.")
else:
    print(f"  ✘  {len(npa_dpd_issues)} NPA loans found with DPD < 91 ← ISSUE FOUND")
    total_issues += 1

# Rule 2: Written-Off loans must have DPD >= 91
wo_rows        = df[df['loan_status'] == 'Written-Off']
wo_dpd_issues  = wo_rows[wo_rows['dpd'] < 91]

if len(wo_dpd_issues) == 0:
    print(f"  ✔  All {len(wo_rows):,} Written-Off loans have DPD >= 91. Logic consistent.")
else:
    print(f"  ✘  {len(wo_dpd_issues)} Written-Off loans found with DPD < 91 ← ISSUE FOUND")
    total_issues += 1

# Rule 3: Closed loans should have DPD = 0
closed_rows       = df[df['loan_status'] == 'Closed']
closed_dpd_issues = closed_rows[closed_rows['dpd'] > 0]

if len(closed_dpd_issues) == 0:
    print(f"  ✔  All {len(closed_rows):,} Closed loans have DPD = 0. Logic consistent.")
else:
    print(f"  ✘  {len(closed_dpd_issues)} Closed loans found with DPD > 0 ← ISSUE FOUND")
    total_issues += 1

# ════════════════════════════════════════════════════════════════
# CHECK 4 — AMOUNT PAID vs PAYMENT DATE LOGIC
# ════════════════════════════════════════════════════════════════
print("\n" + "─" * 55)
print("  CHECK 4: AMOUNT PAID vs PAYMENT DATE LOGIC")
print("─" * 55)

# If payment_date is null, amount_paid must be 0
unpaid_rows          = df[df['payment_date'].isnull()]
unpaid_amount_issues = unpaid_rows[unpaid_rows['amount_paid'] > 0]

if len(unpaid_amount_issues) == 0:
    print(f"  ✔  All {len(unpaid_rows):,} unpaid loans have amount_paid = 0. Logic consistent.")
else:
    print(f"  ✘  {len(unpaid_amount_issues)} unpaid loans have amount_paid > 0 ← ISSUE FOUND")
    total_issues += 1

# If payment_date exists, amount_paid must be > 0
paid_rows          = df[df['payment_date'].notnull()]
paid_amount_issues = paid_rows[paid_rows['amount_paid'] == 0]

if len(paid_amount_issues) == 0:
    print(f"  ✔  All {len(paid_rows):,} paid loans have amount_paid > 0. Logic consistent.")
else:
    print(f"  ✘  {len(paid_amount_issues)} paid loans have amount_paid = 0 ← ISSUE FOUND")
    total_issues += 1

# ════════════════════════════════════════════════════════════════
# CHECK 5 — DATE RANGE VALIDATION
# ════════════════════════════════════════════════════════════════
print("\n" + "─" * 55)
print("  CHECK 5: DATE RANGE VALIDATION")
print("─" * 55)

df['disbursement_date'] = pd.to_datetime(df['disbursement_date'])

start_date = datetime(2022, 1, 1)
end_date   = datetime(2023, 12, 31)

out_of_range = df[
    (df['disbursement_date'] < start_date) |
    (df['disbursement_date'] > end_date)
]

if len(out_of_range) == 0:
    print(f"  ✔  All disbursement dates fall within Jan 2022 – Dec 2023.")
    print(f"     Earliest: {df['disbursement_date'].min().strftime('%Y-%m-%d')}")
    print(f"     Latest  : {df['disbursement_date'].max().strftime('%Y-%m-%d')}")
else:
    print(f"  ✘  {len(out_of_range)} loans have disbursement dates out of range ← ISSUE FOUND")
    total_issues += 1

# ════════════════════════════════════════════════════════════════
# CHECK 6 — DPD VALUE RANGE
# ════════════════════════════════════════════════════════════════
print("\n" + "─" * 55)
print("  CHECK 6: DPD VALUE RANGE CHECK")
print("─" * 55)

negative_dpd = df[df['dpd'] < 0]
extreme_dpd  = df[df['dpd'] > 365]

if len(negative_dpd) == 0:
    print(f"  ✔  No negative DPD values found.")
else:
    print(f"  ✘  {len(negative_dpd)} loans have negative DPD ← ISSUE FOUND")
    total_issues += 1

if len(extreme_dpd) == 0:
    print(f"  ✔  No extreme DPD values (>365 days) found.")
else:
    print(f"  ✘  {len(extreme_dpd)} loans have DPD > 365 days ← ISSUE FOUND")
    total_issues += 1

# ════════════════════════════════════════════════════════════════
# CHECK 7 — DPD BUCKET DISTRIBUTION
# ════════════════════════════════════════════════════════════════
print("\n" + "─" * 55)
print("  CHECK 7: DPD BUCKET DISTRIBUTION")
print("─" * 55)

current  = (df['dpd'] == 0).sum()
sma0     = ((df['dpd'] >= 1)  & (df['dpd'] <= 30)).sum()
sma1     = ((df['dpd'] >= 31) & (df['dpd'] <= 60)).sum()
sma2     = ((df['dpd'] >= 61) & (df['dpd'] <= 90)).sum()
npa      = (df['dpd'] >= 91).sum()
N        = len(df)

print(f"  {'Bucket':<15} {'Count':>6}   {'Actual %':>8}   {'Target %':>8}")
print(f"  {'-'*45}")
print(f"  {'Current (0)':<15} {current:>6}   {current/N*100:>7.1f}%   {'55.0%':>8}")
print(f"  {'SMA-0 (1-30)':<15} {sma0:>6}   {sma0/N*100:>7.1f}%   {'20.0%':>8}")
print(f"  {'SMA-1 (31-60)':<15} {sma1:>6}   {sma1/N*100:>7.1f}%   {'12.0%':>8}")
print(f"  {'SMA-2 (61-90)':<15} {sma2:>6}   {sma2/N*100:>7.1f}%   {'8.0%':>8}")
print(f"  {'NPA (91+)':<15} {npa:>6}   {npa/N*100:>7.1f}%   {'5.0%':>8}")

N = len(df)

# ════════════════════════════════════════════════════════════════
# CHECK 8 — LOAN AMOUNT RANGE BY PRODUCT TYPE
# ════════════════════════════════════════════════════════════════
print("\n" + "─" * 55)
print("  CHECK 8: LOAN AMOUNT RANGE BY PRODUCT TYPE")
print("─" * 55)

product_ranges = {
    'Personal Loan': (50_000,   500_000),
    'Auto Loan':     (200_000, 1_500_000),
    'Home Loan':     (500_000, 2_000_000),
    'Business Loan': (100_000, 2_000_000),
    'Gold Loan':     (50_000,   300_000),
}

for product, (lo, hi) in product_ranges.items():
    subset        = df[df['product_type'] == product]
    out_of_range  = subset[(subset['loan_amount'] < lo) | (subset['loan_amount'] > hi)]
    count         = len(subset)
    issues        = len(out_of_range)
    min_amt       = subset['loan_amount'].min()
    max_amt       = subset['loan_amount'].max()

    if issues == 0:
        print(f"  ✔  {product:<15} {count:>4} loans  |  "
              f"Range: ₹{min_amt:,.0f} – ₹{max_amt:,.0f}  ✔")
    else:
        print(f"  ✘  {product:<15} {issues} loans out of range ← ISSUE FOUND")
        total_issues += 1

# ════════════════════════════════════════════════════════════════
# FINAL SUMMARY
# ════════════════════════════════════════════════════════════════
print("\n" + "=" * 55)
print("  FINAL DATA QUALITY SUMMARY")
print("=" * 55)
print(f"  Total rows validated  : {len(df):,}")
print(f"  Total checks run      : 8")
print(f"  Issues found          : {total_issues}")

if total_issues == 0:
    print(f"\n  ✔  ALL CHECKS PASSED — Dataset is clean and")
    print(f"     ready to load into the star schema.")
else:
    print(f"\n  ✘  {total_issues} ISSUE(S) FOUND — Review flagged checks above")
    print(f"     before loading into the star schema.")

print("=" * 55)