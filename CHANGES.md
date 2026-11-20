# Change log: clean-up for portfolio (2026-11-20)

## Removed
| What | Why |
|---|---|
| `Gurgaon_housing.xlsx` (3 copies: root, `Housing/`, `housing prices/`) | All three files had column headers and no rows. No other file mentioned Gurgaon. |

## Moved to `archive/` (kept unchanged, for reference)
| From | To | What it is |
|---|---|---|
| 7 notebooks in the root | `archive/original_notebooks/` | Original course notebooks: first look, test set, visualising, categorical values, scaling, preprocessing, pipelines |
| `.ipynb_checkpoints/` | `archive/original_notebooks/.ipynb_checkpoints/` | Jupyter's automatic backups (not pushed to GitHub) |
| `housing prices/` | `archive/housing prices/` | Original training script `main.py` (Random Forest), `main_old.py` (3-model comparison), `input.csv` / `output.csv` predictions, `model.pkl` / `pipeline.pkl` |
| `Housing/main.py`, `Housing/housing.csv`, `Housing/.vscode/` | `archive/Housing/` | An earlier, unfinished version of the script |
| `housing.csv` (root) | `data/housing.csv` | The dataset, now in a `data/` folder |

**Left in place:** `Housing/.venv/`, an old Python virtual environment. Windows refused to move it (another program had it open, probably VS Code). It isn't needed, and it's excluded from Git. You can delete it later.

**Not pushed to GitHub:** `model.pkl` (144 MB). GitHub blocks files over 100 MB, and running the notebook rebuilds the model.

## Added
| File | What it contains | Why |
|---|---|---|
| `house_prices_analysis.ipynb` | One clean notebook: business question → quality checks → cleaning → KPIs → map → drivers → segments → metro ranking → model comparison → feature importance → what-if → findings → recommendations → limitations | Replaces 7 repetitive course notebooks with one story an interviewer can follow. Each step reloaded the data and repeated earlier code. |
| `data/housing_clean.csv` | Cleaned data with new columns (income in $, ratios, flags, income band, metro) | Reusable output of the cleaning step |
| `images/01–06_*.png` | 6 charts, each titled with its finding | Used in the README and for slides |
| `sql/01_create_and_load.sql` | Creates the `house_prices` database, the `housing` and `metros` tables, and inserts all 20,640 rows | Lets the analysis be repeated in MySQL Workbench |
| `sql/02_analysis_queries.sql` | 8 business queries | Shows SQL skills that analyst roles require |
| `sql/QUERY_GUIDE.md` | A plain-English explanation and the results of each query | Interview preparation |
| `README.md` | Case-study write-up: problem, findings, recommendations, method, results, limitations | The first thing a recruiter reads |
| `requirements.txt`, `.gitignore` | Python packages; files kept out of Git | So the repo installs cleanly and stays small |

## Fixes compared with the original work
- **Map axes were swapped.** The old notebook plotted latitude on x and longitude on y, so California appeared rotated. Fixed.
- **No conclusions.** The old notebooks had only code. Every section now explains what it found.
- **The model was never evaluated on the test set inside the notebooks.** Test-set accuracy is now reported against a baseline.
- **Missing bedrooms:** the old version filled them with one median value (433). They're now filled with a bedrooms-per-room ratio, so larger neighbourhoods get more bedrooms.
