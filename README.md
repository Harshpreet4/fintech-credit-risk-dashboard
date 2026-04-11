# Fintech Credit Risk & Collections Intelligence Dashboard


## Problem Statement

A retail lending company needs real-time visibility into portfolio health — how many loans are overdue, which branches are underperforming on recoveries, and where the early warning signals are for potential NPA (Non-Performing Asset) formation.

This project delivers a complete analytics solution: a Python ETL pipeline to generate and validate data, SQL transformations using CTEs and window functions, a star schema data warehouse, and a 3-page Power BI executive dashboard covering credit risk, delinquency trends, and collections performance.

---

## Tech Stack

| Tool | Usage |
|------|-------|
| Python (Pandas, NumPy) | Dataset generation + data validation |
| SQL Server | Star schema design + 6 analytical queries |
| Power BI | 3-page executive dashboard + 15 DAX measures |
| Star Schema | Dimensional modeling (1 fact + 4 dim tables) |
| GitHub | Version control + portfolio documentation |

---
fintech-credit-risk-dashboard/
│
├── README.md
├── .gitignore
│
├── data/
│   ├── generate_loan_data.py     ← Generates synthetic 5,000-row loan dataset
│   ├── data_validation.py        ← 8-check data quality validation script
│   └── loan_data.csv             ← Generated dataset (5,000 rows, 21 columns)
│
├── sql/
│   ├── 01_dpd_bucket_classification.sql
│   ├── 02_monthly_delinquency_trend.sql
│   ├── 03_roll_rate_analysis.sql
│   ├── 04_branch_collection_efficiency.sql
│   ├── 05_agent_performance.sql
│   ├── 06_npa_early_warning.sql
│   └── 07_create_star_schema.sql
│
├── screenshots/
│   ├── 01_executive_overview.png
│   ├── 02_delinquency_analysis.png
│   └── 03_branch_agent_performance.png
│
└── docs/
├── data_dictionary.md
└── kpi_definitions.md

---

## Data Schema

### Raw Dataset — `loan_data.csv` (5,000 rows, 21 columns)

| Column | Type | Description |
|--------|------|-------------|
| loan_id | String | Unique loan identifier (LN-00001 format) |
| customer_id | String | Unique customer identifier |
| customer_name | String | Customer full name |
| age | Integer | Customer age (22–65) |
| gender | String | Male / Female |
| city | String | One of 8 Indian cities |
| product_type | String | Personal / Auto / Home / Business / Gold Loan |
| loan_amount | Float | Principal amount in INR |
| interest_rate | Float | Annual interest rate % (8–24%) |
| tenure_months | Integer | Loan duration in months (12/24/36/48/60) |
| disbursement_date | Date | Date loan was disbursed (Jan 2022 – Dec 2023) |
| due_date | Date | EMI due date |
| payment_date | Date | Actual payment date (null = unpaid) |
| emi_amount | Float | Monthly EMI amount in INR |
| amount_paid | Float | Amount actually paid (0 if unpaid) |
| dpd | Integer | Days Past Due (0 = current) |
| branch_id | String | Branch code (BR-01 to BR-10) |
| branch_name | String | Branch full name |
| agent_id | String | Collections agent ID |
| agent_name | String | Collections agent full name |
| loan_status | String | Active / Closed / NPA / Written-Off |

---

## Star Schema Design
                ┌─────────────────┐
                │   dim_customer  │
                │─────────────────│
                │ customer_id (PK)│
                │ customer_name   │
                │ age, gender     │
                │ city            │
                └────────┬────────┘
                         │
┌──────────────┐    ┌────────▼──────────────┐    ┌──────────────────┐
│  dim_product │    │   fact_loan_payments  │    │   dim_branch     │
│──────────────│    │───────────────────────│    │──────────────────│
│ product_id   │◄───│ loan_id (PK)          │───►│ branch_id (PK)   │
│ product_type │    │ customer_id (FK)      │    │ branch_name      │
│ risk_category│    │ product_id (FK)       │    │ region           │
└──────────────┘    │ branch_id (FK)        │    └──────────────────┘
│ due_date_id (FK)      │
│ loan_amount           │    ┌──────────────────┐
│ emi_amount            │    │    dim_date      │
│ amount_paid           │───►│──────────────────│
│ dpd, loan_status      │    │ date_id (PK)     │
│ agent_id, agent_name  │    │ day, month       │
└───────────────────────┘    │ quarter, year    │
└──────────────────┘

---

## DPD Bucket Classification

| DPD Range | Bucket | Risk Level | Portfolio Share |
|-----------|--------|------------|-----------------|
| 0 | Current | Standard | 55% |
| 1–30 | SMA-0 | Watch | 20% |
| 31–60 | SMA-1 | Stressed | 12% |
| 61–90 | SMA-2 | Substandard | 8% |
| 91+ | NPA | Loss Asset | 5% |

---

## KPI Definitions

| KPI | Formula | Business Meaning |
|-----|---------|-----------------|
| Portfolio at Risk (PAR) | SUM(loan_amount where dpd > 0) / Total Portfolio | % of portfolio value at risk of default |
| NPA Rate % | COUNT(loans where dpd >= 91) / Total Loans | % of portfolio classified as non-performing |
| NPA Value | SUM(loan_amount where dpd >= 91) | Total INR exposure in non-performing loans |
| Collection Rate % | SUM(amount_paid) / SUM(emi_amount) | % of total dues successfully recovered |
| Recovery Rate % | SUM(amount_paid) / SUM(loan_amount where dpd > 0) | % of at-risk portfolio recovered |
| Delinquency Rate % | COUNT(loans where dpd > 0) / Total Loans | % of portfolio with any overdue payment |
| SMA-2 Exposure | SUM(loan_amount where dpd 61–90) | Portfolio value one step away from NPA |
| Avg DPD | AVERAGE(dpd where dpd > 0) | Average days overdue for delinquent loans |

---

## SQL Queries

| File | Purpose | Key Techniques |
|------|---------|----------------|
| 01_dpd_bucket_classification.sql | Classify loans into DPD buckets | CASE WHEN, GROUP BY, portfolio % |
| 02_monthly_delinquency_trend.sql | Track delinquency rate month over month | CTE, LAG() window function |
| 03_roll_rate_analysis.sql | Show loan movement between DPD buckets | Two CTEs, LAG(), JOIN on loan_id |
| 04_branch_collection_efficiency.sql | Rank branches by collection performance | CTE, RANK() window function, PAR |
| 05_agent_performance.sql | Score agents on recovery rate | GROUP BY, NTILE(4) quartile ranking |
| 06_npa_early_warning.sql | Flag loans 1 step from becoming NPA | CTE, days_to_npa calculation |

---

## How to Run

### Step 1 — Generate the dataset
```bash
cd data
python generate_loan_data.py
```
This produces `loan_data.csv` with 5,000 rows across 21 columns.

### Step 2 — Validate data quality
```bash
python data_validation.py
```
Runs 8 automated checks. All checks should pass before loading into SQL.

### Step 3 — Set up the star schema
Open SQL Server Management Studio (SSMS), run `sql/07_create_star_schema.sql` to create all dimension and fact tables, then load `loan_data.csv`.

### Step 4 — Run analytical queries
Execute SQL files 01–06 in the `/sql/` folder to reproduce all analytical outputs used in the dashboard.

### Step 5 — Open Power BI dashboard
Open the `.pbix` file in Power BI Desktop (not pushed to GitHub — binary file). Connect to your SQL Server instance and refresh the data model.

---

## Key Insights from the Dashboard

- **5% of the portfolio (NPA loans) accounts for a disproportionate share of total exposure** — early intervention at SMA-2 stage (61–90 DPD) can prevent write-offs
- **SMA-2 exposure represents the highest-priority collections target** — loans in this bucket are one missed payment away from NPA classification
- **Branch performance varies significantly on collection efficiency** — bottom-quartile branches show 2x higher PAR than top performers, indicating a resource allocation opportunity
- **Gold Loans and Personal Loans show the highest delinquency rates by product type** — suggesting tighter underwriting criteria may be needed for these segments

---

## Author

**Harshpreet Kour**
📧 [LinkedIn](https://linkedin.com/in/harshpreet-k-ba5165195) | 💻 [GitHub](https://github.com/Harshpreet4)


---

*Tools: Power BI · Python · SQL Server · Star Schema · ETL · DAX · Pandas*