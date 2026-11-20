# SQL Query Guide (plain English)

This guide explains every query in `02_analysis_queries.sql`: what it does, how it works and what it found. It's written so you can explain each one in an interview.

## How to run it in MySQL Workbench
1. Open Workbench and connect to your local server.
2. **File → Open SQL Script → `sql/01_create_and_load.sql`**, then click the ⚡ lightning icon. It creates the `house_prices` database and its two tables, and loads all 20,640 rows. The last line should show `rows_loaded = 20640`.
3. Open `sql/02_analysis_queries.sql`. Put your cursor inside one query and press **Ctrl+Enter** to run just that query. Run them in order, because Q2 and Q6 create *views* that later queries use.

> **Why averages, not medians?** MySQL has no built-in `MEDIAN()`. The SQL uses `AVG()`, so its numbers are a bit higher than the medians in the Python notebook. A few very expensive areas pull averages up. The *patterns* are identical.
>
> The expected results below come from testing the same queries in a SQLite copy of the data. MySQL should match them. The `NTILE` quintile boundaries could differ by a few rows where incomes tie.

---

## The two tables (from `01_create_and_load.sql`)
- **`housing`**: one row per neighbourhood (20,640 rows). `id` is a primary key, a unique number for each row. `total_bedrooms` allows `NULL` because 207 values are missing.
- **`metros`**: 6 rows giving the centre point (latitude, longitude) of the big cities used to define metro markets.

**Why INSERT statements instead of importing the CSV?** MySQL's `LOAD DATA INFILE` often fails because of security settings on file paths. Plain `INSERT` statements always run in Workbench. The script was generated from the CSV with Python, 1,000 rows per statement.

---

## Q1. Data quality check
**Business question:** Can we trust this data before we analyse it?

**How it works**
- `COUNT(*)` counts every row.
- `SUM(total_bedrooms IS NULL)`: in MySQL, a true/false test counts as 1 or 0, so adding them up *counts* the rows where the test is true. The same trick counts capped values, ISLAND rows and odd people-per-household values.
- `COUNT(*) - COUNT(DISTINCT <all columns>)` gives the number of duplicate rows. If every row is unique, the two counts are equal and the result is 0.

**Result:** 20,640 rows · 207 missing bedroom counts (1%) · 965 home values capped at $500,001 · 1,273 ages capped at 52 · 5 ISLAND rows · 37 odd people-per-household values · **0 duplicates**.

**What to say:** "I always check quality first. The data is clean, with no duplicates and only 1% missing, but top values are capped, so the richest areas are understated."

---

## Q2. Clean view `v_housing`
**Business question:** Can we build one clean, readable version of the table that every later query reuses?

**How it works**
- A **VIEW** is a saved query that behaves like a table. It doesn't copy any data.
- It adds business-friendly columns:
  - `income_usd`: income × 10,000, turned into real dollars.
  - `rooms_per_household` and `people_per_household`: ratios, because raw totals depend on how big the neighbourhood is.
  - `value_to_income`: home value ÷ income, an affordability KPI.
- `CASE WHEN ocean_proximity = 'ISLAND' THEN 'NEAR OCEAN'` merges the 5 ISLAND rows into NEAR OCEAN, because 5 rows are too few for their own segment.
- `(median_house_value >= 500001) AS value_capped` is a 1/0 flag. We keep those rows but mark them.
- `NTILE(5) OVER (ORDER BY median_income)` is a **window function**. It sorts all rows by income and splits them into 5 equal groups (quintiles): 1 = poorest 20%, 5 = richest 20%.

**Result:** a view with 14 tidy columns. The preview shows the first 10 neighbourhoods.

**What to say:** "I put the cleaning logic in one view so every query uses the same definitions. One source of truth."

---

## Q3. KPIs by location type
**Business question:** How do coastal and inland markets compare?

**How it works**
- `GROUP BY location` gives one summary row per location type.
- `SUM(households)` gives market size, and `AVG(...)` gives the typical income, home value and affordability.
- `value_index_vs_CA`: each group's average value ÷ the whole state's average × 100. 100 is average, 125 is 25% above average. The state average comes from a **subquery** (a query inside a query).

**Result**

| location | households | avg income | avg home value | value ÷ income | index vs CA |
|---|---|---|---|---|---|
| NEAR BAY | 1.12M | $41.7k | $259k | 6.8 | 125 |
| NEAR OCEAN | 1.33M | $40.0k | $250k | 6.7 | 121 |
| <1H OCEAN | 4.73M | $42.3k | $240k | 6.2 | 116 |
| INLAND | 3.13M | $32.1k | $125k | 4.1 | 60 |

**What to say:** "Inland homes are 40% below the state average, coastal ones are 16–25% above, and the coast is also less affordable relative to income."

---

## Q4. Income quintiles and share of households
**Business question:** How much does home value rise as income rises, and how big is each income group?

**How it works**
- `GROUP BY income_quintile`, with `MIN`/`MAX` showing each group's income range.
- `SUM(SUM(households)) OVER ()` is a window function on top of a group total. The inner `SUM` is each quintile's households, and the outer `SUM ... OVER ()` adds those up across *all* quintiles. Dividing the two gives each group's **% share**, all in one query.

**Result:** the average home value climbs steadily from **$118k** (quintile 1, incomes up to $23.5k) to **$335k** (quintile 5, $51k+), **2.8x** higher. Each quintile holds about 18–21% of households.

**What to say:** "Home value rises with every step in income, which confirms income as the main driver."

---

## Q5. Segment matrix (pivot table)
**Business question:** At the *same* income level, does location still change home value?

**How it works:** this is **conditional aggregation**. `AVG(CASE WHEN location = 'INLAND' THEN median_house_value END)` averages only the inland rows, because every other row becomes `NULL` and `AVG` skips NULLs. Repeating it for each location turns rows into columns, which is how you build a pivot table in SQL.

**Result (average home value)**

| quintile | inland | <1H ocean | near bay | near ocean |
|---|---|---|---|---|
| 1 | $82k | $158k | $151k | $143k |
| 3 | $130k | $215k | $246k | $229k |
| 5 | $242k | $339k | $368k | $385k |

**What to say:** "Even within the same income group, coastal homes are worth about 1.5–2x inland ones, so location matters on top of income."

---

## Q6. Assign each neighbourhood to its nearest metro
**Business question:** Which big-city market (trade area) does each neighbourhood belong to?

**How it works, step by step**
1. **`WITH distances AS (...)`** is a **CTE** (Common Table Expression), a named temporary result that makes a long query readable.
2. **`CROSS JOIN metros`** pairs every neighbourhood with all 6 cities, giving 20,640 × 6 = 123,840 pairs.
3. **`ST_Distance_Sphere(POINT(lon, lat), POINT(lon, lat))`** is MySQL's built-in function for the straight-line distance on the Earth's surface, in metres. Dividing by 1000 gives km.
4. **`ROW_NUMBER() OVER (PARTITION BY h.id ORDER BY distance)`** numbers the 6 cities for each neighbourhood from nearest (1) to farthest (6). `PARTITION BY` restarts the numbering for every neighbourhood.
5. We keep only `rn = 1`, the nearest city. If it's within **60 km**, that's the metro; otherwise the neighbourhood is labelled `Rest of CA`.
6. The result is saved as the view `v_neighbourhood_metro`.

**Result:** Los Angeles 7,354 neighbourhoods · Rest of CA 5,835 · San Francisco 2,601 · San Jose 1,554 · San Diego 1,551 · Sacramento 1,086 · Fresno 659. This matches the Python notebook exactly.

**What to say:** "I turned raw coordinates into trade areas, the way a retailer thinks about markets, using a CTE, a cross join, a distance function and ROW_NUMBER to pick the nearest city."

---

## Q7. Market ranking by income pool
**Business question:** Which metro markets have the most total customer spending power?

**How it works**
- **Income pool** = `SUM(households × income)`: the total yearly income in the market, a rough size of the customer wallet. Divided by 1e9 to show billions.
- `RANK() OVER (ORDER BY income_pool DESC)` gives rank 1 to the biggest market. `RANK` gives tied markets the same rank.
- `SUM(SUM(households)) OVER ()` again gives each metro's % share of the state's households.

**Result**

| rank | metro | % of CA households | avg income | income pool |
|---|---|---|---|---|
| 1 | Los Angeles | 36.2% | $40.9k | $151.9bn |
| 2 | Rest of CA | 26.8% | $33.0k | $94.2bn |
| 3 | San Francisco | 12.3% | $42.2k | $53.6bn |
| 4 | San Jose | 7.8% | $51.8k | $40.3bn |
| 5 | San Diego | 8.2% | $37.8k | $32.0bn |
| 6 | Sacramento | 5.9% | $34.7k | $21.3bn |
| 7 | Fresno | 2.6% | $28.9k | $7.8bn |

**What to say:** "LA is the biggest market by far, about 2.8x San Francisco. San Jose has the richest households but a much smaller market."

---

## Q8. "Value pockets": high-income areas where housing is still affordable
**Business question:** Where are customers who earn well *and* still have budget left after housing? These are attractive for a value-plus-premium store.

**How it works**
- `WHERE income_quintile >= 4` keeps only the top 40% of neighbourhoods by income.
- `SUM(value_to_income < 4)` counts the ones where homes cost less than 4 years of income.
- `AVG(value_to_income < 4)` is the *share* of them, because the average of 1s and 0s is a percentage.
- `SUM(CASE WHEN ... THEN households END)` adds up the households in those pockets.
- `HAVING COUNT(*) >= 50` drops metros with too few high-income areas to trust. `HAVING` filters *after* grouping, while `WHERE` filters *before*.

**Result**

| metro | high-income areas | % affordable | households in value pockets |
|---|---|---|---|
| Rest of CA | 1,528 | 48% | 387k |
| Los Angeles | 3,261 | 19% | 254k |
| Sacramento | 360 | **68%** | 141k |
| San Diego | 622 | 40% | 115k |
| San Francisco | 1,271 | 16% | 88k |
| San Jose | 1,100 | 11% | 46k |
| Fresno | 114 | 98% | 46k |

**What to say:** "Sacramento stands out: two-thirds of its high-income neighbourhoods are still affordable, so customers there have more money left to spend. In the Bay Area, high incomes are largely absorbed by housing costs."

---

## SQL concepts covered (quick list for the interview)
`CREATE TABLE` with a primary key and `NULL`s · `INSERT` · `VIEW` · `CASE WHEN` · `GROUP BY` / `HAVING` · aggregates (`COUNT`, `SUM`, `AVG`, `MIN`, `MAX`) · counting with true/false sums · subquery · CTE (`WITH`) · `CROSS JOIN` and `JOIN` · window functions (`NTILE`, `ROW_NUMBER`, `RANK`, `SUM() OVER ()`) · `PARTITION BY` · a spatial function (`ST_Distance_Sphere`) · pivoting with conditional aggregation.
