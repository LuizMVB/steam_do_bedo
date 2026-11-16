-- =====================================================================
-- estatisticas.sql · distribuição das colunas dos predicados
--
-- O que faz: para cada coluna que aparece num WHERE, JOIN ou GROUP BY das
-- functions, mostra o que o planejador sabe (pg_stats: n_distinct, valor
-- mais comum e sua frequência, correlação física) e a fração da tabela que
-- o filtro usado na aferição devolve. É a base do inventário em
-- predicados.md e da escolha dos índices.
--
-- Ordem: depois da carga e do VACUUM ANALYZE (o seed.sql já faz).
-- Metodologia do professor (07:03-08:00): se o filtro devolve uma fração
-- grande da tabela, o índice não ajuda; olhar a distribuição antes.
-- =====================================================================

\set ON_ERROR_STOP on
SET search_path TO steam_do_bedo;
\pset footer off

-- 1. O que o planejador sabe de cada coluna de predicado
SELECT tablename AS tabela, attname AS coluna, n_distinct,
       (most_common_vals::text::text[])[1]  AS valor_mais_comum,
       round(most_common_freqs[1]::numeric, 4) AS freq_mais_comum,
       round(correlation::numeric, 3)          AS correlacao
FROM pg_stats
WHERE schemaname = 'steam_do_bedo'
  AND (tablename, attname) IN (
      ('canal', 'nro_plataforma'), ('canal', 'id_streamer'), ('canal', 'nome'),
      ('inscricao', 'id_membro'), ('inscricao', 'id_canal'),
      ('usuario', 'nick'), ('empresa', 'nome'), ('patrocinio', 'nro_empresa'),
      ('video', 'id_canal'), ('comentario', 'id_video'), ('comentario', 'coment_on'),
      ('doacao', 'status'), ('doacao', 'id_video'))
ORDER BY 1, 2;

-- 2. Seletividade real dos filtros da aferição
WITH f AS (
    SELECT (SELECT nro FROM plataforma WHERE nome = 'Kick')    AS peq,
           (SELECT nro FROM plataforma WHERE nome = 'YouTube') AS grd
)
SELECT 'Canal.nro_plataforma = Kick' AS predicado,
       round(100.0 * count(*) FILTER (WHERE nro_plataforma = f.peq) / count(*), 2) AS pct_linhas
FROM canal, f GROUP BY f.peq
UNION ALL
SELECT 'Canal.nro_plataforma = YouTube',
       round(100.0 * count(*) FILTER (WHERE nro_plataforma = f.grd) / count(*), 2)
FROM canal, f GROUP BY f.grd
UNION ALL
SELECT 'Doacao.status <> recusado', round(100.0 * avg((status <> 'recusado')::int), 2) FROM doacao
UNION ALL
SELECT 'Comentario.coment_on = true', round(100.0 * avg(coment_on::int), 2) FROM comentario
UNION ALL
SELECT 'Inscricao.id_membro = (membro com mais inscrições)',
       round(100.0 * max(n) / sum(n), 5) FROM (SELECT count(*) AS n FROM inscricao GROUP BY id_membro) x
UNION ALL
SELECT 'Canal.id_streamer = (streamer com mais canais)',
       round(100.0 * max(n) / sum(n), 5) FROM (SELECT count(*) AS n FROM canal GROUP BY id_streamer) x;

-- 3. Concentração: canais por plataforma (o "todos americanos" do professor)
SELECT p.nome AS plataforma, count(c.*) AS canais,
       round(100.0 * count(c.*) / sum(count(c.*)) OVER (), 1) AS pct
FROM plataforma p LEFT JOIN canal c ON c.nro_plataforma = p.nro
GROUP BY p.nome ORDER BY 2 DESC;
