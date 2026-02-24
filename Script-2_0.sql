/* Проект первого модуля: анализ данных для агентства недвижимости
 * Часть 2. Решаем ad hoc задачи
 * 
 * Автор: Копанев Данил Романович
 * Дата: 10.12.2025
*/



-- Задача 1: Время активности объявлений
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS(
    SELECT
        PERCENTILE_CONT(0.99)WITHIN GROUP(ORDER BY total_area)AS total_area_limit,
        PERCENTILE_DISC(0.99)WITHIN GROUP(ORDER BY rooms)AS rooms_limit,
        PERCENTILE_DISC(0.99)WITHIN GROUP(ORDER BY balcony)AS balcony_limit,
        PERCENTILE_CONT(0.99)WITHIN GROUP(ORDER BY ceiling_height)AS ceiling_height_limit_h,
        PERCENTILE_CONT(0.01)WITHIN GROUP(ORDER BY ceiling_height)AS ceiling_height_limit_l
    FROM real_estate.flats
),
-- Найдём id объявлений, которые не содержат выбросы, также оставим пропущенные данные:
filtered_id AS(
    SELECT id
    FROM real_estate.flats
    WHERE
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    ),
prepared AS(
    SELECT
        a.id,
        CASE
            WHEN c.city='Санкт-Петербург' THEN 'Saint Petersburg'
            ELSE 'Leningrad Region'
        END AS region,
        CASE
            WHEN a.days_exposition IS NULL THEN 'non category'
            WHEN a.days_exposition BETWEEN 1 AND 30 THEN '1-30 days'
            WHEN a.days_exposition BETWEEN 31 AND 90 THEN '31-90 days'
            WHEN a.days_exposition BETWEEN 91 AND 180 THEN '91-180 days'
            WHEN a.days_exposition>=181 THEN '181+ days'
        END AS activity_segment,
        a.first_day_exposition,
        a.days_exposition,
        a.last_price,
        f.total_area,
        f.rooms,
        f.balcony,
        f.floors_total,
        f.ceiling_height,
        CASE
            WHEN f.total_area IS NOT NULL AND f.total_area<>0
            THEN a.last_price/f.total_area
            ELSE NULL
        END AS price_per_sqm,
        f.is_apartment,
        f.open_plan,
        f.airports_nearest,
        f.parks_around3000,
        f.ponds_around3000
    FROM real_estate.advertisement AS a
    JOIN real_estate.flats AS f USING (id)
    JOIN real_estate.city AS c USING (city_id)
    JOIN real_estate.type AS t USING (type_id)
    WHERE
        a.id IN(SELECT id FROM filtered_id) -- без аномалий
        AND t.type='город' -- только города
        AND a.first_day_exposition BETWEEN DATE '2015-01-01' AND DATE '2018-12-31' -- с 2015 по 2018 годы  вкл
),
region_totals AS(
    SELECT
        region,
        COUNT(*)AS total_ads_region
    FROM prepared
    GROUP BY region
)
-- Итоговая сводная таблица
SELECT
    p.region AS region,
    p.activity_segment AS activity_segment,
    COUNT(*)AS ads_count,
    ROUND(100.0 * COUNT(*) / rt.total_ads_region, 0) AS ads_share_pct,
    ROUND(AVG(p.price_per_sqm::int), 0) AS avg_price_per_sqm,
    ROUND(100.0 * AVG(
    				CASE
	    				WHEN p.rooms = 0 THEN 1
	    				ELSE 0
	    			END), 1) AS studios_share_pct,
    ROUND(AVG(p.ceiling_height::int), 2) AS avg_ceiling_height,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.rooms) AS median_rooms,
    PERCENTILE_CONT(0.5)WITHIN GROUP(ORDER BY p.balcony)AS median_balconies,
    PERCENTILE_CONT(0.5)WITHIN GROUP(ORDER BY p.floors_total)AS median_floors_total,
    ROUND(100.0*AVG(
    				CASE
	    				WHEN p.is_apartment=1 THEN 1 
	    				ELSE 0 
	    			END), 1) AS apartments_share_pct, -- Доля апартаментов среди объявлений сегмента, %
    ROUND(100.0*AVG(
    				CASE 
	    				WHEN p.open_plan=1 THEN 1 
	    				ELSE 0 
	    			END), 1) AS open_plan_share_pct, -- Доля квартир с открытой планировкой, %
	ROUND(AVG(p.airports_nearest)::int /1000, 2)AS avg_airport_distance_km, -- Среднее расстояние до аэропорта в км
    PERCENTILE_CONT(0.5)WITHIN GROUP(ORDER BY p.parks_around3000)AS median_parks_3km, -- Медиана числа парков в радиусе 3 км
    PERCENTILE_CONT(0.5)WITHIN GROUP(ORDER BY p.ponds_around3000)AS median_ponds_3km -- Медиана числа водоёмов в радиусе 3 км
FROM prepared AS p
JOIN region_totals AS rt USING (region)
GROUP BY p.region, p.activity_segment, rt.total_ads_region
ORDER BY
    p.region DESC,
    CASE p.activity_segment
        WHEN '1-30 days' THEN 1
        WHEN '31-90 days' THEN 2
        WHEN '91-180 days' THEN 3
        WHEN '181+ days' THEN 4
        WHEN 'non category' THEN 5
    END;

-- выполнил set lc_time = 'ru_RU';

-- Задача 2: Сезонность объявлений
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_CONT(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),
-- Найдём id объявлений, которые не содержат выбросы, также оставим пропущенные данные:
filtered_id AS (
    SELECT id
    FROM real_estate.flats
    WHERE
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
),
prepared AS (
    SELECT
        a.id,
        a.first_day_exposition::date AS publish_date,
        a.days_exposition::int AS days_exposition,
        EXTRACT(MONTH FROM a.first_day_exposition::date) AS publish_month_num,
        -- дату снятия считаем только при известной длительности размещения
        CASE
            WHEN a.days_exposition IS NOT NULL
            THEN (a.first_day_exposition::date + a.days_exposition::int)
            ELSE NULL
        END AS remove_date,
        -- месяц снятия считаем только при известной длительности размещения
        CASE
            WHEN a.days_exposition IS NOT NULL
            THEN EXTRACT(MONTH FROM a.first_day_exposition::date + a.days_exposition::int)
            ELSE NULL
        END AS remove_month_num,
        a.last_price,
        f.total_area,
        CASE
            WHEN f.total_area IS NOT NULL AND f.total_area != 0
            THEN a.last_price / f.total_area
            ELSE NULL
        END AS price_per_sqm
    FROM real_estate.advertisement AS a
    JOIN real_estate.flats AS f USING (id)
    JOIN real_estate.type AS t USING (type_id)
    WHERE
        a.id IN (SELECT id FROM filtered_id)
        AND t.type = 'город'
        AND a.first_day_exposition::date BETWEEN DATE '2015-01-01' AND DATE '2018-12-31'
),
-- статистика по месяцам публикации: считаем все объявления
by_publish AS (
    SELECT
        publish_month_num AS month_num,
        COUNT(*) AS publish_count,
        AVG(price_per_sqm) AS publish_avg_price_sqm,
        AVG(total_area) AS publish_avg_area
    FROM prepared
    GROUP BY publish_month_num
),
-- статистика по месяцам снятия: считаем только объявления с известным месяцем снятия
by_remove AS (
    SELECT
        remove_month_num AS month_num,
        COUNT(*) AS remove_count,
        AVG(price_per_sqm) AS remove_avg_price_sqm,
        AVG(total_area) AS remove_avg_area
    FROM prepared
    WHERE remove_month_num IS NOT NULL
    GROUP BY remove_month_num
),
-- общие количества для расчёта долей
totals AS (
    SELECT
        COUNT(*) AS total_published_count,
        COUNT(*) FILTER (WHERE remove_month_num IS NOT NULL) AS total_removed_count
    FROM prepared
),
-- объединяем данные по публикациям/снятиям, считаем доли и ранги
with_shares AS (
    SELECT
        m.month_num,
        COALESCE(bp.publish_count, 0) AS publish_count,
        COALESCE(br.remove_count, 0) AS remove_count,
        COALESCE(bp.publish_avg_price_sqm, 0) AS publish_avg_price_sqm,
        COALESCE(br.remove_avg_price_sqm, 0) AS remove_avg_price_sqm,
        COALESCE(bp.publish_avg_area, 0) AS publish_avg_area,
        COALESCE(br.remove_avg_area, 0) AS remove_avg_area,
        -- доля опубликованных объявлений по месяцу
        CASE
            WHEN (SELECT total_published_count FROM totals) > 0
            THEN ROUND(100.0 * COALESCE(bp.publish_count, 0) / (SELECT total_published_count FROM totals), 1)
            ELSE 0
        END AS publish_share_pct,
        -- доля снятых объявлений по месяцу
        CASE
            WHEN (SELECT total_removed_count FROM totals) > 0
            THEN ROUND(100.0 * COALESCE(br.remove_count, 0) / (SELECT total_removed_count FROM totals), 1)
            ELSE 0
        END AS remove_share_pct,
        -- ранг месяца по количеству опубликованных
        RANK() OVER (ORDER BY COALESCE(bp.publish_count, 0) DESC) AS publish_rank,
        -- ранг месяца по количеству снятых
        RANK() OVER (ORDER BY COALESCE(br.remove_count, 0) DESC) AS remove_rank
    FROM (
        SELECT month_num
        FROM by_publish
        UNION
        SELECT month_num
        FROM by_remove
    ) AS m
    LEFT JOIN by_publish AS bp USING (month_num)
    LEFT JOIN by_remove  AS br USING (month_num)
)
SELECT
    ws.month_num AS month_num,
    TO_CHAR(TO_DATE(ws.month_num::text, 'MM'), 'TMmon') AS month_name,
    ws.publish_count AS publish_count,
    ws.remove_count AS remove_count,
    ws.publish_share_pct AS publish_share_pct,
    ws.remove_share_pct AS remove_share_pct,
    ROUND(ws.publish_avg_price_sqm::numeric) AS publish_avg_price_sqm, -- решил использовать numeric, чтобы не отсечь дроби
    ROUND(ws.remove_avg_price_sqm::numeric) AS remove_avg_price_sqm,
    ROUND(ws.publish_avg_area::numeric, 1) AS publish_avg_area,
    ROUND(ws.remove_avg_area::numeric, 1) AS remove_avg_area,
    ws.publish_rank AS publish_rank,
    ws.remove_rank AS remove_rank
FROM with_shares AS ws
ORDER BY ws.month_num;
