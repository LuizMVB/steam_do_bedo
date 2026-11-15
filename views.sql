-- =====================================================================
-- Projeto de Banco de Dados 2026/2 - Stream do Bedo
-- Arquivo 3/7: views virtuais e materializadas (item mandatório 3)
-- PostgreSQL 17
--
-- O que faz: cria 2 views virtuais (V1, V2), 2 materializadas (V3, V4),
-- os índices UNIQUE das materializadas e a procedure de refresh.
--
-- Ordem de execução (DEC-030): ddl.sql -> seed_v3.sql -> views.sql ->
-- procedures.sql -> triggers.sql -> indices.sql -> queries.sql.
-- Vem depois da carga porque as views materializadas são preenchidas na
-- criação; e antes das procedures, que as usam.
--
-- DEC-028 (views), DEC-026 (moeda), DEC-001 (membros em USD).
--
-- Virtual x materializada:
--   * View virtual (CREATE VIEW) é só uma consulta salva. Cada uso a
--     executa de novo, e o planejador a expande dentro da consulta que a
--     usa (os filtros de fora descem até as tabelas). Serve para
--     centralizar uma regra (filtro de status, conversão de moeda) num
--     lugar só. Não acelera nada por si.
--   * View materializada grava o resultado como tabela. A leitura é
--     imediata, mas o dado fica parado até o REFRESH. Serve para agregações
--     caras sobre tabelas grandes, quando um atraso é aceitável.
--
-- Teto de índices (P09, DEC-028): o grupo decidiu que o índice de view
-- materializada CONTA no teto de 5 índices de apoio do item 4. Os dois
-- índices UNIQUE abaixo (exigidos pelo REFRESH ... CONCURRENTLY) somam 2
-- dos 5; sobram 3 para as tabelas base (indices.sql, DEC-034).
-- =====================================================================

\set ON_ERROR_STOP on

SET search_path TO steam_do_bedo;

DROP MATERIALIZED VIEW IF EXISTS steam_do_bedo.mv_faturamento_canal;
DROP MATERIALIZED VIEW IF EXISTS steam_do_bedo.mv_interacoes_video;
DROP VIEW IF EXISTS steam_do_bedo.vw_inscricao_usd;
DROP VIEW IF EXISTS steam_do_bedo.vw_doacao_recebida;

-- ---------------------------------------------------------------------
-- V1 · vw_doacao_recebida (virtual)
-- O quê: doações que o canal recebeu (status diferente de 'recusado'),
--   com o canal e a plataforma de cada uma. O valor já está em USD.
-- Por quê: a regra "doação recusada não conta" e o caminho doação ->
--   vídeo -> canal se repetiam nos itens 4, 7, 10 e 11 (e na V4). Fica
--   num lugar só (DEC-003).
-- DEC-028; DEC-026 (valor gravado em USD pelo T11, sem conversão aqui)
-- Cuidado: virtual de propósito. Os filtros das functions (canal por nome,
--   plataforma) descem para dentro da view e usam os índices das tabelas
--   base; uma materializada perderia isso e ficaria desatualizada a cada
--   doação.
-- ---------------------------------------------------------------------
CREATE VIEW steam_do_bedo.vw_doacao_recebida AS
SELECT d.id_video,
       d.seq_comentario,
       d.seq_pg,
       v.id_canal,
       cn.nome          AS nome_canal,
       cn.nro_plataforma,
       d.valor          AS valor_usd,      -- DEC-026: gravado em USD
       d.status
FROM steam_do_bedo.doacao d
JOIN steam_do_bedo.video v  ON v.id_video = d.id_video
JOIN steam_do_bedo.canal cn ON cn.id_canal = v.id_canal
WHERE d.status <> 'recusado';           -- DEC-003: recusada não foi recebida

COMMENT ON VIEW steam_do_bedo.vw_doacao_recebida IS
    'V1: doações não recusadas, em USD, com canal e plataforma. DEC-028';

-- ---------------------------------------------------------------------
-- V2 · vw_inscricao_usd (virtual)
-- O quê: cada inscrição vigente com o valor mensal do nível na moeda do
--   país de residência do membro e convertido para USD.
-- Por quê: a conversão dos membros (DEC-001) se repetia nos itens 6, 9 e
--   11 e na V4. Fica num lugar só.
-- DEC-028; DEC-001; DEC-025 (país de residência obrigatório: o fator
--   sempre existe, sem o COALESCE(..., 1) da versão anterior)
-- Cuidado: valor_usd não é arredondado aqui; as functions arredondam o
--   total, para não acumular erro de arredondamento por membro.
-- ---------------------------------------------------------------------
CREATE VIEW steam_do_bedo.vw_inscricao_usd AS
SELECT i.id_canal,
       i.id_membro,
       u.nick           AS nick_membro,
       i.nivel,
       n.valor          AS valor_local,
       p.moeda,
       cv.fator_conver,
       n.valor * cv.fator_conver AS valor_usd
FROM steam_do_bedo.inscricao i
JOIN steam_do_bedo.nivelcanal n ON n.id_canal = i.id_canal AND n.nivel = i.nivel
JOIN steam_do_bedo.usuario u    ON u.id_usuario = i.id_membro
JOIN steam_do_bedo.pais p       ON p.ddi = u.pais_residencia
JOIN steam_do_bedo.conversao cv ON cv.moeda = p.moeda;

COMMENT ON VIEW steam_do_bedo.vw_inscricao_usd IS
    'V2: inscrições com o valor do nível em moeda local e em USD. DEC-028';

-- ---------------------------------------------------------------------
-- V3 · mv_interacoes_video (materializada)
-- O quê: por vídeo, quantos comentários online, offline e no total.
--   Inclui vídeos sem comentário (zeros), que contam na média do item 3.
-- Por quê: Comentario é a maior tabela (5 mi de linhas no seed) e
--   contá-la inteira domina o tempo dos itens 2 e 3 (DEC-018, DEC-033).
--   A contagem de comentários é uma métrica de ranking; um atraso de
--   algumas horas não muda a decisão de quem usa o sistema.
-- DEC-028
-- Índice: UNIQUE (id_canal, id_video). É obrigatório para o REFRESH ...
--   CONCURRENTLY (que não bloqueia leituras) e, por ter id_canal na
--   frente, também atende "vídeos de um canal" (item 2 com filtro) e
--   "soma por canal" (item 3 com filtro). Conta no teto de 5 (P09).
-- Refresh: periódico (por exemplo, de hora em hora por um agendador
--   externo, como cron ou pg_cron) com CALL sp_refresh_views(). Não é
--   disparado por trigger: refazer a contagem a cada comentário custaria
--   mais do que a própria consulta.
-- ---------------------------------------------------------------------
CREATE MATERIALIZED VIEW steam_do_bedo.mv_interacoes_video AS
SELECT v.id_canal,
       v.id_video,
       count(c.seq) FILTER (WHERE c.coment_on)     AS qtd_online,
       count(c.seq) FILTER (WHERE NOT c.coment_on) AS qtd_offline,
       count(c.seq)                                AS qtd_total
FROM steam_do_bedo.video v
LEFT JOIN steam_do_bedo.comentario c ON c.id_video = v.id_video
GROUP BY v.id_canal, v.id_video;

CREATE UNIQUE INDEX ux_mv_interacoes_video
    ON steam_do_bedo.mv_interacoes_video (id_canal, id_video);   -- DEC-028 (conta no teto)

COMMENT ON MATERIALIZED VIEW steam_do_bedo.mv_interacoes_video IS
    'V3: comentários online, offline e total por vídeo (itens 2 e 3). Refresh periódico. DEC-028';

-- ---------------------------------------------------------------------
-- V4 · mv_faturamento_canal (materializada)
-- O quê: por canal com alguma receita, o total em USD de cada fonte
--   (patrocínio, membros, doações), as quantidades e o faturamento total.
-- Por quê: os itens 8 a 11 são top-k ordenados por um valor agregado, o
--   que nenhum índice sobre as tabelas base atende: sem a view, cada
--   chamada agrega Patrocinio, Inscricao (com conversão) e Doacao
--   inteiras. O sistema existe para escolher que canal patrocinar
--   (professor, 14:50); para isso, um atraso de horas é aceitável.
-- DEC-028; usa V1 e V2, então herda as regras de status e de moeda.
-- Índice: UNIQUE (id_canal), exigido pelo REFRESH CONCURRENTLY. Conta no
--   teto de 5 (P09). O top-k em si ordena ~30 mil linhas (uma por canal
--   com receita), o que custa milissegundos sem índice próprio.
-- Refresh: periódico, junto com a V3 (sp_refresh_views).
-- Cuidado: cada fonte é agregada por canal antes de ser combinada; um JOIN
--   direto entre as três tabelas multiplicaria as linhas (DEC-004).
-- ---------------------------------------------------------------------
CREATE MATERIALIZED VIEW steam_do_bedo.mv_faturamento_canal AS
WITH pat AS (
    SELECT id_canal, sum(valor) AS vr, count(*) AS qtd
    FROM steam_do_bedo.patrocinio
    GROUP BY id_canal
),
mem AS (
    SELECT id_canal, sum(valor_usd) AS vr, count(*) AS qtd
    FROM steam_do_bedo.vw_inscricao_usd
    GROUP BY id_canal
),
doa AS (
    SELECT id_canal, sum(valor_usd) AS vr, count(*) AS qtd, count(DISTINCT id_video) AS qtd_videos
    FROM steam_do_bedo.vw_doacao_recebida
    GROUP BY id_canal
)
SELECT c.id_canal,
       round(coalesce(pat.vr, 0), 2)  AS vr_patrocinio,
       coalesce(pat.qtd, 0)           AS qtd_patrocinadores,
       round(coalesce(mem.vr, 0), 2)  AS vr_membros,
       coalesce(mem.qtd, 0)           AS qtd_membros,
       round(coalesce(doa.vr, 0), 2)  AS vr_doacoes,
       coalesce(doa.qtd, 0)           AS qtd_doacoes,
       coalesce(doa.qtd_videos, 0)    AS qtd_videos_com_doacao,
       round(coalesce(pat.vr, 0) + coalesce(mem.vr, 0) + coalesce(doa.vr, 0), 2) AS vr_faturamento_total
FROM steam_do_bedo.canal c
LEFT JOIN pat ON pat.id_canal = c.id_canal
LEFT JOIN mem ON mem.id_canal = c.id_canal
LEFT JOIN doa ON doa.id_canal = c.id_canal
WHERE pat.id_canal IS NOT NULL OR mem.id_canal IS NOT NULL OR doa.id_canal IS NOT NULL;

CREATE UNIQUE INDEX ux_mv_faturamento_canal
    ON steam_do_bedo.mv_faturamento_canal (id_canal);            -- DEC-028 (conta no teto)

COMMENT ON MATERIALIZED VIEW steam_do_bedo.mv_faturamento_canal IS
    'V4: faturamento por canal em USD (itens 8 a 11). Refresh periódico. DEC-028';

-- ---------------------------------------------------------------------
-- sp_refresh_views(): atualiza as duas materializadas.
-- O quê: REFRESH MATERIALIZED VIEW CONCURRENTLY na V3 e na V4.
-- Por quê: estratégia de refresh periódico da DEC-028. CONCURRENTLY
--   recalcula num lado e aplica só a diferença, sem bloquear quem está
--   lendo a view (por isso o índice UNIQUE).
-- Cuidado: CONCURRENTLY é mais lento que o refresh comum (compara as
--   duas versões) e não funciona numa view nunca preenchida. O custo foi
--   medido no bench (DEC-034, overhead de escrita).
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE steam_do_bedo.sp_refresh_views()
LANGUAGE plpgsql AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY steam_do_bedo.mv_interacoes_video;
    REFRESH MATERIALIZED VIEW CONCURRENTLY steam_do_bedo.mv_faturamento_canal;
END;
$$;

ANALYZE steam_do_bedo.mv_interacoes_video;
ANALYZE steam_do_bedo.mv_faturamento_canal;
