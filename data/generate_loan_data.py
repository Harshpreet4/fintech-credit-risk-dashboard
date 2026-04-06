import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import random

# ── Reproducibility ──────────────────────────────────────────────
np.random.seed(42)
random.seed(42)

N = 5000  # total loan records

# ── Reference Data ───────────────────────────────────────────────
cities = ['Mumbai', 'Delhi', 'Bangalore', 'Chennai',
          'Hyderabad', 'Pune', 'Kolkata', 'Ahmedabad']

product_config = {
    'Personal Loan': (50_000,   500_000),
    'Auto Loan':     (200_000, 1_500_000),
    'Home Loan':     (500_000, 2_000_000),
    'Business Loan': (100_000, 2_000_000),
    'Gold Loan':     (50_000,   300_000),
}

tenure_options = [12, 24, 36, 48, 60]

branches = {
    'BR-01': 'Mumbai Central',
    'BR-02': 'Delhi North',
    'BR-03': 'Bangalore East',
    'BR-04': 'Chennai South',
    'BR-05': 'Hyderabad West',
    'BR-06': 'Pune Central',
    'BR-07': 'Kolkata North',
    'BR-08': 'Ahmedabad East',
    'BR-09': 'Mumbai West',
    'BR-10': 'Delhi South',
}

agent_names = [
    'Rahul Mehta', 'Priya Sharma', 'Amit Kumar', 'Sneha Iyer',
    'Vikram Singh', 'Anita Desai', 'Rohan Gupta', 'Kavya Nair',
    'Suresh Rao',  'Pooja Joshi', 'Arjun Patel', 'Divya Menon',
    'Nikhil Shah', 'Ritu Agarwal', 'Manish Tiwari',
]

loan_status_map = {
    'Current': ['Active', 'Closed'],
    'SMA-0':   ['Active'],
    'SMA-1':   ['Active'],
    'SMA-2':   ['Active'],
    'NPA':     ['NPA', 'Written-Off'],
}

# ── DPD Distribution ─────────────────────────────────────────────
# 55% Current | 20% SMA-0 | 12% SMA-1 | 8% SMA-2 | 5% NPA
dpd_buckets = np.random.choice(
    ['Current', 'SMA-0', 'SMA-1', 'SMA-2', 'NPA'],
    size=N,
    p=[0.55, 0.20, 0.12, 0.08, 0.05]
)

def get_dpd(bucket):
    if bucket == 'Current': return 0
    if bucket == 'SMA-0':   return np.random.randint(1,  31)
    if bucket == 'SMA-1':   return np.random.randint(31, 61)
    if bucket == 'SMA-2':   return np.random.randint(61, 91)
    if bucket == 'NPA':     return np.random.randint(91, 181)

# ── Build Rows ───────────────────────────────────────────────────
rows = []

for i in range(N):
    loan_id     = f'LN-{i+1:05d}'
    customer_id = f'CUST-{np.random.randint(1000, 9999)}'
    
    # Name
    first_names = ['Priya','Rahul','Amit','Sneha','Vikram','Anita',
                   'Rohan','Kavya','Suresh','Pooja','Arjun','Divya',
                   'Nikhil','Ritu','Manish','Sanjay','Meena','Deepak']
    last_names  = ['Sharma','Mehta','Kumar','Iyer','Singh','Desai',
                   'Gupta','Nair','Rao','Joshi','Patel','Menon',
                   'Shah','Agarwal','Tiwari','Verma','Reddy','Khanna']
    customer_name = f'{random.choice(first_names)} {random.choice(last_names)}'
    
    age    = np.random.randint(22, 66)
    gender = np.random.choice(['Male', 'Female'], p=[0.55, 0.45])
    city   = random.choice(cities)
    
    # Product
    product_type        = random.choice(list(product_config.keys()))
    lo, hi              = product_config[product_type]
    loan_amount         = round(np.random.uniform(lo, hi), -3)  # round to nearest 1000
    interest_rate       = round(np.random.uniform(8.0, 24.0), 1)
    tenure_months       = random.choice(tenure_options)
    
    # EMI (simple flat calc — good enough for BI project)
    monthly_rate = interest_rate / (12 * 100)
    if monthly_rate > 0:
        emi_amount = round(
            loan_amount * monthly_rate * (1 + monthly_rate)**tenure_months /
            ((1 + monthly_rate)**tenure_months - 1), 2
        )
    else:
        emi_amount = round(loan_amount / tenure_months, 2)

    # Dates
    disbursement_date = datetime(2022, 1, 1) + timedelta(
        days=np.random.randint(0, 730)  # Jan 2022 – Dec 2023
    )
    due_date = disbursement_date + timedelta(days=30)

    # DPD & Payment
    bucket = dpd_buckets[i]
    dpd    = get_dpd(bucket)

    if dpd == 0:
        # Paid on time or early
        payment_date = due_date - timedelta(days=np.random.randint(0, 3))
        amount_paid  = emi_amount
    else:
        # Overdue — no payment made
        payment_date = None
        amount_paid  = 0.0

    # Branch & Agent
    branch_id   = random.choice(list(branches.keys()))
    branch_name = branches[branch_id]
    agent_idx   = np.random.randint(1, 16)
    agent_id    = f'AGT-{agent_idx:03d}'
    agent_name  = agent_names[agent_idx - 1]

    # Loan Status
    possible_statuses = loan_status_map[bucket]
    if bucket == 'Current':
        loan_status = np.random.choice(
            possible_statuses, p=[0.85, 0.15]
        )
    else:
        loan_status = random.choice(possible_statuses)

    rows.append({
        'loan_id':           loan_id,
        'customer_id':       customer_id,
        'customer_name':     customer_name,
        'age':               age,
        'gender':            gender,
        'city':              city,
        'product_type':      product_type,
        'loan_amount':       loan_amount,
        'interest_rate':     interest_rate,
        'tenure_months':     tenure_months,
        'disbursement_date': disbursement_date.strftime('%Y-%m-%d'),
        'due_date':          due_date.strftime('%Y-%m-%d'),
        'payment_date':      payment_date.strftime('%Y-%m-%d') if payment_date else None,
        'emi_amount':        emi_amount,
        'amount_paid':       amount_paid,
        'dpd':               dpd,
        'branch_id':         branch_id,
        'branch_name':       branch_name,
        'agent_id':          agent_id,
        'agent_name':        agent_name,
        'loan_status':       loan_status,
    })

# ── Save CSV ─────────────────────────────────────────────────────
df = pd.DataFrame(rows)
df.to_csv('loan_data.csv', index=False)

# ── Summary Stats ─────────────────────────────────────────────────
print("=" * 45)
print("   LOAN DATASET GENERATION COMPLETE")
print("=" * 45)
print(f"  Total loans generated : {len(df):,}")
print(f"  Total portfolio value : ₹{df['loan_amount'].sum():,.0f}")
print(f"  NPA count (DPD 91+)   : {(df['dpd'] >= 91).sum():,}")
print(f"  Average DPD (all)     : {df['dpd'].mean():.1f} days")
print(f"  Average DPD (overdue) : {df[df['dpd']>0]['dpd'].mean():.1f} days")
print("-" * 45)
print("  DPD Bucket Breakdown:")
print(f"    Current  (0)     : {(df['dpd']==0).sum():,}")
print(f"    SMA-0   (1-30)   : {((df['dpd']>=1)  & (df['dpd']<=30)).sum():,}")
print(f"    SMA-1   (31-60)  : {((df['dpd']>=31) & (df['dpd']<=60)).sum():,}")
print(f"    SMA-2   (61-90)  : {((df['dpd']>=61) & (df['dpd']<=90)).sum():,}")
print(f"    NPA     (91+)    : {(df['dpd']>=91).sum():,}")
print("=" * 45)
print("  loan_data.csv saved successfully!")
print("=" * 45)