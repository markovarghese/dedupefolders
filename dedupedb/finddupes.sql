USE dedupedb;
GO
CREATE TABLE dirs
([id]            INT NOT NULL IDENTITY(1, 1) PRIMARY KEY, 
 [fullname]      VARCHAR(300) NOT NULL, 
 [name]          VARCHAR(300) NOT NULL, 
 [mode]          VARCHAR(20) NOT NULL, 
 [creationtime]  DATETIME2, 
 [lastwritetime] DATETIME2 NOT NULL, 
 filelength      BIGINT NOT NULL, 
 [dirid]         INT NOT NULL
);
CREATE TABLE files
([id]            INT NOT NULL IDENTITY(1, 1) PRIMARY KEY, 
 [fullname]      VARCHAR(300) NOT NULL, 
 [name]          VARCHAR(300) NOT NULL, 
 [mode]          VARCHAR(20) NOT NULL, 
 [creationtime]  DATETIME2, 
 [lastwritetime] DATETIME2 NOT NULL, 
 filelength      BIGINT NOT NULL, 
 [dirid]         INT NOT NULL
);
INSERT INTO dirs
([fullname], 
 [name], 
 [mode], 
 [creationtime], 
 [lastwritetime], 
 filelength, 
 [dirid]
)
       SELECT D.[FullName], 
              D.[Name], 
              D.[Mode], 
              D.[CreationTime], 
              D.[LastWriteTime], 
              0, 
              0
       FROM dbo.filefolderinfo D
       WHERE D.[Mode] LIKE 'd%'
       ORDER BY 1;
INSERT INTO files
([fullname], 
 [name], 
 [mode], 
 [creationtime], 
 [lastwritetime], 
 filelength, 
 [dirid]
)
       SELECT D.[FullName], 
              D.[Name], 
              D.[Mode], 
              D.[CreationTime], 
              D.[LastWriteTime], 
              D.[Length], 
              0
       FROM dbo.filefolderinfo D
       WHERE D.[Mode] NOT LIKE 'd%'
       ORDER BY 1;
CREATE INDEX IUX1_dirs ON dirs([fullname]) INCLUDE([name]);
CREATE INDEX IUX1_files ON files([fullname]) INCLUDE([name]);
CREATE INDEX IX2_files ON files([dirid]) INCLUDE([filelength], [name]);
CREATE INDEX IX2_dirs ON dirs([numfiles]);

--populate the dirs of dirs and files
UPDATE D
  SET 
      D.dirid = DD.[id]
FROM dirs D
     INNER JOIN dirs DD ON DD.fullname = LEFT(D.[fullname], LEN(D.[fullname]) - 1 - LEN(D.[name]));
UPDATE F
  SET 
      F.dirid = DD.[id]
FROM files F
     INNER JOIN dirs DD ON DD.fullname = LEFT(F.[fullname], LEN(F.[fullname]) - 1 - LEN(F.[name]));
ALTER TABLE dirs
ADD numfiles INT NOT NULL
                 DEFAULT 0;
--populate the size of dirs
UPDATE D
  SET 
      D.filelength = F.filelength, 
      D.numfiles = F.numfiles
FROM dirs D
     INNER JOIN
(
    SELECT FF.dirid, 
           SUM(FF.filelength) AS filelength, 
           COUNT(*) AS numfiles
    FROM files FF
    GROUP BY FF.dirid
) F ON F.dirid = D.id;

--store the comparison results
CREATE TABLE dbo.comparefolders
([id]   INT NOT NULL IDENTITY(1, 1) PRIMARY KEY, 
 [id_a] INT NOT NULL, 
 [id_b] INT NOT NULL, 
 diff   BIGINT NULL, 
 pos    BIGINT NULL, 
 neg    BIGINT NULL
);
INSERT INTO dbo.comparefolders
([id_a], 
 [id_b], 
 diff, 
 pos, 
 neg
)
       SELECT A.[id] AS [id_a], 
              B.[id] AS [id_b], 
              diffposneg.diff, 
              diffposneg.pos, 
              diffposneg.neg
       FROM dirs A
            INNER JOIN dirs B ON A.id < B.id
            CROSS APPLY
       (
           SELECT SUM(CASE
                          WHEN AA.[name] IS NOT NULL
                               AND BB.[name] IS NOT NULL
                          THEN AA.[filelength] + BB.[filelength]
                          ELSE 0 - ISNULL(AA.[filelength], 0) - ISNULL(BB.[filelength], 0)
                      END) AS diff, 
                  SUM(CASE
                          WHEN AA.[name] IS NOT NULL
                               AND BB.[name] IS NOT NULL
                          THEN AA.[filelength] + BB.[filelength]
                          ELSE 0
                      END) AS pos, 
                  SUM(CASE
                          WHEN AA.[name] IS NOT NULL
                               AND BB.[name] IS NOT NULL
                          THEN 0
                          ELSE 0 - ISNULL(AA.[filelength], 0) - ISNULL(BB.[filelength], 0)
                      END) AS neg
           FROM
           (
               SELECT F.[name], 
                      F.[filelength]
               FROM files F
               WHERE F.dirid = A.[id]
           ) AA
           FULL OUTER JOIN
           (
               SELECT F.[name], 
                      F.[filelength]
               FROM files F
               WHERE F.dirid = B.[id]
           ) BB ON AA.[name] = BB.[name]
                   AND AA.[filelength] = BB.[filelength]
       ) AS diffposneg
       WHERE A.numfiles > 0
             AND B.numfiles > 0;
SELECT TOP 100 A.*, 
               D1.*, 
               D2.*
FROM [dbo].[comparefolders] A(NOLOCK)
     INNER JOIN [dbo].[dirs] D1 ON D1.[id] = A.[id_a]
     INNER JOIN [dbo].[dirs] D2 ON D2.[id] = A.[id_b]
WHERE A.[pos] > 0
ORDER BY A.diff DESC;
GO
USE master;
GO