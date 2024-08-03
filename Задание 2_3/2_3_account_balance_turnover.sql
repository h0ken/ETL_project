-----------------------------------------------------------------

--Задание 2.3
-----------------------------------------------------------------
-- запросы к таблицам
SELECT * FROM dm.account_balance_turnover
ORDER BY account_rk, effective_date;

SELECT * FROM dm.dict_currency;
SELECT * FROM rd.account;
SELECT * FROM rd.account_balance
ORDER BY account_rk, effective_date;

DROP TABLE rd.new_account_balance;
CREATE TABLE rd.new_account_balance AS
SELECT * FROM rd.account_balance;

SELECT * FROM rd.new_account_balance
ORDER BY account_rk, effective_date;
-----------------------------------------------------------------


-----------------------------------------------------------------
-- Запрос на нахождение отклонений сумм дней (для наглядности и проверки)
SELECT 
    account_rk,
    effective_date,
    account_in_sum,
    account_out_sum,
	LAG(account_out_sum) OVER (PARTITION BY account_rk ORDER BY effective_date) AS previous_account_out_sum,
	account_in_sum - LAG(account_out_sum) OVER (PARTITION BY account_rk ORDER BY effective_date) AS diff
FROM 
	rd.new_account_balance
ORDER BY 
    account_rk, effective_date
-----------------------------------------------------------------


-----------------------------------------------------------------
-- Верный запрос на изменение таблицы rd.account_balance
WITH cte AS (
    SELECT
        t1.account_rk,
        t1.effective_date,
        t2.account_out_sum AS correct_account_in_sum
    FROM
        rd.account_balance t1
    JOIN
        rd.account_balance t2
    ON
        t1.account_rk = t2.account_rk
    AND
        t1.effective_date = t2.effective_date + INTERVAL '1 day'
)
UPDATE rd.account_balance
SET account_in_sum = cte.correct_account_in_sum
FROM cte
WHERE rd.account_balance.account_rk = cte.account_rk
AND rd.account_balance.effective_date = cte.effective_date;
-----------------------------------------------------------------


-----------------------------------------------------------------
-- Второй (обратный) запрос по условию задачи
WITH cte AS (
    SELECT
        t1.account_rk,
        t1.effective_date AS now_date,
        t1.account_in_sum AS correct_account_out_sum,
		t2.account_out_sum AS incorrect,
        t2.effective_date AS previous_date
    FROM
        rd.new_account_balance t1
    JOIN
        rd.new_account_balance t2
    ON
        t1.account_rk = t2.account_rk
    AND
        t1.effective_date = t2.effective_date + INTERVAL '1 day'
    WHERE
        t1.account_in_sum != t2.account_out_sum
)
UPDATE rd.new_account_balance
SET account_out_sum = cte.correct_account_out_sum
FROM cte
WHERE rd.new_account_balance.account_rk = cte.account_rk
AND rd.new_account_balance.effective_date = cte.previous_date;

-----------------------------------------------------------------


-----------------------------------------------------------------
--Данный нам прототип витрины по условию
SELECT a.account_rk,
	   COALESCE(dc.currency_name, '-1'::TEXT) AS currency_name,
	   a.department_rk,
	   ab.effective_date,
	   ab.account_in_sum,
	   ab.account_out_sum
FROM rd.account a
LEFT JOIN rd.new_account_balance ab ON a.account_rk = ab.account_rk
LEFT JOIN dm.dict_currency dc ON a.currency_cd = dc.currency_cd
order by account_rk, effective_date

-----------------------------------------------------------------


-----------------------------------------------------------------
CREATE OR REPLACE PROCEDURE account_balance_turnover()
LANGUAGE plpgsql
AS $$
	BEGIN
    	TRUNCATE TABLE dm.account_balance_turnover;

   		INSERT INTO dm.account_balance_turnover (account_rk, currency_name, department_rk, effective_date, account_in_sum, account_out_sum)
    	SELECT 
       		a.account_rk,
        	COALESCE(dc.currency_name, '-1'::TEXT) AS currency_name,
        	a.department_rk,
        	ab.effective_date,
        	ab.account_in_sum,
        	ab.account_out_sum
    	FROM 
        	rd.account a
    	LEFT JOIN 
        	rd.new_account_balance ab ON a.account_rk = ab.account_rk
    	LEFT JOIN 
        	dm.dict_currency dc ON a.currency_cd = dc.currency_cd
   		ORDER BY 
        	a.account_rk, ab.effective_date;
	END;
$$;

-----------------------------------------------------------------
CALL account_balance_turnover();
