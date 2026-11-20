-- =====================================================================
-- 02_analysis_queries.sql
-- Business analysis of California neighbourhoods for retail site planning.
-- Run 01_create_and_load.sql first. Each query is explained in plain
-- English in sql/QUERY_GUIDE.md.
-- Note: MySQL has no MEDIAN function, so these queries use AVG (averages).
-- The Python notebook uses medians, so the numbers differ slightly.
-- =====================================================================
USE house_prices;

-- ---------------------------------------------------------------------
-- Q1. Data quality check: can we trust the data?
-- ---------------------------------------------------------------------
SELECT
    COUNT(*)                                                AS total_rows,
    SUM(total_bedrooms IS NULL)                             AS missing_bedrooms,
    SUM(median_house_value >= 500001)                       AS value_capped_rows,
    SUM(housing_median_age >= 52)                           AS age_capped_rows,
    SUM(ocean_proximity = 'ISLAND')                         AS island_rows,
    SUM(population / households > 10)                       AS odd_people_per_household,
    COUNT(*) - COUNT(DISTINCT longitude, latitude, housing_median_age,
                     total_rooms, population, households,
                     median_income, median_house_value)     AS duplicate_rows
FROM housing;

-- ---------------------------------------------------------------------
-- Q2. Clean view: one reusable "clean" version of the table
--     (business-friendly columns, flags, income quintile).
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_housing AS
SELECT
    id,
    longitude,
    latitude,
    housing_median_age,
    households,
    population,
    median_house_value,
    median_income * 10000                                   AS income_usd,
    total_rooms / households                                AS rooms_per_household,
    population / households                                 AS people_per_household,
    median_house_value / (median_income * 10000)            AS value_to_income,
    CASE WHEN ocean_proximity = 'ISLAND' THEN 'NEAR OCEAN'
         ELSE ocean_proximity END                           AS location,
    (median_house_value >= 500001)                          AS value_capped,
    NTILE(5) OVER (ORDER BY median_income)                  AS income_quintile   -- 1 = lowest 20%, 5 = highest 20%
FROM housing;

SELECT * FROM v_housing ORDER BY id LIMIT 10;

-- ---------------------------------------------------------------------
-- Q3. KPIs by location type, with an index vs the California average (= 100)
-- ---------------------------------------------------------------------
SELECT
    location,
    COUNT(*)                                                AS neighbourhoods,
    SUM(households)                                         AS households,
    ROUND(AVG(income_usd))                                  AS avg_income_usd,
    ROUND(AVG(median_house_value))                          AS avg_home_value,
    ROUND(AVG(value_to_income), 2)                          AS avg_value_to_income,
    ROUND(100 * AVG(median_house_value)
          / (SELECT AVG(median_house_value) FROM housing))  AS value_index_vs_CA
FROM v_housing
GROUP BY location
ORDER BY avg_home_value DESC;

-- ---------------------------------------------------------------------
-- Q4. Income quintiles: how value rises with income, and each
--     quintile's share of all households (window function SUM() OVER ()).
-- ---------------------------------------------------------------------
SELECT
    income_quintile,
    ROUND(MIN(income_usd))                                  AS income_from_usd,
    ROUND(MAX(income_usd))                                  AS income_to_usd,
    ROUND(AVG(median_house_value))                          AS avg_home_value,
    SUM(households)                                         AS households,
    ROUND(100 * SUM(households) / SUM(SUM(households)) OVER (), 1) AS pct_of_all_households
FROM v_housing
GROUP BY income_quintile
ORDER BY income_quintile;

-- ---------------------------------------------------------------------
-- Q5. Segment matrix (pivot): average home value for each income
--     quintile (rows) by location type (columns).
-- ---------------------------------------------------------------------
SELECT
    income_quintile,
    ROUND(AVG(CASE WHEN location = 'INLAND'     THEN median_house_value END)) AS inland,
    ROUND(AVG(CASE WHEN location = '<1H OCEAN'  THEN median_house_value END)) AS within_1h_ocean,
    ROUND(AVG(CASE WHEN location = 'NEAR BAY'   THEN median_house_value END)) AS near_bay,
    ROUND(AVG(CASE WHEN location = 'NEAR OCEAN' THEN median_house_value END)) AS near_ocean
FROM v_housing
GROUP BY income_quintile
ORDER BY income_quintile;

-- ---------------------------------------------------------------------
-- Q6. Assign every neighbourhood to its nearest metro (within 60 km),
--     using a CTE, a CROSS JOIN, a distance function and ROW_NUMBER().
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_neighbourhood_metro AS
WITH distances AS (
    SELECT
        h.id,
        m.metro,
        ST_Distance_Sphere(POINT(h.longitude, h.latitude),
                           POINT(m.longitude, m.latitude)) / 1000 AS distance_km,
        ROW_NUMBER() OVER (PARTITION BY h.id
                           ORDER BY ST_Distance_Sphere(POINT(h.longitude, h.latitude),
                                                       POINT(m.longitude, m.latitude))) AS rn
    FROM housing h
    CROSS JOIN metros m
)
SELECT
    v.*,
    CASE WHEN d.distance_km <= 60 THEN d.metro ELSE 'Rest of CA' END AS metro
FROM v_housing v
JOIN distances d ON d.id = v.id AND d.rn = 1;

SELECT metro, COUNT(*) AS neighbourhoods
FROM v_neighbourhood_metro
GROUP BY metro
ORDER BY neighbourhoods DESC;

-- ---------------------------------------------------------------------
-- Q7. Market ranking: rank metro markets by total yearly income pool
--     (households x income) = rough size of the customer wallet.
-- ---------------------------------------------------------------------
SELECT
    metro,
    SUM(households)                                         AS households,
    ROUND(100 * SUM(households) / SUM(SUM(households)) OVER (), 1) AS pct_of_CA_households,
    ROUND(AVG(income_usd))                                  AS avg_income_usd,
    ROUND(AVG(median_house_value))                          AS avg_home_value,
    ROUND(SUM(households * income_usd) / 1e9, 1)            AS income_pool_bn_usd,
    RANK() OVER (ORDER BY SUM(households * income_usd) DESC) AS market_rank
FROM v_neighbourhood_metro
GROUP BY metro
ORDER BY market_rank;

-- ---------------------------------------------------------------------
-- Q8. "Value pockets": high-income neighbourhoods (top 40%) where homes
--     are still affordable (value under 4x income), by metro.
--     These customers earn well AND have budget left after housing.
-- ---------------------------------------------------------------------
SELECT
    metro,
    COUNT(*)                                                AS high_income_neighbourhoods,
    SUM(value_to_income < 4)                                AS affordable_high_income,
    ROUND(100 * AVG(value_to_income < 4), 1)                AS pct_affordable,
    SUM(CASE WHEN value_to_income < 4 THEN households END)  AS households_in_value_pockets
FROM v_neighbourhood_metro
WHERE income_quintile >= 4
GROUP BY metro
HAVING COUNT(*) >= 50
ORDER BY households_in_value_pockets DESC;
