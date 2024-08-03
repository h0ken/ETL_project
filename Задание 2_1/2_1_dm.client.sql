SELECT * FROM dm.client
ORDER BY client_rk, effective_from_date

-------------------------------------------------------
with t1 AS 
	(SELECT * FROM dm.client
	 UNION
	 SELECT * FROM dm.client)
SELECT * FROM t1
WHERE client_rk = 3055149
ORDER BY client_rk, effective_from_date

-------------------------------------------------------


-------------------------------------------------------
-- Создадим копию dm.client для тестов 
DROP TABLE dm.temp_client;
CREATE TABLE dm.temp_client AS
SELECT * FROM dm.client;

SELECT * FROM dm.client
ORDER BY client_rk, effective_from_date;
-------------------------------------------------------


-------------------------------------------------------
-- 1 способ очищения от дубликатов (так же этот запрос является проверяющим итоговой таблицы)
WITH diff_data AS (
    SELECT 
        client_rk, 
        effective_from_date, 
        effective_to_date, 
        LAG(effective_to_date) OVER (PARTITION BY client_rk ORDER BY effective_from_date) AS prev_effective_to_date
    FROM 
        dm.temp_client
)
SELECT 
    client_rk, 
    effective_from_date, 
    effective_to_date, 
    prev_effective_to_date
FROM 
    diff_data
WHERE 
    prev_effective_to_date IS NOT NULL
    AND prev_effective_to_date != effective_from_date;

-------------------------------------------------------


-------------------------------------------------------
-- Второе решение удаления дубликатов

SELECT ctid,* FROM dm.temp_client WHERE ctid NOT IN
(SELECT max(ctid) FROM dm.temp_client GROUP BY client_rk, effective_from_date);

DELETE FROM dm.temp_client WHERE ctid NOT IN
(SELECT max(ctid) FROM dm.temp_client GROUP BY client_rk, effective_from_date);
-------------------------------------------------------


-------------------------------------------------------
-- Третье решение удаления дубликатов

ALTER TABLE dm.temp_client ADD COLUMN temp_id SERIAL PRIMARY KEY;

CREATE TEMP TABLE temp_ranked_clients AS
WITH RankedClients AS (
    SELECT
        temp_id,
        client_rk,
        effective_from_date,
        effective_to_date,
        account_rk,
        ROW_NUMBER() OVER (
            PARTITION BY client_rk, effective_from_date 
            ORDER BY effective_to_date, account_rk
        ) AS rn
    FROM
        dm.temp_client
)
SELECT *
FROM RankedClients
WHERE rn > 1;

DELETE FROM dm.temp_client
WHERE temp_id IN (SELECT temp_id FROM temp_ranked_clients);

ALTER TABLE dm.temp_client DROP COLUMN temp_id;

DROP TABLE temp_ranked_clients;

-------------------------------------------------------