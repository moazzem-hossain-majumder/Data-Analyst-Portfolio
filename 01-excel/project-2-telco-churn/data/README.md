# Data notes

- **Original dataset:** Telco Customer Churn (IBM sample data), Kaggle: https://www.kaggle.com/datasets/blastchar/telco-customer-churn
- **File:** `WA_Fn-UseC_-Telco-Customer-Churn.csv` (7,043 rows x 21 columns).
- **Provenance:** this copy was taken from a public GitHub repository that mirrors the Kaggle file, because Kaggle itself could not be reached when the project was built. Before publishing, download the file directly from the Kaggle page above and confirm it matches (same row count and columns, 1,869 customers with Churn = Yes, and monthly charges adding up to $456,116.60). Replace this copy with the official download if there is any difference.
- **Licence:** check the licence/terms on the Kaggle dataset page before redistributing the CSV. If in doubt, delete the CSV from this folder and keep only the link.
- **Known quirk:** 11 customers have a blank space in `TotalCharges`; all have tenure 0 (see `Cleaning_Log` sheet).
