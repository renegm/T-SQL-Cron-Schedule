CREATE OR ALTER FUNCTION Tools.CheckSchedule (@Dt datetime2(0), @Schedule varchar(8000))
/*
https://github.com/renegm/T-SQL-Cron-Schedule
*/
RETURNS bit
AS
BEGIN
    /*--#region Cleanup and simple checks*/
    IF @Schedule IN ( '', '*', '* *', '* * *', '* * * *' ) RETURN 1; /*Trivial Schedules*/
    SELECT @Schedule = REPLACE(@Schedule, CHAR(9), ' ')
         , @Schedule = REPLACE(@Schedule, CHAR(10), ' ')
         , @Schedule = REPLACE(@Schedule, CHAR(13), ' ');
    IF @Schedule LIKE '%[^|&^~)(0-9, */-]%' RETURN NULL; /*Wrong character*/
    SELECT @Schedule = LTRIM(@Schedule)
         , @Schedule = RTRIM(@Schedule)
         , @Schedule = REPLACE(@Schedule, REPLICATE(' ', 87), ' ')
         , @Schedule = REPLACE(@Schedule, REPLICATE(' ', 12), ' ')
         , @Schedule = REPLACE(@Schedule, REPLICATE(' ', 4), ' ')
         , @Schedule = REPLACE(@Schedule, REPLICATE(' ', 2), ' ')
         , @Schedule = REPLACE(@Schedule, REPLICATE(' ', 2), ' ')
         , @Schedule = REPLACE(@Schedule, REPLICATE(' ', 2), ' ')
         , @Schedule = REPLACE(@Schedule, ' |', '|')
         , @Schedule = REPLACE(@Schedule, '| ', '|')
         , @Schedule = REPLACE(@Schedule, ' &', '&')
         , @Schedule = REPLACE(@Schedule, '& ', '&')
         , @Schedule = REPLACE(@Schedule, ' ^', '^')
         , @Schedule = REPLACE(@Schedule, '^ ', '^')
         , @Schedule = REPLACE(@Schedule, ' ~', '~')
         , @Schedule = REPLACE(@Schedule, '~ ', '~')
         , @Schedule = REPLACE(@Schedule, ' )', ')')
         , @Schedule = REPLACE(@Schedule, ') ', ')')
         , @Schedule = REPLACE(@Schedule, ' (', '(')
         , @Schedule = REPLACE(@Schedule, '( ', '(')
         , @Schedule = REPLACE(@Schedule, ' ,', ',')
         , @Schedule = REPLACE(@Schedule, ', ', ',');
    /*--#endregion  Cleanup and simple checks*/
    DECLARE @Limits table (
        Id    int NOT NULL PRIMARY KEY
      , MnTkn int NOT NULL
      , MxTkn int NOT NULL
      , Vdt   int NOT NULL
    );
    INSERT INTO @Limits (Id, MnTkn, MxTkn, Vdt)
    VALUES (0, 0, 23, DATEPART(HOUR, @Dt))
         , (1, 1, 31, DATEPART(DAY, @Dt))
         , (2, 1, 12, DATEPART(MONTH, @Dt))
         , (3, 1, 7, (DATEPART(WEEKDAY, @Dt) + @@DATEFIRST - 1) % 7 + 1);
    DECLARE @EoMonth     int           = DAY(EOMONTH(@Dt, 0))
          , @Return      bit
          , @Infix       varchar(8000) = ''
          , @StartLen    int           = 8001
          , @EndLen      int           = 8000
          , @Pos         int
          , @subSchedule varchar(8000)
          , @IsOper      bit           = IIF(@Schedule LIKE '[)(~&^|]%', 1, 0);
    WHILE @Schedule > ''
    BEGIN
        SELECT @Pos = IIF(@IsOper = 1, PATINDEX('%[^)(~&^|]%', @Schedule), PATINDEX('%[)(~&^|]%', @Schedule)) - 1
             , @subSchedule = IIF(@Pos > 0, LEFT(@Schedule, @Pos), @Schedule);
        IF @IsOper = 0
            IF @subSchedule IN ( '', '*', '* *', '* * *', '* * * *' ) SET @Return = 1;
            ELSE
                /* --#region Main Eval */
                WITH T AS
                (SELECT [Key] AS Id, Value AS Token FROM OPENJSON('["' + REPLACE(@subSchedule, ' ', '","') + '"]')WHERE [Key] < 5)
                   , B AS
                (   SELECT T.Id
                         , CASE WHEN T.Id > 3 THEN NULL                                                         /* Extra fields*/
                                WHEN K.value = '*' THEN 1                                                       /* trivial * */
                                WHEN K.value = '' OR Q.L = '' OR Q.R = '' THEN NULL                             /* empty*/
                                WHEN NOT (Q.Lv = 32 AND T.Id = 1 OR Q.Lv BETWEEN M.MnTkn AND M.MxTkn) THEN NULL /* L out of range*/
                                WHEN Q.R LIKE '%[^0-9]%' THEN NULL                                              /* R must be a number or null*/
                                /* Start single value */
                                WHEN Q.ndx = 0 AND Q.Lv = 32 AND T.Id = 1 AND M.Vdt = @EoMonth THEN 1           /* Eomonth match*/
                                WHEN Q.ndx = 0 AND Q.Lv = M.Vdt THEN 1                                          /* ndx 0 Match*/
                                WHEN Q.ndx = 0 THEN 0                                                           /* ndx 0 No Match*/
                                /* Start steps. if L='*' Lv already set to MnTkn */
                                WHEN Q.Separator = '/' AND (Q.Lv = 32 OR Q.Rv = 0) THEN NULL                    /* L out of range (32 not valid on steps) or R=0 */
                                WHEN Q.Separator = '/' AND M.Vdt < Q.Lv THEN 0                                  /* before steps*/
                                WHEN Q.Separator = '/' THEN 1 - SIGN((M.Vdt - Q.Lv) % Q.Rv)                     /* eval steps*/
                                /* start range. */
                                WHEN Q.L = '*' THEN NULL                                                        /* L must be a number*/
                                WHEN Q.Rv NOT BETWEEN M.MnTkn AND M.MxTkn THEN NULL                             /* R out of range*/
                                WHEN Q.Lv = 32 AND M.Vdt BETWEEN @EoMonth - Q.Rv + 1 AND @EoMonth THEN 1        /* last R days match */
                                WHEN Q.Lv = 32 THEN 0                                                           /* last R days No match*/
                                WHEN Q.Lv > Q.Rv THEN NULL                                                      /* Bad range*/
                                WHEN M.Vdt BETWEEN Q.Lv AND Q.Rv THEN 1                                         /* range match*/
                                ELSE 0                                                                          /* range No match*/ END AS Eval
                      FROM T
                      LEFT JOIN @Limits AS M ON M.Id = T.Id
                     CROSS APPLY STRING_SPLIT(T.Token, ',') AS K
                     CROSS APPLY
                          (   SELECT C.ndx
                                   , L.L
                                   , R.R
                                   , SUBSTRING(K.value, C.ndx, 1) AS Separator
                                   , IIF(L.L = '*', M.MnTkn, TRY_CAST(L.L AS int)) AS Lv
                                   , IIF(K.value = '*', M.MxTkn, TRY_CAST(R.R AS int)) AS Rv
                                FROM (VALUES (PATINDEX('%[/-]%', K.value))) AS C (ndx)
                               CROSS APPLY (VALUES (IIF(C.ndx > 0, LEFT(K.value, C.ndx - 1), K.value))) AS L (L)
                               CROSS APPLY (VALUES (IIF(C.ndx > 0, STUFF(K.value, 1, C.ndx, ''), NULL))) AS R (R) ) AS Q )
                   , F AS
                (SELECT B.Id, MIN(IIF(B.Eval IS NULL, 0, 1)) AS Flag, MAX(B.Eval) AS Eval FROM B GROUP BY B.Id)
                SELECT @Return = IIF(MIN(F.Flag) = 0, NULL, MIN(F.Eval))FROM F;
        /* --#endregion  Main Eval */
        SELECT @Infix = @Infix + CASE WHEN @IsOper = 1 AND @Pos > 0 THEN LEFT(@Schedule, @Pos)
                                      WHEN @IsOper = 1 THEN @Schedule
                                      ELSE CAST(@Return AS char(1))END
             , @Schedule = IIF(@Pos > 0, STUFF(@Schedule, 1, @Pos, ''), '')
             , @IsOper = ~ @IsOper;
        IF @Infix IS NULL
            RETURN NULL /*Infix is null when @Return is null because error on subschedule*/;
    END;
    SELECT @Infix = REPLACE(@Infix, '()', '1'), @Infix = REPLACE(@Infix, '~~', '');
    BEGIN
        SET @StartLen = @EndLen;
        WHILE @Infix LIKE '%[01]&[01]%' OR @Infix LIKE '%([01])%' OR @Infix LIKE '~[01]'
            SELECT @Infix = REPLACE(@Infix, '~0', '1')
                 , @Infix = REPLACE(@Infix, '~1', '0')
                 , @Infix = REPLACE(@Infix, '0&0', '0')
                 , @Infix = REPLACE(@Infix, '0&1', '0')
                 , @Infix = REPLACE(@Infix, '1&0', '0')
                 , @Infix = REPLACE(@Infix, '1&1', '1')
                 , @Infix = REPLACE(@Infix, '(0)', '0')
                 , @Infix = REPLACE(@Infix, '(1)', '1');
        WHILE @Infix LIKE '%[01][|^][01]%' OR @Infix LIKE '%([01])%' OR @Infix LIKE '~[01]'
            SELECT @Infix = REPLACE(@Infix, '0|0', '0')
                 , @Infix = REPLACE(@Infix, '0|1', '1')
                 , @Infix = REPLACE(@Infix, '1|0', '1')
                 , @Infix = REPLACE(@Infix, '1|1', '1')
                 , @Infix = REPLACE(@Infix, '0^0', '0')
                 , @Infix = REPLACE(@Infix, '0^1', '1')
                 , @Infix = REPLACE(@Infix, '1^0', '1')
                 , @Infix = REPLACE(@Infix, '1^1', '0')
                 , @Infix = REPLACE(@Infix, '~0', '1')
                 , @Infix = REPLACE(@Infix, '~1', '0')
                 , @Infix = REPLACE(@Infix, '(0)', '0')
                 , @Infix = REPLACE(@Infix, '(1)', '1');
        SET @EndLen = LEN(@Infix);
    END;
    RETURN IIF(@EndLen > 1, NULL, TRY_CAST(@Infix AS bit));
END;
GO