----------------
-- START GAME --
----------------

/*

Game of Life, now in SQL.

*/

-----------------
-- DROP TABLES --
-----------------

BEGIN
   EXECUTE IMMEDIATE 'DROP TABLE ' || 'LatestUsedPattern';
   EXECUTE IMMEDIATE 'DROP TABLE ' || 'Iteration';
   EXECUTE IMMEDIATE 'DROP TABLE ' || 'Game';
   EXECUTE IMMEDIATE 'DROP TABLE ' || 'Pattern';
   EXECUTE IMMEDIATE 'DROP TABLE ' || 'Player';
EXCEPTION
   WHEN OTHERS THEN
      IF SQLCODE != -942 THEN
         RAISE;
      END IF;
END;
/

BEGIN
   EXECUTE IMMEDIATE 'DROP SEQUENCE ' || 'player_id_seq';
   EXECUTE IMMEDIATE 'DROP SEQUENCE ' || 'pattern_id_seq';
   EXECUTE IMMEDIATE 'DROP SEQUENCE ' || 'game_id_seq';
   EXECUTE IMMEDIATE 'DROP SEQUENCE ' || 'iteration_id_seq';
EXCEPTION
   WHEN OTHERS THEN
      IF SQLCODE != -2289 THEN
         RAISE;
      END IF;
END;
/

-------------------
-- CREATE TABLES --
-------------------

CREATE SEQUENCE player_id_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE pattern_id_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE game_id_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE iteration_id_seq START WITH 1 INCREMENT BY 1;

-- Primary

CREATE TABLE Player (
    player_id NUMBER PRIMARY KEY,
    player_name VARCHAR2(20)
);

CREATE TABLE Pattern (
    pattern_id NUMBER PRIMARY KEY,
    pattern_name VARCHAR2(40),
    pattern_description VARCHAR2(100),
    pattern_shape NVARCHAR2(4000)
);

CREATE TABLE Game (
    game_id NUMBER PRIMARY KEY,
    step_count NUMBER,
    player_id NUMBER,
    pattern_id NUMBER,
    FOREIGN KEY (player_id) REFERENCES Player(player_id) ON DELETE CASCADE,
    FOREIGN KEY (pattern_id) REFERENCES Pattern(pattern_id) ON DELETE CASCADE
);

CREATE TABLE Iteration (
    iteration_id NUMBER PRIMARY KEY,
    idx NUMBER,
    pattern_state NVARCHAR2(4000),
    game_id NUMBER,
    FOREIGN KEY (game_id) REFERENCES Game(game_id) ON DELETE CASCADE
);

-- Secondary

CREATE TABLE LatestUsedPattern (
    player_id NUMBER,
    pattern_id NUMBER,
    FOREIGN KEY (player_id) REFERENCES Player(player_id) ON DELETE CASCADE,
    FOREIGN KEY (pattern_id) REFERENCES Pattern(pattern_id) ON DELETE CASCADE,
    PRIMARY KEY (player_id, pattern_id)
);

-----------------
-- SEED TABLES --
-----------------

INSERT INTO Player VALUES (player_id_seq.NEXTVAL, 'Andy');
INSERT INTO Player VALUES (player_id_seq.NEXTVAL, 'Feri');
INSERT INTO Player VALUES (player_id_seq.NEXTVAL, 'Ema');

INSERT INTO Pattern VALUES (
    pattern_id_seq.NEXTVAL,
    'Glider',
    'A glider pattern that moves diagonally across the grid.',
    '     ' || CHR(10) || 
    '  X  ' || CHR(10) || 
    '   X ' || CHR(10) || 
    ' XXX ' || CHR(10) || 
    '     ' || CHR(10)
);

INSERT INTO Pattern VALUES (
    pattern_id_seq.NEXTVAL,
    'Blinker',
    'A blinker pattern that oscillates vertically on the grid.',
    '     ' || CHR(10) || 
    '     ' || CHR(10) || 
    ' XXX ' || CHR(10) || 
    '     ' || CHR(10) || 
    '     ' || CHR(10)
);

INSERT INTO Pattern VALUES (
    pattern_id_seq.NEXTVAL,
    'Block',
    'A block pattern that remains stable over generations.',
    '     ' || CHR(10) || 
    ' XX  ' || CHR(10) || 
    ' XX  ' || CHR(10) || 
    '     ' || CHR(10) || 
    '     ' || CHR(10)
);

INSERT INTO Pattern VALUES (
    pattern_id_seq.NEXTVAL,
    'Line',
    'Line of 5 cells.',
    '     ' || CHR(10) || 
    '     ' || CHR(10) || 
    'XXXXX' || CHR(10) || 
    '     ' || CHR(10) || 
    '     ' || CHR(10)
);

INSERT INTO Pattern VALUES (
    pattern_id_seq.NEXTVAL,
    'Smile',
    'A smiling face.',
    ' X X ' || CHR(10) || 
    '     ' || CHR(10) || 
    'X   X' || CHR(10) || 
    ' XXX ' || CHR(10) || 
    '     ' || CHR(10)
);

INSERT INTO Pattern VALUES (
    pattern_id_seq.NEXTVAL,
    'Empty',
    'No cells.',
    '     ' || CHR(10) || 
    '     ' || CHR(10) || 
    '     ' || CHR(10) || 
    '     ' || CHR(10) || 
    '     ' || CHR(10)
);

----------------
-- GAME LOGIC --
----------------

CREATE OR REPLACE FUNCTION getWidth(input_state NVARCHAR2) RETURN INT IS
BEGIN
    return INSTR(input_state, CHR(10)) - 1;
END getWidth;
/

CREATE OR REPLACE FUNCTION getHeight(input_state NVARCHAR2) RETURN INT IS
BEGIN
    return LENGTH(input_state) - LENGTH(REPLACE(input_state, CHR(10), ''));
END getHeight;
/

CREATE OR REPLACE FUNCTION getCell(input_state NVARCHAR2, y INT, x INT) RETURN NVARCHAR2 IS
    height INT := getHeight(input_state);
    width INT := getWidth(input_state);
    char_index INT;
    current_char NVARCHAR2(1);
BEGIN
    IF y < 0 OR y >= height THEN
        RETURN '';
    END IF;

     IF x < 0 OR x >= width THEN
        RETURN '';
    END IF;

    char_index := y * (width + 1) + x + 1;
    current_char := SUBSTR(input_state, char_index, 1);
    RETURN current_char;
END getCell;
/

CREATE OR REPLACE FUNCTION replaceCharOnBoard(board NVARCHAR2, x INT, y INT, new_char CHAR) RETURN NVARCHAR2 IS
    height INT := getHeight(board);
    width INT := getWidth(board);
    position INT := y * (width + 1) + x;
    new_board NVARCHAR2(4000);
BEGIN
    new_board := SUBSTR(board, 1, position - 1) || new_char || SUBSTR(board, position + 1);
    RETURN new_board;
END replaceCharOnBoard;
/

CREATE OR REPLACE FUNCTION putPatternOnBoard(input_state NVARCHAR2) RETURN NVARCHAR2 IS
    height INT := getHeight(input_state);
    width INT := getWidth(input_state);
    board NVARCHAR2(4000);
    current_char NVARCHAR2(1);
BEGIN
    board := 
    '          ' || CHR(10) ||
    '          ' || CHR(10) ||
    '          ' || CHR(10) ||
    '          ' || CHR(10) ||
    '          ' || CHR(10) ||
    '          ' || CHR(10) ||
    '          ' || CHR(10) ||
    '          ' || CHR(10) ||
    '          ' || CHR(10) ||
    '          ' || CHR(10);

    FOR i IN 0..height-1 LOOP
        FOR j IN 0..width-1 LOOP
            current_char := getCell(input_state, i, j);
            board := replaceCharOnBoard(board, j + CEIL((10 - width) / 2), i + CEIL((10 - height) / 2), current_char);
        END LOOP;
    END LOOP;
    RETURN board;
END putPatternOnBoard;
/

CREATE OR REPLACE FUNCTION countLiveNeighbors(input_state NVARCHAR2, y INT, x INT) RETURN INT IS
    live_count INT := 0;
    current_char NVARCHAR2(1);
BEGIN
    FOR i IN -1..1 LOOP
        FOR j IN -1..1 LOOP
            IF i != 0 OR j != 0 THEN
                current_char := getCell(input_state, y + i, x + j);
                IF current_char = 'X' THEN
                    live_count := live_count + 1;
                END IF;
            END IF;
        END LOOP;
    END LOOP;
    RETURN live_count;
END countLiveNeighbors;
/

CREATE OR REPLACE FUNCTION calculateNextState(input_state NVARCHAR2) RETURN NVARCHAR2 IS
    next_state NVARCHAR2(4000) := '';
    height INT;
    width INT;
    liveNeighbors INT;
    current_char NVARCHAR2(1);
BEGIN
    height := LENGTH(input_state) - LENGTH(REPLACE(input_state, CHR(10), ''));
    width := INSTR(input_state, CHR(10)) - 1;

    FOR i IN 0..height-1 LOOP
        FOR j IN 0..width-1 LOOP
            liveNeighbors := countLiveNeighbors(input_state, i, j);
            current_char := getCell(input_state, i, j);

            IF current_char = 'X' THEN
                IF liveNeighbors < 2 THEN
                    next_state := next_state || ' ';
                ELSIF liveNeighbors = 2 OR liveNeighbors = 3 THEN
                    next_state := next_state || 'X';
                ELSE
                    next_state := next_state || ' ';
                END IF;
            ELSE
                IF liveNeighbors = 3 THEN
                    next_state := next_state || 'X';
                ELSE
                    next_state := next_state || ' ';
                END IF;
            END IF;
        END LOOP;
        next_state := next_state || CHR(10);
    END LOOP;
    RETURN next_state;
END calculateNextState;
/

CREATE OR REPLACE FUNCTION step(current_state NVARCHAR2) RETURN NVARCHAR2 IS
    v_next_state_string NVARCHAR2(4000);
BEGIN
    v_next_state_string := calculateNextState(current_state);
    RETURN v_next_state_string;
END;
/

--------------
-- TRIGGERS --
--------------

-- Run game on game creation

CREATE OR REPLACE TRIGGER create_iteration_trigger
AFTER INSERT ON Game
FOR EACH ROW
DECLARE
    v_pattern_state NVARCHAR2(4000);
    v_padded_pattern_state NVARCHAR2(4000);
    v_next_pattern_state NVARCHAR2(4000);
BEGIN
    SELECT pattern_shape INTO v_pattern_state
    FROM Pattern
    WHERE pattern_id = :NEW.pattern_id;

    v_padded_pattern_state := putPatternOnBoard(v_pattern_state);

    INSERT INTO Iteration VALUES (iteration_id_seq.NEXTVAL, 1, v_padded_pattern_state, :NEW.game_id);

    FOR i IN 2..:NEW.step_count LOOP
        v_next_pattern_state := step(v_padded_pattern_state);

        IF v_next_pattern_state = v_padded_pattern_state THEN
            EXIT;
        END IF;

        INSERT INTO Iteration VALUES (iteration_id_seq.NEXTVAL, i, v_next_pattern_state, :NEW.game_id);

        v_padded_pattern_state := v_next_pattern_state;
    END LOOP;
END;
/

-- Latest used pattern by player

CREATE OR REPLACE TRIGGER update_latest_used_pattern
AFTER INSERT ON Game
FOR EACH ROW
BEGIN
    DELETE FROM LatestUsedPattern
    WHERE player_id = :NEW.player_id;

    INSERT INTO LatestUsedPattern (player_id, pattern_id)
    VALUES (:NEW.player_id, :NEW.pattern_id);
END;
/

-------------
-- CURSORS --
-------------

-- Print iterations of a single game

CREATE OR REPLACE PROCEDURE print_game(game_id INT) IS
  CURSOR iterations IS SELECT * FROM Iteration WHERE game_id = game_id;
BEGIN
  FOR iteration IN iterations LOOP
    DBMS_OUTPUT.PUT_LINE(iteration.pattern_state);
  END LOOP;
END;
/

-- Generate games for each pattern

CREATE OR REPLACE PROCEDURE add_games_for_patterns IS
  CURSOR patterns IS SELECT * FROM Pattern;
BEGIN
  FOR pattern IN patterns LOOP
    INSERT INTO Game (game_id, step_count, player_id, pattern_id)
    VALUES (
        game_id_seq.NEXTVAL,
        10,
        (SELECT player_id FROM (SELECT player_id FROM Player ORDER BY DBMS_RANDOM.RANDOM) WHERE ROWNUM = 1),
        pattern.pattern_id
    );
  END LOOP;
END;
/

--------------------
-- GENERATE GAMES --
--------------------

BEGIN
  add_games_for_patterns;
END;
/

-- Generate random games

BEGIN
    FOR i IN 1..10 LOOP
        INSERT INTO Game (game_id, step_count, player_id, pattern_id)
        VALUES (
            game_id_seq.NEXTVAL,
            ROUND(DBMS_RANDOM.VALUE(5, 10)),
            (SELECT player_id FROM (SELECT player_id FROM Player ORDER BY DBMS_RANDOM.RANDOM) WHERE ROWNUM = 1),
            (SELECT pattern_id FROM (SELECT pattern_id FROM Pattern ORDER BY DBMS_RANDOM.RANDOM) WHERE ROWNUM = 1)
        );
    END LOOP;
    COMMIT;
END;
/

------------
-- SELECT --
------------

-- Games with patterns that terminate sooner than requested

SELECT 
    g.game_id, 
    p.pattern_name, 
    g.step_count as requested, 
    i.iteration_count as actual
FROM 
    Game g
JOIN 
    Pattern p ON g.pattern_id = p.pattern_id
LEFT JOIN (
    SELECT 
        game_id, 
        COUNT(*) AS iteration_count
    FROM 
        Iteration
    GROUP BY 
        game_id
) i ON g.game_id = i.game_id
WHERE 
    i.iteration_count < g.step_count;

-- Patterns and the number of player that have run them at least once

SELECT 
    p.pattern_id,
    p.pattern_name, 
    COUNT(DISTINCT g.player_id) AS player_count
FROM 
    Pattern p
JOIN 
    Game g ON p.pattern_id = g.pattern_id
GROUP BY 
    p.pattern_id, p.pattern_name;

-- Players that have tried at least three patterns

SELECT 
    p.player_id, 
    p.player_name, 
    COUNT(DISTINCT g.pattern_id) AS pattern_count
FROM 
    Player p
JOIN 
    Game g ON p.player_id = g.player_id
GROUP BY 
    p.player_id, p.player_name
HAVING 
    COUNT(DISTINCT g.pattern_id) >= 3;

-- Get all games of given pattern

SELECT
    g.game_id,
    g.step_count,
    p.pattern_id,
    p.pattern_name
FROM
    Game g
JOIN
    Pattern p ON g.pattern_id = p.pattern_id
WHERE
    p.pattern_name = 'Glider';

-- Get all games of patterns

SELECT
    p.pattern_name,
    g.game_id,
    g.step_count
FROM
    Game g
JOIN
    Pattern p ON g.pattern_id = p.pattern_id
ORDER BY
    p.pattern_name,
    g.step_count;

-- Show latest used pattern by player

SELECT 
    p.player_name, pt.pattern_name
FROM 
    Player p
JOIN 
    LatestUsedPattern lup ON p.player_id = lup.player_id
JOIN 
    Pattern pt ON lup.pattern_id = pt.pattern_id;

-- Get all iterations of given game

SELECT
    i.idx,
    i.pattern_state
FROM
    iteration i
WHERE
    i.game_id = 1
ORDER BY
    i.idx;

-- Patterns with game id with most iterations

SELECT
    p.pattern_id,
    p.pattern_name,
    g.game_id
FROM
    Pattern p
JOIN (
    SELECT
        g.pattern_id,
        MAX(i.iteration_id) AS max_iterations
    FROM
        Game g
    JOIN
        Iteration i ON g.game_id = i.game_id
    GROUP BY
        g.pattern_id
) max_iter ON p.pattern_id = max_iter.pattern_id
JOIN
    Game g ON p.pattern_id = g.pattern_id
JOIN
    Iteration i ON g.game_id = i.game_id
WHERE
    i.iteration_id = max_iter.max_iterations
ORDER BY
    p.pattern_id;

---------------
-- GAME OVER --
---------------
