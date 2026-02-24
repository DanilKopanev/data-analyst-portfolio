/* Проект «Секреты Тёмнолесья»
 * Цель проекта: изучить влияние характеристик игроков и их игровых персонажей 
 * на покупку внутриигровой валюты «райские лепестки», а также оценить 
 * активность игроков при совершении внутриигровых покупок
 * 
 * Автор: Копанев Данил Романович
 * Дата: 17.11.2025
*/


-- Часть 1. Исследовательский анализ данных
-- Задача 1. Исследование доли платящих игроков

-- 1.1. Доля платящих пользователей по всем данным:
SELECT COUNT(DISTINCT id) AS total_users,
	SUM(payer) AS payer_users,
	ROUND(AVG(payer),2) AS avg_payer_users
FROM fantasy.users

-- 1.2. Доля платящих пользователей в разрезе расы персонажа:
-- можно без r и u, так как значения не повторяются в таблицах
SELECT r.race,
	SUM(u.payer) AS payer_count,
	COUNT(*) AS total_users,
	ROUND(AVG(u.payer), 2) AS avg_payer_users
FROM fantasy.users u
JOIN fantasy.race r USING (race_id)
GROUP BY race
ORDER BY avg_payer_users DESC;

-- Задача 2. Исследование внутриигровых покупок
-- 2.1. Статистические показатели по полю amount:
SELECT COUNT(amount) AS count_amount,
	SUM(amount) AS total_amount,
	MIN(amount) AS min_amount,
	MAX(amount) AS max_amount,
	ROUND(AVG(amount::numeric)) AS avg_amount,
	PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY amount) AS median_amount,
	ROUND(STDDEV(amount::numeric)) AS stand_dev_amount
FROM fantasy.events;

-- 2.2: Аномальные нулевые покупки:
WITH base AS (SELECT COUNT(CASE 
		WHEN amount = 0 THEN 1 
		END) AS zero,
		COUNT(amount) AS total_count
		FROM fantasy.events
)
SELECT *,
	ROUND(zero::numeric / total_count,4) AS zero_amount_count
FROM base;
	
-- 2.3: Популярные эпические предметы:
SELECT i.game_items,
    COUNT(*) AS absolute_total_items,
    ROUND(COUNT(*)::numeric / SUM(COUNT(*)) OVER (), 2) AS item_sales, -- еще читал, что можно * 1.0
    ROUND(COUNT(DISTINCT e.id)::numeric /
    	(SELECT COUNT(DISTINCT id)
     	 FROM fantasy.events
     	 WHERE amount > 0), 2) AS buyer_share
FROM fantasy.events e
JOIN fantasy.items i USING (item_code)
WHERE e.amount > 0
GROUP BY i.game_items
ORDER BY buyer_share DESC;


-- Часть 2. Решение ad hoc-задачи
-- Задача: Зависимость активности игроков от расы персонажа:
WITH users AS (
	SELECT r.race AS race,
	COUNT(DISTINCT u.id) AS total_users
	FROM fantasy.users u
	JOIN fantasy.race r USING (race_id)
	GROUP BY r.race
),
buyers AS (
	SELECT r.race AS race,
        COUNT(DISTINCT u.id) AS buyers_count
    FROM fantasy.users u
	JOIN fantasy.race r USING (race_id)
	JOIN fantasy.events e USING (id)
	WHERE e.amount > 0
	GROUP BY r.race
),
paying_buyers AS (
  	SELECT r.race AS race,
    	COUNT(DISTINCT u.id) AS paying_buyers_count
  	FROM fantasy.users u
	JOIN fantasy.race r USING (race_id)
	JOIN fantasy.events e USING (id)
  	WHERE e.amount > 0 AND u.payer = 1
  	GROUP BY r.race
),
paying_buyers_share AS (
	SELECT b.race AS race,
		buyers_count,
		ROUND(paying_buyers_count::numeric / buyers_count, 2) AS paying_share
	FROM buyers b
	LEFT JOIN paying_buyers pb USING (race)
),
activity AS (
	SELECT r.race AS race,
    	u.id AS user_id,
    	COUNT(e.transaction_id) AS shop_count,
    	SUM(e.amount) AS shop_sum,
    	AVG(e.amount) AS avg_shop
  	FROM fantasy.users u
  	JOIN fantasy.race r USING (race_id)
  	JOIN fantasy.events e USING (id)
  	WHERE e.amount > 0
  	GROUP BY r.race, u.id
)
SELECT
  u.race,
  u.total_users,
  b.buyers_count,
  ROUND(b.buyers_count::NUMERIC / u.total_users, 2) AS buyers_share,
  pbs.paying_share,
  ROUND(AVG(a.shop_count::numeric)) AS avg_paying_buyer,
  ROUND(AVG(a.avg_shop::numeric)) AS avg_paying_amount,
  ROUND(AVG(a.shop_sum::numeric)) AS avg_total_buyer
FROM users u
LEFT JOIN buyers b USING (race)
LEFT JOIN paying_buyers pb USING (race)
LEFT JOIN paying_buyers_share pbs USING (race)
LEFT JOIN activity a USING (race)
GROUP BY u.race, u.total_users, b.buyers_count, pbs.paying_share
ORDER BY u.total_users DESC;



	