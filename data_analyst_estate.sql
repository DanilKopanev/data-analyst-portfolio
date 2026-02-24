/* Проект первого модуля: анализ данных для агентства недвижимости
 * Часть 2. Решаем ad hoc задачи
 * 
 * Автор: Копанев Данил Романович
 * Дата: 09.12.2025
*/



-- Задача 1: Время активности объявлений
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
prepared AS (
    SELECT
        a.id,
        CASE
            WHEN c.city = 'Санкт-Петербург' THEN 'Санкт-Петербург'
            ELSE 'ЛенОбл'
        END AS region,
        CASE
            WHEN a.days_exposition IS NULL THEN 'non category'
            WHEN a.days_exposition BETWEEN 1 AND 30 THEN '1-30 days'
            WHEN a.days_exposition BETWEEN 31 AND 90 THEN '31-90 days'
            WHEN a.days_exposition BETWEEN 91 AND 180 THEN '91-180 days'
            WHEN a.days_exposition >= 181 THEN '181+ days'
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
            WHEN f.total_area IS NOT NULL AND f.total_area != 0
            THEN a.last_price / f.total_area
            ELSE NULL
        END AS price_per_sqm
    FROM real_estate.advertisement AS a
    JOIN real_estate.flats AS f USING (id)
    JOIN real_estate.city AS c USING (city_id)
    JOIN real_estate.type AS t USING (type_id)
    WHERE
        a.id IN (SELECT id FROM filtered_id) -- без аномалий
        AND t.type = 'город' -- только города
        AND a.first_day_exposition BETWEEN DATE '2015-01-01' AND DATE '2018-12-31'-- с 2015 по 2018 годы  вкл
),
-- Общее количество объявлений по каждому региону (для доли)
region_totals AS (
    SELECT
        region,
        COUNT(*) AS total_ads_region
    FROM prepared
    GROUP BY region
)
-- Итоговая сводная таблица
SELECT
    p.region AS "Регион",
    p.activity_segment AS "Сегмент активности",
    COUNT(*) AS "Количество объявлений",
    ROUND(100.0 * COUNT(*) / rt.total_ads_region, 0) AS "Доля объявлений, %",
    ROUND(AVG(p.price_per_sqm::int), 0) AS "Средняя стоимость кв. метра",
    ROUND(AVG(p.total_area::int), 0)   AS "Средняя площадь",
    ROUND(100.0 * AVG(
    				CASE
	    				WHEN p.rooms = 0 THEN 1
	    				ELSE 0
	    			END
	    			), 1) AS "Доля студий, %",
    ROUND(AVG(p.ceiling_height::int), 2) AS "Средняя высота потолка",
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.rooms) AS "Медиана кол-ва комнат",
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.balcony) AS "Медиана кол-ва балконов",
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.floors_total) AS "Медиана этажности"
FROM prepared AS p
JOIN region_totals AS rt USING (region)
GROUP BY p.region, p.activity_segment, rt.total_ads_region
ORDER BY
    p.region DESC,
    CASE p.activity_segment
        WHEN '1-30 days'   THEN 1
        WHEN '31-90 days'  THEN 2
        WHEN '91-180 days' THEN 3
        WHEN '181+ days'   THEN 4
        WHEN 'non category' THEN 5
    END;



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
        (a.first_day_exposition::date + a.days_exposition::int) AS remove_date,
        EXTRACT( MONTH FROM a.first_day_exposition::date + a.days_exposition::int) AS remove_month_num,
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
        AND a.days_exposition IS NOT NULL -- без активных объявлений
),
by_publish AS (
    SELECT
        publish_month_num AS month_num, -- решил сделать общее поле для удобного юниона
        COUNT(*) AS publish_cnt,
        AVG(price_per_sqm) AS publish_avg_price_sqm,
        AVG(total_area) AS publish_avg_area
    FROM prepared
    GROUP BY publish_month_num
),
by_remove AS (
    SELECT
        remove_month_num AS month_num,
        COUNT(*) AS remove_cnt,
        AVG(price_per_sqm) AS remove_avg_price_sqm,
        AVG(total_area) AS remove_avg_area
    FROM prepared
    GROUP BY remove_month_num
)
SELECT
    m.month_num AS "Номер месяца",
    CASE m.month_num
        WHEN 1  THEN 'Январь'
        WHEN 2  THEN 'Февраль'
        WHEN 3  THEN 'Март'
        WHEN 4  THEN 'Апрель'
        WHEN 5  THEN 'Май'
        WHEN 6  THEN 'Июнь'
        WHEN 7  THEN 'Июль'
        WHEN 8  THEN 'Август'
        WHEN 9  THEN 'Сентябрь'
        WHEN 10 THEN 'Октябрь'
        WHEN 11 THEN 'Ноябрь'
        WHEN 12 THEN 'Декабрь'
    END AS "Месяц",
    COALESCE(bp.publish_cnt, 0) AS "Число опубликованных объявлений",
    COALESCE(br.remove_cnt, 0) AS "Число снятых объявлений",
    ROUND(bp.publish_avg_price_sqm::numeric) AS "Средняя цена кв. м (публикация)",
    ROUND(br.remove_avg_price_sqm::numeric) AS "Средняя цена кв. м (снятие)",
    ROUND(bp.publish_avg_area::numeric, 1) AS "Средняя площадь (публикация)",
    ROUND(br.remove_avg_area::numeric, 1) AS "Средняя площадь (снятие)"
FROM (
    SELECT month_num
    FROM by_publish
    UNION
    SELECT month_num
    FROM by_remove
) AS m
LEFT JOIN by_publish AS bp USING (month_num)
LEFT JOIN by_remove AS  br USING (month_num)
ORDER BY "Номер месяца";