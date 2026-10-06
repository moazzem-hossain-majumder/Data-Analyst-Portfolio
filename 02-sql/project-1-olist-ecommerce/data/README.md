# Data

The CSV files are **not stored in this repository** (about 60 MB). Download them and place them in this folder.

## Source
Brazilian E-Commerce Public Dataset by Olist, on Kaggle:
https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce

Download and unzip, then copy these 8 files into `data/`:

| File | Rows expected | Loaded into |
|---|---|---|
| `olist_customers_dataset.csv` | 99,441 | `customers` |
| `olist_orders_dataset.csv` | 99,441 | `orders` |
| `olist_order_items_dataset.csv` | 112,650 | `order_items` |
| `olist_order_payments_dataset.csv` | 103,886 | `order_payments` |
| `olist_order_reviews_dataset.csv` | see note below | `order_reviews` |
| `olist_products_dataset.csv` | 32,951 | `products` |
| `olist_sellers_dataset.csv` | 3,095 | `sellers` |
| `product_category_name_translation.csv` | 71 | `category_translation` |

`olist_geolocation_dataset.csv` (about 1 million rows) is not used in this project.

## Provenance note (please read)
While building this project Kaggle could not be reached, so the files were taken from public GitHub copies of the same dataset. Seven of the eight files match the published row counts exactly. The reviews file in that copy has **100,000 rows** (99,441 orders, 99,173 distinct `review_id`s), while Kaggle's current version lists 99,224 rows, so it is probably an earlier release of the file.

Review-based results (queries Q35, Q40-Q42, Q29, Q44) may therefore shift slightly when you use the official download. All queries read reviews through the `v_order_review` view, which keeps one (the latest) review per order, so they work with either version.

Before publishing, download the official files from Kaggle, re-run `./run_all.sh` and update the numbers in the README if they changed. Also check the dataset's licence on the Kaggle page.
