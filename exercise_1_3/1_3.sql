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
	balance_in_val NUMERIC(23,8),
	balance_in_total NUMERIC(23,8),
	turn_deb_rub NUMERIC(23,8),
	turn_deb_val NUMERIC(23,8),
	turn_deb_total NUMERIC(23,8),
	turn_cre_rub NUMERIC(23,8),
	turn_cre_val NUMERIC(23,8),
	turn_cre_total NUMERIC(23,8),
	balance_out_rub NUMERIC(23,8),
	balance_out_val NUMERIC(23,8),
	balance_out_total NUMERIC(23,8)
	);
--------------------------------------------

-- Создание функции расчета остатков и оборотов по балансам второго порядка
--------------------------------------------

CREATE OR REPLACE FUNCTION dm.fill_f101_round_f(i_OnDate DATE)
RETURNS VOID AS $$
DECLARE
    v_FromDate DATE;
    v_ToDate DATE;
BEGIN
    -- Определение дат начала и конца отчетного периода
    v_FromDate := (DATE_TRUNC('month', i_OnDate) - INTERVAL '1 month')::DATE;
    v_ToDate := (DATE_TRUNC('month', i_OnDate) - INTERVAL '1 day')::DATE;

    -- Удаление записей за дату расчета
    DELETE FROM DM.DM_F101_ROUND_F WHERE TO_DATE = v_ToDate;

    -- Вставка новых данных, расчеты
    INSERT INTO DM.DM_F101_ROUND_F (
        FROM_DATE, TO_DATE, CHAPTER, LEDGER_ACCOUNT, CHARACTERISTIC,
        BALANCE_IN_RUB, BALANCE_IN_VAL, BALANCE_IN_TOTAL,
        TURN_DEB_RUB, TURN_DEB_VAL, TURN_DEB_TOTAL,
        TURN_CRE_RUB, TURN_CRE_VAL, TURN_CRE_TOTAL,
        BALANCE_OUT_RUB, BALANCE_OUT_VAL, BALANCE_OUT_TOTAL
    )
    SELECT
        v_FromDate AS FROM_DATE,
        v_ToDate AS TO_DATE,
        la.chapter AS CHAPTER,
        SUBSTRING(ad.account_number FROM 1 FOR 5)::BIGINT AS LEDGER_ACCOUNT,
        ad.char_type AS CHARACTERISTIC,
        SUM(CASE WHEN ad.currency_code IN ('810', '643') THEN bf.balance_out_rub ELSE 0 END) AS BALANCE_IN_RUB,
        SUM(CASE WHEN ad.currency_code NOT IN ('810', '643') THEN bf.balance_out_rub ELSE 0 END) AS BALANCE_IN_VAL,
        SUM(bf.balance_out_rub) AS BALANCE_IN_TOTAL,
        COALESCE (SUM(CASE WHEN ad.currency_code IN ('810', '643') THEN tf.debet_amount_rub ELSE 0 END),0) AS TURN_DEB_RUB,
        SUM(CASE WHEN ad.currency_code NOT IN ('810', '643') THEN tf.debet_amount_rub ELSE 0 END) AS TURN_DEB_VAL,
        COALESCE (SUM(tf.debet_amount_rub),0) AS TURN_DEB_TOTAL,
        COALESCE (SUM(CASE WHEN ad.currency_code IN ('810', '643') THEN tf.credit_amount_rub ELSE 0 END),0) AS TURN_CRE_RUB,
        SUM(CASE WHEN ad.currency_code NOT IN ('810', '643') THEN tf.credit_amount_rub ELSE 0 END) AS TURN_CRE_VAL,
        COALESCE (SUM(tf.credit_amount_rub),0) AS TURN_CRE_TOTAL,
        SUM(CASE WHEN ad.currency_code IN ('810', '643') THEN bf2.balance_out_rub ELSE 0 END) AS BALANCE_OUT_RUB,
        SUM(CASE WHEN ad.currency_code NOT IN ('810', '643') THEN bf2.balance_out_rub ELSE 0 END) AS BALANCE_OUT_VAL,
        SUM(bf2.balance_out_rub) AS BALANCE_OUT_TOTAL
    FROM
        ds.md_account_d ad
        JOIN ds.md_ledger_account_s la ON SUBSTRING(ad.account_number FROM 1 FOR 5)::BIGINT = la.ledger_account
        LEFT JOIN DM.DM_ACCOUNT_BALANCE_F bf ON bf.account_rk = ad.account_rk AND bf.on_date = v_FromDate - INTERVAL '1 day'
        LEFT JOIN DM.DM_ACCOUNT_TURNOVER_F tf ON tf.account_rk = ad.account_rk AND tf.on_date BETWEEN v_FromDate AND v_ToDate
        LEFT JOIN DM.DM_ACCOUNT_BALANCE_F bf2 ON bf2.account_rk = ad.account_rk AND bf2.on_date = v_ToDate
    GROUP BY
        la.chapter,
        SUBSTRING(ad.account_number FROM 1 FOR 5),
        ad.char_type;
END;
$$ LANGUAGE plpgsql;

--------------------------------------------

-- Процедура заполнения таблицы dm.dm_f101_round_f с логированием
--------------------------------------------
DO $$
DECLARE
    table_or_function_name VARCHAR := 'fill_f101_round_f';
    ready_to_start TIMESTAMP;
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    count_record INTEGER;
BEGIN
    ready_to_start := clock_timestamp();
    start_time := clock_timestamp();
    
    PERFORM dm.fill_f101_round_f('2018-02-01'::DATE);
    
    end_time := clock_timestamp();
    
    SELECT count(*) INTO count_record FROM dm.dm_f101_round_f;
    
    INSERT INTO logs.log_info (table_or_function_name, ready_to_start, start_time, end_time, count_record)
    VALUES (table_or_function_name, 
            DATE_TRUNC('second', ready_to_start), 
            DATE_TRUNC('second', start_time), 
            DATE_TRUNC('second', end_time), 
            count_record);
END $$;

--------------------------------------------
--ПРОВЕРКА 
-- 18 счетов
--SELECT distinct(SUBSTRING(account_number FROM 1 FOR 5)) as test FROM ds.md_account_d

