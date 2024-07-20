--------------------------------------------

-- 1.3 расчет 101 формы за январь 2018 года
--------------------------------------------
DROP TABLE IF EXISTS DM.DM_F101_ROUND_F;
CREATE TABLE DM.DM_F101_ROUND_F(
	from_date DATE,
	to_date DATE,
	chapter CHAR(1),
	ledger_account CHAR(5),
	characteristic CHAR(1),
	balance_in_rub NUMERIC(23,8),
	r_balance_in_rub NUMERIC(23,8),
	balance_in_val NUMERIC(23,8),
	r_balance_in_val NUMERIC(23,8),
	balance_in_total NUMERIC(23,8),
	r_balance_in_total NUMERIC(23,8),
	turn_deb_rub NUMERIC(23,8),
	r_turn_deb_rub NUMERIC(23,8),
	turn_deb_val NUMERIC(23,8),
	r_turn_deb_val NUMERIC(23,8),
	turn_deb_total NUMERIC(23,8),
	r_turn_deb_total NUMERIC(23,8),
	turn_cre_rub NUMERIC(23,8),
	r_turn_cre_rub NUMERIC(23,8),
	turn_cre_val NUMERIC(23,8),
	r_turn_cre_val NUMERIC(23,8),
	turn_cre_total NUMERIC(23,8),
	r_turn_cre_total NUMERIC(23,8),
	balance_out_rub NUMERIC(23,8),
	r_balance_out_rub NUMERIC(23,8),
	balance_out_val NUMERIC(23,8),
	r_balance_out_val NUMERIC(23,8),
	balance_out_total NUMERIC(23,8),
	r_balance_out_total NUMERIC(23,8)
	);
--------------------------------------------

-- Создание функции расчета остатков и оборотов по балансам второго порядка
--------------------------------------------

CREATE OR REPLACE FUNCTION dm.fill_f101_round_f(i_OnDate DATE)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_FromDate DATE;
    v_ToDate DATE;
BEGIN
    -- Определяем начальную и конечную даты отчетного периода
    v_FromDate := date_trunc('month', i_OnDate) - INTERVAL '1 month';
    v_ToDate := v_FromDate + INTERVAL '1 month' - INTERVAL '1 day';

    -- Удаляем существующие записи за отчетный период
    DELETE FROM DM.DM_F101_ROUND_F WHERE FROM_DATE = v_FromDate AND TO_DATE = v_ToDate;

    -- Вставляем новые данные в таблицу отчета
    INSERT INTO DM.DM_F101_ROUND_F (
        FROM_DATE, TO_DATE, CHAPTER, LEDGER_ACCOUNT, CHARACTERISTIC,
        BALANCE_IN_RUB, BALANCE_IN_VAL, BALANCE_IN_TOTAL,
        TURN_DEB_RUB, TURN_DEB_VAL, TURN_DEB_TOTAL,
        TURN_CRE_RUB, TURN_CRE_VAL, TURN_CRE_TOTAL,
        BALANCE_OUT_RUB, BALANCE_OUT_VAL, BALANCE_OUT_TOTAL
    )
    WITH balances AS (
        -- CTE для расчета остатков
        SELECT
            LEFT(a.account_number, 5)::INTEGER AS LEDGER_ACCOUNT,
            a.char_type AS CHARACTERISTIC,
            COALESCE(SUM(CASE WHEN a.currency_code IN (810, 643) THEN b.balance_out_rub ELSE 0 END), 0) AS BALANCE_IN_RUB,
            COALESCE(SUM(CASE WHEN a.currency_code NOT IN (810, 643) THEN b.balance_out_rub ELSE 0 END), 0) AS BALANCE_IN_VAL,
            COALESCE(SUM(b.balance_out_rub), 0) AS BALANCE_IN_TOTAL
        FROM
            DS.MD_ACCOUNT_D a
        LEFT JOIN
            DM.DM_ACCOUNT_BALANCE_F b ON a.account_rk = b.account_rk AND b.on_date = v_FromDate - INTERVAL '1 day'
        GROUP BY
            LEFT(a.account_number, 5), a.char_type
		
    ), turnovers AS (
        -- CTE turn
        SELECT
            LEFT(a.account_number, 5)::INTEGER AS LEDGER_ACCOUNT,
            COALESCE(SUM(CASE WHEN a.currency_code IN (810, 643) THEN t.debet_amount_rub ELSE 0 END), 0) AS TURN_DEB_RUB,
            COALESCE(SUM(CASE WHEN a.currency_code NOT IN (810, 643) THEN t.debet_amount_rub ELSE 0 END), 0) AS TURN_DEB_VAL,
            COALESCE(SUM(t.debet_amount_rub), 0) AS TURN_DEB_TOTAL,
            COALESCE(SUM(CASE WHEN a.currency_code IN (810, 643) THEN t.credit_amount_rub ELSE 0 END), 0) AS TURN_CRE_RUB,
            COALESCE(SUM(CASE WHEN a.currency_code NOT IN (810, 643) THEN t.credit_amount_rub ELSE 0 END), 0) AS TURN_CRE_VAL,
            COALESCE(SUM(t.credit_amount_rub), 0) AS TURN_CRE_TOTAL
        FROM
            DS.MD_ACCOUNT_D a
        LEFT JOIN
            DM.DM_ACCOUNT_TURNOVER_F t ON a.account_rk = t.account_rk AND t.on_date BETWEEN v_FromDate AND v_ToDate
        GROUP BY
            LEFT(a.account_number, 5)
    ), balance AS( 
        -- CTE Balance_out
    SELECT
		LEFT(a.account_number, 5)::INTEGER AS LEDGER_ACCOUNT,
		COALESCE(SUM(CASE WHEN a.currency_code IN (810, 643) THEN balance_out_rub ELSE 0 END), 0) BALANCE_OUT_RUB,
		COALESCE(SUM(CASE WHEN a.currency_code NOT IN (810, 643) THEN balance_out_rub ELSE 0 END), 0) BALANCE_OUT_VAL,
		COALESCE(SUM(CASE WHEN a.currency_code IN (810, 643) THEN balance_out_rub ELSE 0 END), 0) +
		COALESCE(SUM(CASE WHEN a.currency_code NOT IN (810, 643) THEN balance_out_rub ELSE 0 END), 0) AS BALANCE_OUT_TOTAL
	FROM DM.DM_ACCOUNT_BALANCE_F b
	JOIN DS.MD_ACCOUNT_D a USING (account_rk)
	WHERE on_date = v_ToDate
	group by LEFT(a.account_number, 5)
	order by LEDGER_ACCOUNT
		)
	
    SELECT
        v_FromDate AS FROM_DATE,
        v_ToDate AS TO_DATE,
        l.chapter AS CHAPTER,
        bs.LEDGER_ACCOUNT,
        bs.CHARACTERISTIC,
        bs.BALANCE_IN_RUB,
        bs.BALANCE_IN_VAL,
        bs.BALANCE_IN_TOTAL,
        t.TURN_DEB_RUB,
        t.TURN_DEB_VAL,
        t.TURN_DEB_TOTAL,
        t.TURN_CRE_RUB,
        t.TURN_CRE_VAL,
        t.TURN_CRE_TOTAL,
        b.BALANCE_OUT_RUB,
		b.BALANCE_OUT_VAL,
        b.BALANCE_OUT_TOTAL
    FROM balance b
    JOIN balances bs USING (LEDGER_ACCOUNT)
	JOIN turnovers t USING (LEDGER_ACCOUNT)
    LEFT JOIN DS.MD_LEDGER_ACCOUNT_S l ON bs.LEDGER_ACCOUNT = l.ledger_account;
END;
$$;
--------------------------------------------

-- Процедура заполнения таблицы dm.dm_f101_round_f с логированием
--------------------------------------------

CREATE OR REPLACE PROCEDURE dm.fill_f101_round_procedure(input_date DATE)
LANGUAGE plpgsql
AS $$
DECLARE
    table_or_function_name VARCHAR := 'fill_f101_round_f';
    ready_to_start TIMESTAMP;
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    count_record INTEGER;
BEGIN
    ready_to_start := clock_timestamp();
    start_time := clock_timestamp();
    
    PERFORM dm.fill_f101_round_f(input_date);
    
    end_time := clock_timestamp();
    
    SELECT count(*) INTO count_record FROM dm.dm_f101_round_f;
    
    INSERT INTO logs.log_info (table_or_function_name, ready_to_start, start_time, end_time, count_record)
    VALUES (table_or_function_name, 
            DATE_TRUNC('second', ready_to_start), 
            DATE_TRUNC('second', start_time), 
            DATE_TRUNC('second', end_time), 
            count_record);
END $$;

CALL dm.fill_f101_round_procedure('2018-02-01');
--------------------------------------------