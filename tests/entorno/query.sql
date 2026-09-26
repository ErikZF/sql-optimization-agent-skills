-- Consulta lenta a propósito. Tiene varias oportunidades: predicado no sargable (YEAR),
-- sin índice por custid, JOIN antes de filtrar por región.
-- ORDER BY desempata por custid: orden determinista para que el checksum sea estable.
SELECT c.custid, c.name, COUNT(*) AS pedidos, SUM(o.amount) AS total
FROM dbo.Orders o
JOIN dbo.Customers c ON c.custid = o.custid
WHERE YEAR(o.orderdate) = 2022
  AND c.region = 'Norte'
GROUP BY c.custid, c.name
ORDER BY total DESC, c.custid;
