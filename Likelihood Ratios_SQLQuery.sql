-- **************** This Routine Calculates Likelihood Ratios ***************

DROP TABLE #temp
SELECT * INTO #temp FROM [dbo].[DxAge_1] -- 4233546 rows
INSERT INTO #temp SELECT * FROM [dbo].[DxAge_2] -- 5223128 rows
INSERT INTO #temp SELECT * FROM [dbo].[DxAge_3] -- 4179754 rows
INSERT INTO #temp SELECT * FROM [dbo].[DxAge_4] -- 3807014 rows
DROP TABLE dbo.final
SELECT CAST([id] as int) as id
      , [icd9]
      , CASE AgeAtDx
              WHEN 'NULL' THEN null
              ELSE CAST(AgeAtDx as float) END as AgeAtDx
      , CASE AgeAtFirstDM
              WHEN 'NULL' THEN null
              ELSE CAST(AgeAtFirstDM as float) END as [AgeAtFirstDM]
      , CASE AgeAtDeath
              WHEN 'NULL' THEN null
              ELSE CAST(AgeAtDeath as float) END as [AgeAtDeath]
INTO dbo.final
FROM #temp
*/
SELECT Count(*) FROM dbo.final --(17,443,442 rows)
-- Identify zombies
DROP TABLE #Z
SELECT DISTINCT Id
INTO #Z
FROM dbo.final
WHERE AgeAtDeath<AgeAtDx -- Death before Dx
GROUP BY ID
SELECT TOP 5 * FROM #Z ORDER BY id DESC
/*
Id
828364
827342
825881
804070
799179
*/
-- 168 unique patients with wrong date of death
-- Exclude zombies from final table
DROP TABLE #data
SELECT a.*
INTO #data
FROM dbo.final a left join #Z b ON a.id=b.id
WHERE b.id is null
SELECT TOP 3 * FROM #data order by ID
-- (17,432,694 row(s) affected)
/*
id     icd9   AgeAtDx       AgeAtFirstDM  AgeAtDeath
1      I292.0 69.166666     NULL          NULL
1      I304.10       69.166666     NULL          NULL
1      IV62.4 69.166666     NULL          NULL
*/
-- Remove patients with more than 365 diagnosis in a year and diagnosis with age being wrong
DROP TABLE #Data2
SELECT DISTINCT ID
INTO #Data2
FROM #Data
GROUP BY ID, Cast(AgeAtDx as Int)
HAVING Count(Icd9) >365
SELECT TOP 3 * FROM #Data2
-- (56 row(s) affected)
/*
ID
14063
23314
32692
*/
DROP TABLE #Data3
SELECT a.*
INTO #Data3
FROM #Data a left join #Data2 b on a.id=b.id
WHERE b.id is null and AgeAtDx is not null AND AgeAtDx >0 
-- removing also problems with age at diagnosis
SELECT TOP 3 * FROM #Data3 WHERE AGeAtDx<0
-- 17,432,694 is reduced to 17,379,713 reduced to 17,379,218
/*
ID            icd9   	AgeAtDx       AgeAtFirstDM  AgeAtDeath
270780 	IV66.7 	71.5   	NULL           NULL
270780 	I294.20       71.5   	NULL           NULL
270780 	I518.81       71.5   	NULL           NULL
*/
-- Select training and validation set
SELECT *
INTO dbo.training
FROM #Data3
WHERE Rand(ID) <=.8
SELECT TOP 5 * FROM dbo.training WHERE ID=467828
-- (13,760,073 row(s) affected)
/*
ID            icd9   	AgeAtDx       AgeAtFirstDM  AgeAtDeath
467828 	IE850.2       65.166666     NULL		68.083333
467828 	I515.  	66.333333     NULL         	68.083333
467828 	I162.9 	66.333333     NULL         	NULL
467828 	I276.1 	66.333333     NULL         	NULL
467828 	I300.00       65     	NULL   	NULL
*/
 -- Find unique IDs in training set
DROP TABLE #trainID
SELECT DISTINCT ID
INTO #trainID
FROM dbo.training
--  (657,885 row(s) affected)
-- Create Validation set
SELECT a.*
INTO dbo.vSet 
FROM #Data3 a left join #trainID b ON a.id=b.id
WHERE b.id is null
-- (3619145 row(s) affected)
 -- Calculate # dead and # alive in training set
DROP TABLE #cnt1
select ID, CASE WHEN Max(ageatdeath)>0 THEN 1 ELSE 0 END AS Dead
       , CASE WHEN Max(ageatdeath)>0 THEN 0 ELSE 1 END AS Alive
       , CASE WHEN Max(AgeAtDeath) IS NULL THEN 1 ELSE 0 END AS Alive2
INTO #cnt1
FROM dbo.training
GROUP BY ID
SELECT TOP 3 * FROM #cnt1
/*
ID	            Dead   Alive  Alive2
148916 		0	1	1
158491 		0	1	1
535221 		0	1	1
*/
-- (657885 row(s) affected)
DROP TABLE #cnt2
SELECT SUM(Alive) AS PtsAlive, Sum(Dead) AS PtsDead
INTO #Cnt2
FROM #cnt1
SELECT * FROM #Cnt2
 /* Unique patients alive or Dead
PtsAlive      PtsDead
545175 	112710
*/
-- ******** Calculate Likelihood Ratio *********
-- Select patients who died 6 month after diagnosis
DROP TABLE #DeadwDx
SELECT ICD9, count(distinct ID) as PtsDead6
INTO #DeadwDx
FROM dbo.training
WHERE AgeatDeath-AgeatDx<=.5 -- This is 6 months in age measured in years
GROUP BY ICD9
SELECT TOP 5 * FROM #DeadwDx
/*
I788.30       1121
I611.71       3
I974.4 	5
I786.1 	48
I386.03       1
*/
-- (6400 row(s) affected)
-- Select diagnosis where patient did not die or did not die within 6 months
DROP TABLE #AlivewDx
SELECT ICD9, count(distinct ID) as PtsAlive6
INTO #AlivewDx
FROM dbo.training
WHERE AgeatDeath-AgeatDx>.5 or AgeAtDeath is null -- Not dead in 6 months or not dead
GROUP BY ICD9
SELECT TOP 5 * FROM #AlivewDx ORDER BY ICD9
/*
ICD9   PtsAlive6
I001.0 1
I001.9 1
I002.0 1
I003.0 118
I003.1 28
*/
--(10431 row(s) affected)
-- Combine the tables for dead and alive patients
Drop Table #Dx
SELECT CASE a.Icd9 WHEN null THEN b.icd9 ELSE a.icd9 END as icd9
, PtsDead6
, PtsAlive6
INTO #Dx
FROM #alivewDx a FULL OUTER JOIN #DeadwDx b
       ON a.icd9=b.icd9 --Full join keeps record even if not in either table
SELECT TOP 5 * FROM #Dx
/*
icd9   PtsDead6      PtsAlive6
IV58.72       27  	1085
I747.64       NULL  	18
IV14.2 	42   	673
I733.14       137	 290
I211.5 	12	187
*/
-- (10480 row(s) affected)
-- Calculate Likelihood Ratios
-- Set LR to maximum when all in DX are dead
-- Set LR to minimum when all in Dx are alive
SELECT Icd9
, PtsDead6
, PtsAlive6
, PtsDead
, PtsAlive
, CASE
       WHEN PtsAlive6 is null THEN PtsDead6+1
       WHEN PtsAlive6=0 THEN PtsDead6+1
       WHEN PtsDead6 is null THEN 1/(PtsAlive6 +1)
       WHEN PtsDead6= 0 THEN 1/(PtsAlive6 +1)
       ELSE
       (cast(PtsDead6 as float)/Cast(PtsDead as float))/(Cast(PtsAlive6 as Float)/Cast(PtsAlive As Float)) END AS LR 
-- % of Dx among dead divided by % of Dx among alive patients
INTO dbo.LR
FROM #Dx cross join #Cnt2
SELECT top 10 * FROM dbo.LR ORDER BY LR desc
/*
Icd9   PtsDead6      PtsAlive6     PtsDead       PtsAlive      LR
I798.2 	3  	     	1      112710 545175 14.5109129624701
I853.05       3      	1      112710 545175 14.5109129624701
I183.2 	2         	1      112710 545175 9.67394197498004
I798.9 	2 		1      112710 545175 9.67394197498004
I852.05       2 		1      112710 545175 9.67394197498004
I194.8 	2   		1      112710 545175 9.67394197498004
I718.59       2    		1      112710 545175 9.67394197498004
I960.7 	2  		1      112710 545175 9.67394197498004
I862.21       2       	1      112710 545175 9.67394197498004
I531.21       2 		1      112710 545175 9.67394197498004
*/
--(10480 row(s) affected)
-- *********************** End of calculation of LR for single Diagnosis ************

 
 
-- **************Calculate LR for combinations*****************
 
-- Select distinct ICD codes for each person ( no repeats of same diagnosis)
DROP TABLE #temp
SELECT DISTINCT ID, ICD9, Max(AgeAtDeath) as AgeDeath
INTO #temp
FROM dbo.training
GROUP BY ID, ICD9
SELECT TOP 5 * from #temp WHERE ID='86154'
/*
ID     ICD9   AgeDeath
86154  I368.2 	NULL
86154  I378.54       NULL
86154  I493.20       NULL
86154  IV15.3 	NULL
86154  IE933.1       NULL
*/
-- (8,130,674 row(s) affected)
 
-- concatenate dx codes
DROP TABLE #list 
SELECT id, Max(ageDeath) as Death,  STUFF((SELECT ',' +x.icd9 FROM #temp x
WHERE x.id=y.id ORDER BY icd9 for xml path ('')), 1,1,'') AS ICD9List
INTO #list
FROM #temp y
GROUP BY id
ORDER BY id ASC
  -- (657885 row(s) affected)
 
-- Select patients who died and had the combination of the diagnoses
DROP TABLE #DeadwDx
SELECT ICD9list, count(distinct ID) as PtsDead
INTO #DeadwDx
FROM #list
WHERE Death >0
GROUP BY ICD9list
 
-- Among people who are alive Select list of diagnoses
DROP TABLE #AlivewDx
SELECT ICD9list, count(distinct ID) as PtsAlive
INTO #AlivewDx
FROM #list
WHERE Death is null
GROUP BY ICD9list

-- Combined files for dead and alive patients
Drop Table #Dx
SELECT CASE a.Icd9list WHEN null THEN b.icd9list ELSE a.icd9list END as icd9list
, DeadwDx
, AlivewDx
INTO #Dx
FROM #alivewDx a FULL OUTER JOIN #DeadwDx b
       ON a.icd9list=b.icd9list --Full join keeps record even if not in either table
SELECT TOP 5 * FROM #Dx

-- Calculate Likelihood Ratios
-- Set LR to maximum when all in DX are dead
-- Calculate LR for combination of diagnoses
SELECT Icd9List
, DeadwDx
, AlivewDX
, PtsDead
, PtsAlive
, CASE
       WHEN AlivewDx is null THEN DeadwDx+1
       WHEN AlivewDx=0 THEN DeadwDx+1
       WHEN DeadwDx is null THEN 1/(AlivewDx +1)
       WHEN DeadwDx=0 THEN 1/(AlivewDx +1)
       ELSE
       (cast(DeadwDx as float)/Cast(PtsDead as float))/(Cast(AlivewDx as Float)/Cast(PtsAlive As Float)) END AS LRList 
-- % of Dx among dead divided by % of Dx among alive patients
INTO dbo.LRList
FROM #Dx cross join #Cnt2
SELECT top 10 * FROM dbo.LRList ORDER BY LRList desc

-- *********************  This ends calculation of LR for list of Dx
