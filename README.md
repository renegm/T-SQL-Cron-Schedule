# T-SQL-Cron-Schedule
Sql server function to evaluate Schedules Cron-alike
--------

The function receives two params: `@Dt datetime2`, the date to verify and a `@Schedule varchar(8000)`.  `@Schedule` is a Boolean expression of SingleSchedule, each one of them is cron-like. If `@Schedule` is malformed return null or Bit 1/0 when match/no match. All Boolean operators permited  |(OR), &(AND), ^(XOR) and ~(NOT) and parenthesis for grouping.

A SingleSchedule string has up 4 fields, spaces separated, using a like Cron syntax but there’s not field for minute:
### Fields
Field1 Field2 Field3 Field4
* Field1: Hours (Scope 0-23)
* Field2: Day of month (Scope 1-31) plus a special value 32 meaning EndOfMonth
* Field3: Month (Scope 1-12)
* Field4: Day of the week (1-7) 1=Sunday, 2=Monday…, 7=Saturday

### Spaces and "Huffman code" for fields
Spaces are ignored everywhere except between Fields. It is valid to use as many as desired. Tabs and line breaks are considered spaces (chars 9,10,13).

Unlike Cron, fields are optional.  Always Field1 is for Hour, Field2 day… Missing fields will be considered "Everything" (**`*`**) So **`8`** (only the hour field) is the same as **`8 * * *`**, and **`9 5`** is the same as **`9 5 * *`**. Empty string is also everything (all fields omitted)

### Tokens
Like Cron, each field is a list of tokens, comma separated with similar rules

### Rules.
A token can be:
* A single element:
  1. **`N`** a number in then scope of Field (0 to 23 in Field1, etc)
  2. **`*`**  an asterisk, means everything
  3. **`32`** Only permited in Field2, means EndOfMonth
* A Step, two numbers separated by `/` (slash)
  1. **`N/M`** means the succession “from N each M”: N, N+M, N+2M…
  2. **`*/M`** same as before and * means the beginning of scope 0 for hour, 1 otherwise
  3. N must be in scope and M>0
* A Range, two numbers separated by `–`(minus)
  1. **`32-N`** In field1 means “Last N days of the month” 
  2. **`N-M`** means From **`N`** to **`M`**
  3. **`N`** and **`M`** must be on scope and **`N<=M`** except point (1) for Days Field
  
If a token fails a rule (a range 5-1 or 45-50) the whole expression fails and function will return null.

Syntax is based on Cron. But there’s some important differences.
* Algebra of SingleSchedule. No Cron, as far as I know, permit that.
* 32 to indicate Eomonth. 
* No minute field.
* Most Cron use 0-6 for Day of the week starting Monday. Function follow SQL default 1-7 starting Sunday.
* The grandfather of crons, Vixie Cron was written as a char level parser, not token level with some faulty logic: when firstchar = \* means something like "don’t use this filter" instead of "use the full range". Also, Cron evaluates Field2 (Day of month) and Field4 (Day of the week) as OR. As a result, in Cron `30 8 *,1 * 1` means 8:30 every Monday but `30 8 1,* * 1`. ([crontab.guru - Cron bug](https://crontab.guru/cron-bug.html))

In summary. To evaluate a `@Dt` vs a SingleSchedule Field1, Field2...
* For each Field all tokens in his list are evaluated, if any returns NULL the entire expression returns NULL because it indicates an error. If at least 1 token returns True that field is True. Order of a list is irrelevant.
* If all present Fields are true, the result is true.

To evaluate the `@Schedule` each SingleSchedule inside is evaluated and then, the `@Schedule` boolean expression.

### Examples for SingleSchedule:




* **`*`** Everything
* **`2`**	At 2:00AM
* **`10 * * 1`**    10:00AM every Sunday
* **`* 1-7,15 1-3,7-9 2`** 	Every hour, days 1 to 7 or 15, 1st and 3rd Quarters, Monday
* **`14-18 32-7 * 3`**	Between 2Pm and 6pm last Tuesday of every month
10 8-14 * 1	10AM, Second Sunday every month

Examples for Booleans Schedule
Schedule		Explanation 
Second to last Sunday.	* 32-14 * 1&~* 32-7 * 1	 (Last two Sundays) AND Not(last Sunday.)

Closest workday to day 15
	* 14,15 * 6|* 15,16 * 2	
The second weekend (Saturday, Sunday) contained entirely in the month	9-14 * 1,7|* 8 * 7| * 15 * 1	First weekend can be 1,2 and second 8,9… until First 7,8 and second 14,15. So our second weekend is 
8,9 (8 Saturday) 
or 14,15(15 Sunday) 
or belongs to 9-14 entirely
Last weekend day other than the end of the month	(* 32-7 * 1|* 32-2 * 7)&~* 32  	Saturday on last 2 days or last Sunday. Except EoMonth
nth Monday  of nth quarter	* 1-7 1-3 2|* 8-14 4-6 2|* 15-21 7-9 2|* 22-28 10-12 2	

