-- Crea TuningDB con datos deterministas (mismo resultado en cualquier máquina).
-- Orders: 1M filas, clustered por orderdate, PK nonclustered orderid (como PerformanceV3 del libro).
-- Idempotente: si ya está cargada, no hace nada.
IF DB_ID('TuningDB') IS NULL CREATE DATABASE TuningDB;
GO
USE TuningDB;
GO
IF OBJECT_ID('dbo.Orders') IS NOT NULL AND (SELECT COUNT_BIG(*) FROM dbo.Orders) = 1000000
BEGIN
  PRINT 'TuningDB ya cargada.';
  SET NOEXEC ON;
END
GO
DROP TABLE IF EXISTS dbo.Orders, dbo.Customers;

CREATE TABLE dbo.Customers(
  custid INT NOT NULL PRIMARY KEY,
  name   VARCHAR(40) NOT NULL,
  region VARCHAR(10) NOT NULL);

CREATE TABLE dbo.Orders(
  orderid   INT IDENTITY NOT NULL CONSTRAINT PK_Orders PRIMARY KEY NONCLUSTERED,
  custid    INT NOT NULL,
  empid     INT NOT NULL,
  orderdate DATE NOT NULL,
  amount    DECIMAL(10,2) NOT NULL);
CREATE CLUSTERED INDEX CIX_Orders_orderdate ON dbo.Orders(orderdate);

WITH n AS (SELECT TOP (20000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS i
           FROM sys.all_objects a CROSS JOIN sys.all_objects b)
INSERT dbo.Customers(custid, name, region)
SELECT CAST(i AS INT), CONCAT('Cliente ', i),
       CHOOSE(CAST(i % 5 AS INT) + 1, 'Norte', 'Sur', 'Este', 'Oeste', 'Centro')
FROM n;

WITH n AS (SELECT TOP (1000000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS i
           FROM sys.all_objects a CROSS JOIN sys.all_objects b)
INSERT dbo.Orders(custid, empid, orderdate, amount)
SELECT CAST((i * 7919) % 20000 + 1 AS INT),
       CAST((i * 104729) % 500 + 1 AS INT),
       DATEADD(DAY, CAST((i * 31) % 1500 AS INT), '20200101'),
       CAST((i * 7) % 100000 AS DECIMAL(10,2)) / 100
FROM n;

UPDATE STATISTICS dbo.Orders WITH FULLSCAN;
UPDATE STATISTICS dbo.Customers WITH FULLSCAN;
PRINT 'TuningDB cargada.';
GO
SET NOEXEC OFF;
GO
