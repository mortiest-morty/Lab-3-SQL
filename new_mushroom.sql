-- ---------- 1. Спец. таблица ----------
DROP TABLE IF EXISTS spec CASCADE;
CREATE TABLE spec (
    id           INTEGER PRIMARY KEY,
    table_name   TEXT    NOT NULL,
    column_name  TEXT    NOT NULL,
    current_max  INTEGER NOT NULL,
    UNIQUE (table_name, column_name)
);

-- ---------- 2. Начальная запись ----------
INSERT INTO spec (id, table_name, column_name, current_max)
VALUES (1, 'spec', 'id', 1);

-- ---------- 3. Хранимая функция ----------
CREATE OR REPLACE FUNCTION next_id(p_table TEXT, p_column TEXT)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_cur    INTEGER;
    v_new_id INTEGER;
BEGIN
    -- Есть ли запись в spec?
    SELECT current_max INTO v_cur
      FROM spec
     WHERE table_name = p_table AND column_name = p_column
     FOR UPDATE;

    IF FOUND THEN
        v_cur := v_cur + 1;
        UPDATE spec SET current_max = v_cur
         WHERE table_name = p_table AND column_name = p_column;
        RETURN v_cur;
    END IF;

    -- Записи нет: ищем MAX в целевой таблице
    EXECUTE format('SELECT COALESCE(MAX(%I),0) FROM %I', p_column, p_table)
      INTO v_cur;
    v_cur := v_cur + 1;

    -- Рекурсивно получаем id для новой строки spec
    v_new_id := next_id('spec','id');

    INSERT INTO spec (id, table_name, column_name, current_max)
    VALUES (v_new_id, p_table, p_column, v_cur);

    RETURN v_cur;
END;
$$;
/*
-- ---------- 4-5. spec/id → 2 ----------
SELECT next_id('spec','id') AS step4_result;       
SELECT * FROM spec ORDER BY id;                     

-- ---------- 6-7. spec/id → 3 ----------
SELECT next_id('spec','id') AS step6_result;       
SELECT * FROM spec ORDER BY id;                     

-- ---------- 8-9. Таблица mushrooms ----------
DROP TABLE IF EXISTS mushrooms CASCADE;
CREATE TABLE mushrooms (
    id        INTEGER PRIMARY KEY,
    name      TEXT,
    edibility TEXT
);
INSERT INTO mushrooms (id, name, edibility)
VALUES (10, 'Белый гриб', 'съедобный');

-- ---------- 10-11. mushrooms/id → 11 (рекурсия) ----------
SELECT next_id('mushrooms','id') AS step10_result;  
SELECT * FROM spec ORDER BY id;  
--SELECT * FROM mushrooms;

-- ---------- 12-13. mushrooms/id → 12 ----------
SELECT next_id('mushrooms','id') AS step12_result;  
SELECT * FROM spec ORDER BY id;                     

-- ---------- 14. Таблица mushrooms2 ----------
DROP TABLE IF EXISTS mushrooms2 CASCADE;
CREATE TABLE mushrooms2 (
    num_value1 INTEGER,
    num_value2 INTEGER
);

-- ---------- 15-16. mushrooms2/num_value1 → 1 ----------
SELECT next_id('mushrooms2','num_value1') AS step15_result; 
SELECT * FROM spec ORDER BY id;                              

-- ---------- 17-18. mushrooms2/num_value1 → 2 ----------
SELECT next_id('mushrooms2','num_value1') AS step17_result; 
SELECT * FROM spec ORDER BY id;


-- ---------- 19-21. mushrooms2/num_value2 → 14 ----------
INSERT INTO mushrooms2 (num_value1, num_value2) VALUES (2, 13);
SELECT next_id('mushrooms2','num_value2') AS step20_result;
SELECT * FROM spec ORDER BY id;                              


-- ---------- 22-23. 5 вызовов num_value1 → 7 ----------
SELECT next_id('mushrooms2','num_value1') FROM generate_series(1,5);
SELECT * FROM spec ORDER BY id;

-- ============================================================
-- ТРИГГЕРЫ синхронизации spec

CREATE OR REPLACE FUNCTION trg_sync_spec()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_col     TEXT := TG_ARGV[0];
    v_new_val BIGINT;
    v_cur     INTEGER;
BEGIN
    EXECUTE format('SELECT ($1).%I', v_col) INTO v_new_val USING NEW;
    IF v_new_val IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT current_max INTO v_cur
      FROM spec
     WHERE table_name = TG_TABLE_NAME AND column_name = v_col;

    IF FOUND THEN
        IF v_new_val > v_cur THEN
            UPDATE spec SET current_max = v_new_val
             WHERE table_name = TG_TABLE_NAME AND column_name = v_col;
        END IF;
    ELSE
        INSERT INTO spec (id, table_name, column_name, current_max)
        VALUES (next_id('spec','id'), TG_TABLE_NAME, v_col, v_new_val);
    END IF;

    RETURN NEW;
END;
$$;

-- Динамическое создание триггеров для всех уникальных пар (table,column)
DO $$
DECLARE r RECORD;
BEGIN
    FOR r IN
        SELECT DISTINCT table_name, column_name
          FROM spec
         WHERE table_name <> 'spec'
    LOOP
        EXECUTE format($f$
            DROP TRIGGER IF EXISTS trg_sync_%1$I_%2$I ON %1$I;
            CREATE TRIGGER trg_sync_%1$I_%2$I
            AFTER INSERT OR UPDATE OF %2$I ON %1$I
            FOR EACH ROW EXECUTE FUNCTION trg_sync_spec(%2$L);
        $f$, r.table_name, r.column_name);
    END LOOP;
END;
$$;

-- ---------- Тест триггера: вставка в обход ХП ----------
INSERT INTO mushrooms (id, name, edibility)
VALUES (100, 'Мухомор красный', 'ядовитый');
--INSERT INTO mushrooms (id, name, edibility)
--VALUES (5, 'Мухомор красный', 'ядовитый');
 SELECT * FROM spec WHERE table_name='mushrooms' ORDER BY id;  
-- SELECT * FROM mushrooms ORDER BY id;

-- ---------- Тест триггера: UPDATE с превышением ----------
UPDATE mushrooms SET id = 200 WHERE id = 100;
SELECT * FROM spec WHERE table_name='mushrooms' ORDER BY id;  

-- SELECT next_id('mushrooms','id') AS after_trigger;        
-- SELECT * FROM spec ORDER BY id;

-- ============================================================
-- Очистка (шаги 24-25)
-- ============================================================
DROP FUNCTION IF EXISTS next_id(TEXT,TEXT) CASCADE;
DROP FUNCTION IF EXISTS trg_sync_spec() CASCADE;
DROP TABLE IF EXISTS mushrooms2 CASCADE;
DROP TABLE IF EXISTS mushrooms  CASCADE;
DROP TABLE IF EXISTS spec        CASCADE;*/