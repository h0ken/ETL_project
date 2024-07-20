------------------------------------------------

-- Задача 1.2
------------------------------------------------

-- Создание таблицы витрины оборотов DM.DM_ACCOUNT_TURNOVER_F
------------------------------------------------
CREATE SCHEMA IF NOT EXISTS DM;

DROP TABLE IF EXISTS DM.DM_ACCOUNT_TURNOVER_F;
CREATE TABLE DM.DM_ACCOUNT_TURNOVER_F(
	  on_date 				DATE
	, account_rk 			NUMERIC
	, credit_amount 		NUMERIC(23,8)
	, credit_amount_rub		NUMERIC(23,8)
	, debet_amount 			NUMERIC(23,8)
	, debet_amount_rub 		NUMERIC(23,8)
	, PRIMARY KEY (on_date, account_rk)
);

------------------------------------------------

-- Создание функции dm.fill_account_turnover_f
------------------------------------------------

CREATE OR REPLACE FUNCTION dm.fill_account_turnover_f(i_OnDate DATE)
RETURNS VOID AS $$
BEGIN
    -- Удаляем существующие данные за дату расчета
    DELETE FROM DM.DM_ACCOUNT_TURNOVER_F
    WHERE on_date = i_OnDate;

    -- Вставляем рассчитанные данные
    INSERT INTO DM.DM_ACCOUNT_TURNOVER_F (on_date, account_rk, credit_amount, credit_amount_rub, debet_amount, debet_amount_rub)
    WITH t1 AS (
        SELECT 
            p.oper_date,
            p.credit_account_rk AS account_rk,
            b.currency_rk,
            SUM(p.credit_amount) AS credit_amount,
            0 AS debet_amount
        FROM DS.FT_POSTING_F p
        LEFT JOIN DS.FT_BALANCE_F b ON b.account_rk = p.credit_account_rk
        WHERE p.oper_date = i_OnDate
        GROUP BY p.oper_date, p.credit_account_rk, b.currency_rk

        UNION ALL

        SELECT 
            p.oper_date,
            p.debet_account_rk AS account_rk,
            b.currency_rk,
            0 AS credit_amount,
            SUM(p.debet_amount) AS debet_amount
        FROM DS.FT_POSTING_F p
        LEFT JOIN DS.FT_BALANCE_F b ON b.account_rk = p.debet_account_rk
        WHERE p.oper_date = i_OnDate
        GROUP BY p.oper_date, p.debet_account_rk, b.currency_rk
    ),
    t2 AS (
		SELECT currency_rk, reduced_cource 
		FROM DS.MD_EXCHANGE_RATE_D
		WHERE i_OnDate BETWEEN data_actual_date AND data_actual_end_date
		group by 1,2
    	)

    SELECT 
        i_OnDate AS on_date,
        t1.account_rk,
        SUM(t1.credit_amount) AS credit_amount,
        SUM(t1.credit_amount * COALESCE(t2.reduced_cource, 1)) AS credit_amount_rub,
        SUM(t1.debet_amount) AS debet_amount,
        SUM(t1.debet_amount * COALESCE(t2.reduced_cource, 1)) AS debet_amount_rub
    FROM t1
    LEFT JOIN t2 ON t1.currency_rk = t2.currency_rk
    GROUP BY t1.account_rk;
END;
$$ LANGUAGE plpgsql;

------------------------------------------------

-- Создание и выполнение процедуры для заполнения каждого дня января 2018 года
------------------------------------------------
CREATE OR REPLACE PROCEDURE dm.fill_account_turnover_procedure(start_date DATE, end_date DATE)
LANGUAGE plpgsql
AS $$
DECLARE
    currentDate DATE := start_date;
    table_or_function_name VARCHAR := 'fill_account_turnover_f';
    ready_to_start TIMESTAMP;
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    count_record INTEGER;
BEGIN
    ready_to_start := clock_timestamp();
    start_time := clock_timestamp();
    
    WHILE currentDate <= end_date LOOP
        PERFORM dm.fill_account_turnover_f(currentDate);
        currentDate := currentDate + INTERVAL '1 day';
    END LOOP;
    
    end_time := clock_timestamp();
    
    SELECT count(*) INTO count_record FROM DM.DM_ACCOUNT_TURNOVER_F;
    
    INSERT INTO logs.log_info (table_or_function_name, ready_to_start, start_time, end_time, count_record)
    VALUES (table_or_function_name, 
            DATE_TRUNC('second', ready_to_start), 
            DATE_TRUNC('second', start_time), 
            DATE_TRUNC('second', end_time), 
            count_record);
END $$;


CALL dm.fill_account_turnover_procedure('2018-01-01', '2018-01-31');

------------------------------------------------

-- --------- ПРОВЕРКА
-- SELECT count(distinct account_rk) FROM DM.DM_ACCOUNT_TURNOVER_F

-- WITH t1 As (SELECT credit_account_rk as account_rk FROM ds.ft_posting_f
-- UNION
-- SELECT debet_account_rk as account_rk FROM ds.ft_posting_f)
-- SELECT count(distinct account_rk) FROM t1
-- -- ----------
-- SELECT * FROM DM.DM_ACCOUNT_TURNOVER_F
-- WHERE on_date = '2018-01-09' AND account_rk = 13630
	
-- SELECT credit_account_rk, sum(credit_amount) FROM ds.ft_posting_f
-- WHERE oper_date = '2018-01-09' AND credit_account_rk = 13630
-- GROUP BY credit_account_rk
------------------------------------------------
	
-- Создание таблицы витрины остатка DM.DM_ACCOUNT_BALANCE_F
------------------------------------------------
DROP TABLE IF EXISTS DM.DM_ACCOUNT_BALANCE_F;

CREATE TABLE DM.DM_ACCOUNT_BALANCE_F(
	on_date DATE,
	account_rk numeric, 
	balance_out FLOAT,
	balance_out_rub FLOAT
);
------------------------------------------------

-- Заполняем витрину DM.DM_ACCOUNT_BALANCE_F за '31.12.2017'
------------------------------------------------

INSERT INTO DM.DM_ACCOUNT_BALANCE_F (on_date, account_rk, balance_out, balance_out_rub)
SELECT 
	on_date,	
	account_rk, 
	balance_out, 
	balance_out * coalesce(reduced_cource, 1) as balance_out_rub
FROM 
	DS.FT_BALANCE_F b
LEFT JOIN DS.MD_EXCHANGE_RATE_D e ON b.currency_rk = e.currency_rk
AND '2017-12-31' BETWEEN data_actual_date and data_actual_end_date

------------------------------------------------

-- Создаем функцию по заполнению витрины остатков за весь месяц
------------------------------------------------

CREATE OR REPLACE FUNCTION ds.fill_account_balance_f(i_OnDate DATE)
RETURNS VOID AS $$
BEGIN
    -- Удаление данных за указанную дату, если они уже существуют
   DELETE FROM DM.DM_ACCOUNT_BALANCE_F WHERE on_date = i_OnDate;
    
    -- Вставка новых данных
    INSERT INTO DM.DM_ACCOUNT_BALANCE_F (on_date, account_rk, balance_out, balance_out_rub)
    SELECT
        i_OnDate AS on_date,
        a.account_rk,
        -- Расчет balance_out
        CASE 
            WHEN a.char_type = 'А' THEN 
                COALESCE((
                    SELECT balance_out
                    FROM DM.DM_ACCOUNT_BALANCE_F 
                    WHERE account_rk = a.account_rk 
                    AND on_date = i_OnDate - INTERVAL '1 day'
                ), 0)
                + COALESCE((
                    SELECT SUM(debet_amount)
                    FROM DM.DM_ACCOUNT_TURNOVER_F 
                    WHERE account_rk = a.account_rk 
                    AND on_date = i_OnDate
                ), 0)
                - COALESCE((
                    SELECT SUM(credit_amount)
                    FROM DM.DM_ACCOUNT_TURNOVER_F 
                    WHERE account_rk = a.account_rk 
                    AND on_date = i_OnDate
                ), 0)
            WHEN a.char_type = 'П' THEN 
                COALESCE((
                    SELECT balance_out
                    FROM DM.DM_ACCOUNT_BALANCE_F 
                    WHERE account_rk = a.account_rk 
                    AND on_date = i_OnDate - INTERVAL '1 day'
                ), 0)
                - COALESCE((
                    SELECT SUM(debet_amount)
                    FROM DM.DM_ACCOUNT_TURNOVER_F 
                    WHERE account_rk = a.account_rk 
                    AND on_date = i_OnDate
                ), 0)
                + COALESCE((
                    SELECT SUM(credit_amount)
                    FROM DM.DM_ACCOUNT_TURNOVER_F 
                    WHERE account_rk = a.account_rk 
                    AND on_date = i_OnDate
                ), 0)
        END AS balance_out,
        -- Расчет balance_out_rub
        CASE 
            WHEN a.char_type = 'А' THEN 
                COALESCE((
                    SELECT balance_out_rub
                    FROM DM.DM_ACCOUNT_BALANCE_F 
                    WHERE account_rk = a.account_rk 
                    AND on_date = i_OnDate - INTERVAL '1 day'
                ), 0)
                + COALESCE((
                    SELECT SUM(debet_amount_rub)
                    FROM DM.DM_ACCOUNT_TURNOVER_F 
                    WHERE account_rk = a.account_rk 
                    AND on_date = i_OnDate
                ), 0)
                - COALESCE((
                    SELECT SUM(credit_amount_rub)
                    FROM DM.DM_ACCOUNT_TURNOVER_F 
                    WHERE account_rk = a.account_rk 
                    AND on_date = i_OnDate
                ), 0)
            WHEN a.char_type = 'П' THEN 
                COALESCE((
                    SELECT balance_out_rub
                    FROM DM.DM_ACCOUNT_BALANCE_F 
                    WHERE account_rk = a.account_rk 
                    AND on_date = i_OnDate - INTERVAL '1 day'
                ), 0)
                - COALESCE((
                    SELECT SUM(debet_amount_rub)
                    FROM DM.DM_ACCOUNT_TURNOVER_F 
                    WHERE account_rk = a.account_rk 
                    AND on_date = i_OnDate
                ), 0)
                + COALESCE((
                    SELECT SUM(credit_amount_rub)
                    FROM DM.DM_ACCOUNT_TURNOVER_F 
                    WHERE account_rk = a.account_rk 
                    AND on_date = i_OnDate
                ), 0)
        END AS balance_out_rub
    FROM
        ds.md_account_d a
    WHERE
        i_OnDate BETWEEN a.data_actual_date AND a.data_actual_end_date;
END;
$$ LANGUAGE plpgsql;

------------------------------------------------

-- Создаем процедуру заполнения DM.DM_ACCOUNT_BALANCE_F с 1 по 31 января 2018 года
------------------------------------------------

CREATE OR REPLACE PROCEDURE dm.fill_account_balance_procedure(start_date DATE, end_date DATE)
LANGUAGE plpgsql
AS $$
DECLARE
    currentDate DATE := start_date;
    table_or_function_name VARCHAR := 'fill_account_balance_f';
    ready_to_start TIMESTAMP;
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    count_record INTEGER;
BEGIN
    ready_to_start := clock_timestamp();
    start_time := clock_timestamp();
    
    WHILE currentDate <= end_date LOOP
        PERFORM ds.fill_account_balance_f(currentDate);
        currentDate := currentDate + INTERVAL '1 day';
    END LOOP;
    
    end_time := clock_timestamp();
    
    SELECT count(*) INTO count_record FROM DM.DM_ACCOUNT_balance_F;
    
    INSERT INTO logs.log_info (table_or_function_name, ready_to_start, start_time, end_time, count_record)
    VALUES (table_or_function_name, 
            DATE_TRUNC('second', ready_to_start), 
            DATE_TRUNC('second', start_time), 
            DATE_TRUNC('second', end_time), 
            count_record);
END $$;


CALL dm.fill_account_balance_procedure('2018-01-01', '2018-01-31');