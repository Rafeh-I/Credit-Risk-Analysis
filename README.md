# Berka Credit Risk Portfolio

End-to-end credit risk project on the [Berka dataset](https://www.kaggle.com/datasets/nitamontana/berka-dataset) — a real Czech bank's loan portfolio from 1993–1998. Demonstrates the full model pipeline: SQL feature engineering, exploratory analysis, machine learning, WoE scorecard, two-stage decisioning, and a Power BI dashboard.

---

## Project Structure

```
Credit-Risk-Analysis/
├── sql/
│   ├── 01_schema.sql           # Table definitions and constraints
│   ├── 02_load.sql             # Raw data loading
│   ├── 04_features.sql         # Full feature engineering query
│   └── 05_descriptives.sql     # Exploratory descriptive statistics
├── jupyter_notebooks/
│   ├── 01_modelling.ipynb      # EDA, LR / RF / XGBoost, SHAP, P&L analysis
│   └── woe_binning.ipynb       # WoE scorecard + two-stage model
├── power_bi/
│   └── berka_dashboards.pbix   # Power BI dashboard (3 pages)
├── requirements.txt
└── README.md
```

---

## Dataset

- **682 loans** across 8 Czech regions, 1993–1998
- **76 defaults** (11.1% default rate)
- Raw tables: `loan`, `account`, `transaction`, `client`, `disp`, `district`
- Source: [PKDD 1999 Discovery Challenge](https://www.kaggle.com/datasets/nitamontana/berka-dataset)
---

## Pipeline Overview

### 1. Schema & Data Loading (SQL)
Raw Berka CSV files loaded into Postgres. Tables created with appropriate data types, primary keys, and foreign key relationships across `loan`, `account`, `transaction`, `client`, `disp`, and `district`.

### 2. Descriptive Statistics (SQL)
Exploratory analysis on the raw tables: loan volume and default rate by year, region, duration, and loan size; transaction volume and balance trends by account; district-level demographic summaries.

### 3. Feature Engineering (SQL)
36 features computed from raw transactions directly in Postgres and stored in a `loan_features` table:

| Feature Group | Examples |
|---|---|
| Balance behaviour | `avg_balance_3m/6m/12m`, `min_balance_6m`, `sd_balance_6m`, `balance_at_grant` |
| Cash flow | `monthly_inflow_3m/6m`, `monthly_outflow_3m/6m`, `cash_out_6m` |
| Derived ratios | `payment_to_inflow_6m`, `loan_to_annual_salary`, `inflow_outflow_ratio_6m`, `cash_share_of_outflow_6m` |
| Credit behaviour | `n_credits_6m`, `n_debits_6m`, `n_penalty_interest_12m` |
| Loan & account | `loan_amount`, `duration`, `account_age_months`, `age_at_loan` |
| District | `avg_salary`, `unemployment_rate_95`, `entrepreneurs_per_1000`, `urban_ratio` |

### 4. Modelling (Python)

#### Logistic Regression (baseline)
- Pipeline: median imputation → standard scaling → L2 logistic (C=0.01)
- Bootstrap confidence intervals on coefficients to identify statistically significant predictors
- **CV ROC-AUC: 0.895 | PR-AUC: 0.658**

#### Random Forest
- 500 trees, `min_samples_leaf=5`, `class_weight="balanced_subsample"`
- **CV ROC-AUC: 0.910 | PR-AUC: 0.676**

#### XGBoost
- 300 trees, `max_depth=3`, `learning_rate=0.05`, `scale_pos_weight=8`
- SHAP values for feature importance and effect direction
- **CV ROC-AUC: 0.918 | PR-AUC: 0.679** ← best single model

#### WoE Scorecard (optbinning)
- 36 features ranked by Information Value (IV); 10 selected (IV > 0.1, non-redundant)
- Monotonic binning via `BinningProcess`, logistic regression on WoE-transformed features
- PDO-odds scaling: 600 points = 1:1 odds, 20 points doubles odds
- Score range: 578–718, mean 671
- **CV ROC-AUC: 0.878 | PR-AUC: 0.606**
- Interpretable by design — industry standard for retail credit

#### Two-Stage Model
- Stage 1 — Scorecard filter: auto-decline < 620, borderline 620–650, auto-approve > 650
- Stage 2 — XGBoost on 116 borderline loans: decline if predicted PD > 0.25
- Nested cross-validation for honest AUC estimate
- **CV ROC-AUC: 0.823 | PR-AUC: 0.505**
- Lower AUC is expected: optimised for a specific decision boundary, not ranking

---

## Top SHAP Features (XGBoost)

| Feature | Mean SHAP |
|---|---|
| Min Balance (6M) | 1.116 |
| Cash Share of Outflow (6M) | 1.029 |
| Min Balance (3M) | 0.643 |
| Account Age (Months) | 0.443 |
| No. of Credits (6M) | 0.433 |

Minimum balance dominates — borrowers who run their account close to zero are significantly higher risk regardless of income level.

---

## Business Results

Cut-off = 0.15 | Assumptions: 8% annual interest rate, 40% LGD (Loss Given Default)

| Model | Net Profit (CZK) | Defaults Avoided | Catch Rate | Good Loans Lost |
|---|---|---|---|---|
| Approve All (baseline) | 19,568,364 | 0 | 0.0% | 0 |
| Logistic Regression | 19,646,409 | 57 | 75.0% | 69 |
| XGBoost | 21,856,472 | 59 | 77.6% | 61 |
| Two-Stage | 21,817,647 | 49 | 64.5% | 42 |
| Random Forest | 14,949,623 | 71 | 93.4% | 195 |

**XGBoost** delivers the highest net profit (+11.7% vs baseline). **Random Forest** has the highest catch rate but declines 195 good customers, destroying more interest income than it saves in avoided losses. **Two-Stage** is the best risk-adjusted choice: near-identical profit to XGBoost with the fewest good loans lost (42 vs 61).

---

## Power BI Dashboard

Three-page dashboard connected live to Postgres:

1. **Portfolio Overview** — KPI cards (682 loans, 76 defaults, 11.1% default rate), default rate by score band and gender, loan volume and default rate trends 1993–1998
2. **Model Comparison** — AUC comparison table, business P&L table, catch rate chart, net profit chart
3. **Credit Risk Analysis** — Default rate by region, loan size × term, loan term; gender slicer

---

## Setup

```bash
# 1. Clone
git clone https://github.com/Rafeh-I/Credit-Risk-Analysis.git
cd Credit-Risk-Analysis

# 2. Create virtual environment
python -m venv venv
source venv/bin/activate        # Windows: venv\Scripts\activate

# 3. Install dependencies
pip install -r requirements.txt

# 4. Set environment variable
echo "DB_URL=postgresql://user:password@localhost:5432/berka" > .env

# 5. Load data into Postgres
psql -d berka -f sql/01_schema.sql
psql -d berka -f sql/02_load.sql
psql -d berka -f sql/04_features.sql

# 6. Open notebooks
jupyter lab
```

---

## Notes

- P&L uses assumed 8% annual simple interest rate — Berka dataset contains no interest rate data
- LGD assumed at 40% — standard retail unsecured lending assumption
- 1998 data is partial (loans still active at snapshot date), which slightly deflates the default rate for that year
- WoE Scorecard excluded from standalone P&L comparison — it functions as Stage 1 of the two-stage model, not as an independent decisioning model
  
