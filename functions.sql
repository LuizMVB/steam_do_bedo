-- =====================================================================
-- Projeto de Banco de Dados 2026/2 - Stream do Bedo
-- Arquivo 4/6: functions parametrizadas das 12 consultas (item 6)
-- PostgreSQL 17
--
-- O que faz: cria uma function por consulta do enunciado (itens 1 a 12,
-- o 12 é o desafio). Cada filtro opcional é um parâmetro com DEFAULT NULL.
--
-- Ordem de execução: ddl.sql -> seed.sql -> views.sql ->
-- functions.sql -> triggers.sql -> tests.sql.
-- Depende das views V1 a V4 (views.sql).
--
-- As premissas de cada item, a reescrita para desempenho e a
-- interpretação do item 12 estão no decisoes_detalhamento.md.
--
-- Padrão das functions:
--   * LANGUAGE sql STABLE: o planejador expande a function dentro da
--     consulta que a chama (inlining). Com o parâmetro constante, o
--     padrão "p IS NULL OR col = p" vira "col = p" e pode usar índice.
--     Por isso só o item 12 é plpgsql: a posição global obriga a agregar
--     todas as plataformas de qualquer jeito, e ele valida os parâmetros.
--   * As consultas que listam canais devolvem nome E plataforma: o nome
--     só é único por plataforma.
--   * Itens 2, 3 e 8 a 11 leem views materializadas (V3, V4): o resultado
--     reflete o último sp_refresh_views(). Itens 1, 4 a 7 e 12 leem as
--     tabelas base (direto ou pelas views virtuais V1, V2) e são exatos.
--   * Os DROP FUNCTION removem assinaturas antigas: CREATE OR REPLACE não
--     troca o tipo de retorno nem a lista de parâmetros.
-- =====================================================================

\set ON_ERROR_STOP on

SET search_path TO steam_do_bedo;

-- ---------------------------------------------------------------------
-- 1. Streamers com mais vídeos publicados, com o total de vídeos e a soma
--    das visualizações. Filtro opcional: plataforma.
-- Como: conta os vídeos por streamer (dono do canal) e soma visu_total;
--   o nick vem de Usuario depois da agregação (agrupa por id inteiro, não
--   por texto).
-- Cuidado: vídeos em que o streamer só participa (Participa) não contam:
--   "publicados" = postados nos canais dele. Desempate por nick.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS steam_do_bedo.sp_obter_streamers_com_maior_qtd_videos_publicados(BIGINT);
DROP FUNCTION IF EXISTS steam_do_bedo.sp_obter_streamers_com_maior_qtd_videos_publicados(INTEGER);

CREATE FUNCTION steam_do_bedo.sp_obter_streamers_com_maior_qtd_videos_publicados(
    p_plataforma INTEGER DEFAULT NULL)
RETURNS TABLE (nick VARCHAR, qtd_video_publicados BIGINT, soma_visualizacoes BIGINT)
LANGUAGE sql STABLE AS $$
    SELECT u.nick, a.qtd, a.soma
    FROM (
        SELECT c.id_streamer,
               count(*)                              AS qtd,
               coalesce(sum(v.visu_total), 0)::BIGINT AS soma
        FROM steam_do_bedo.canal c
        JOIN steam_do_bedo.video v ON v.id_canal = c.id_canal
        WHERE p_plataforma IS NULL OR c.nro_plataforma = p_plataforma  -- filtro opcional
        GROUP BY c.id_streamer
    ) a
    JOIN steam_do_bedo.usuario u ON u.id_usuario = a.id_streamer
    ORDER BY a.qtd DESC, u.nick;
$$;

-- ---------------------------------------------------------------------
-- 2. Vídeos ordenados pela quantidade de comentários (online, offline e
--    total). Filtro opcional: nome do canal.
-- Como: lê a V3 (contagens prontas por vídeo). Com filtro, o nome acha o
--   canal pelo UNIQUE (nome, nro_plataforma) e os vídeos do canal pelo
--   índice da V3, que começa por id_canal.
-- Reescrita antes dos índices: a versão anterior agregava Comentario
--   inteira e só depois filtrava o canal.
-- Cuidado: contagem do último refresh da V3. Vídeos sem comentário
--   aparecem com zero. Desempate por título.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS steam_do_bedo.sp_obter_videos_mais_comentados(VARCHAR);

CREATE FUNCTION steam_do_bedo.sp_obter_videos_mais_comentados(p_nome_canal VARCHAR DEFAULT NULL)
RETURNS TABLE (
    video_titulo VARCHAR,
    nome_canal VARCHAR,
    nro_plataforma INTEGER,
    qtd_comentarios_online BIGINT,
    qtd_comentarios_offline BIGINT,
    qtd_comentarios_total BIGINT
) LANGUAGE sql STABLE AS $$
    SELECT v.titulo, cn.nome, cn.nro_plataforma,
           m.qtd_online, m.qtd_offline, m.qtd_total
    FROM steam_do_bedo.mv_interacoes_video m                      -- V3
    JOIN steam_do_bedo.canal cn ON cn.id_canal = m.id_canal
    JOIN steam_do_bedo.video v  ON v.id_video = m.id_video
    WHERE p_nome_canal IS NULL OR cn.nome = p_nome_canal
    ORDER BY m.qtd_total DESC, v.titulo;
$$;

-- ---------------------------------------------------------------------
-- 3. Canais pela quantidade total de interações (comentários online +
--    offline de todos os vídeos) e média de interações por vídeo.
--    Filtro opcional: nick do streamer.
-- Como: soma a V3 por canal. Dois ramos excludentes num UNION ALL:
--   * sem filtro (p IS NULL): agrega a V3 inteira por canal numa passada
--     (HashAggregate) e junta com Canal e Usuario por hash;
--   * com filtro (u.nick = p): acha o usuário pelo UNIQUE (nick), os canais
--     dele e soma só as linhas da V3 desses canais (LATERAL pelo índice
--     ux_mv_interacoes_video, que começa por id_canal).
--   Com o parâmetro constante, o planejador elimina o ramo que não serve
--   (a condição vira falsa na hora de planejar), então cada chamada roda
--   só o plano bom para o seu caso.
-- Medido: sem filtro 3,0 s -> 1,5 s a quente com este formato; a versão
--   anterior juntava Canal à V3 por merge join e reagrupava 1,25 mi de
--   linhas.
-- Cuidado: canal sem vídeo aparece com 0 vídeos e média nula. Contagem do
--   último refresh da V3. Os dois ramos precisam devolver as mesmas
--   colunas na mesma ordem.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS steam_do_bedo.sp_obter_canais_por_qtd_total_interacoes(VARCHAR);

CREATE FUNCTION steam_do_bedo.sp_obter_canais_por_qtd_total_interacoes(p_nick_streamer VARCHAR DEFAULT NULL)
RETURNS TABLE (
    nick_streamer VARCHAR,
    nome_canal VARCHAR,
    nro_plataforma INTEGER,
    qtd_interacoes BIGINT,
    qtd_videos BIGINT,
    media_interacoes_por_video NUMERIC
) LANGUAGE sql STABLE AS $$
    SELECT * FROM (
        -- ramo sem filtro: agrega a V3 inteira uma vez
        SELECT u.nick, cn.nome, cn.nro_plataforma,
               coalesce(a.tot, 0)::BIGINT, coalesce(a.n, 0)::BIGINT,
               round(a.tot::NUMERIC / nullif(a.n, 0), 2)
        FROM steam_do_bedo.canal cn
        JOIN steam_do_bedo.usuario u ON u.id_usuario = cn.id_streamer
        LEFT JOIN (SELECT id_canal, sum(qtd_total) AS tot, count(*) AS n
                   FROM steam_do_bedo.mv_interacoes_video                    -- V3
                   GROUP BY id_canal) a ON a.id_canal = cn.id_canal
        WHERE p_nick_streamer IS NULL
        UNION ALL
        -- ramo com filtro: só os canais do streamer
        SELECT u.nick, cn.nome, cn.nro_plataforma,
               coalesce(a.tot, 0)::BIGINT, coalesce(a.n, 0)::BIGINT,
               round(a.tot::NUMERIC / nullif(a.n, 0), 2)
        FROM steam_do_bedo.usuario u
        JOIN steam_do_bedo.canal cn ON cn.id_streamer = u.id_usuario
        CROSS JOIN LATERAL (SELECT sum(m.qtd_total) AS tot, count(*) AS n
                            FROM steam_do_bedo.mv_interacoes_video m         -- V3
                            WHERE m.id_canal = cn.id_canal) a
        WHERE u.nick = p_nick_streamer
    ) x
    ORDER BY 4 DESC, 2;
$$;

-- ---------------------------------------------------------------------
-- 4. Canais pelo valor médio das doações recebidas por comentário, com a
--    quantidade de doações e o total. Filtro opcional: plataforma.
-- Como: soma as doações de cada comentário (um comentário pode ter mais
--   de uma doação) e tira a média por canal. Lê a V1, que já exclui as
--   recusadas e traz a plataforma: o filtro desce para Canal.
-- Valores em USD (gravados assim pelo T11).
-- Cuidado: só canais com doação recebida aparecem. Desempate por nome.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS steam_do_bedo.sp_obter_canais_pela_media_doacoes_por_comentario(INTEGER);

CREATE FUNCTION steam_do_bedo.sp_obter_canais_pela_media_doacoes_por_comentario(
    p_nro_plataforma INTEGER DEFAULT NULL)
RETURNS TABLE (
    nome_canal VARCHAR,
    nro_plataforma INTEGER,
    vr_medio_doacoes_por_comentario NUMERIC,
    qtd_doacoes BIGINT,
    vr_total_doacoes NUMERIC
) LANGUAGE sql STABLE AS $$
    SELECT dc.nome_canal, dc.nro_plataforma,
           round(avg(dc.vr_comentario), 2),
           sum(dc.qtd)::BIGINT,
           sum(dc.vr_comentario)
    FROM (
        SELECT d.id_canal, d.nome_canal, d.nro_plataforma, d.id_video, d.seq_comentario,
               count(*) AS qtd, sum(d.valor_usd) AS vr_comentario
        FROM steam_do_bedo.vw_doacao_recebida d                     -- V1
        WHERE p_nro_plataforma IS NULL OR d.nro_plataforma = p_nro_plataforma
        GROUP BY d.id_canal, d.nome_canal, d.nro_plataforma, d.id_video, d.seq_comentario
    ) dc
    GROUP BY dc.id_canal, dc.nome_canal, dc.nro_plataforma
    ORDER BY 3 DESC, dc.nome_canal;
$$;

-- ---------------------------------------------------------------------
-- 5. Canais patrocinados e valor pago por empresa. Filtro opcional: nome
--    da empresa.
-- Como: uma linha por (canal, empresa); a PK de Patrocinio é
--   (nro_empresa, id_canal), então o filtro por empresa usa o UNIQUE
--   (nome) de Empresa e o prefixo da PK de Patrocinio.
-- Valor em USD (contrato externo).
-- Cuidado: agrupa por id (antes agrupava por nome, o que juntava canais
--   homônimos de plataformas diferentes). Ordena pelo valor.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS steam_do_bedo.sp_obter_canais_patrocinados_com_valores_por_empresa(VARCHAR);

CREATE FUNCTION steam_do_bedo.sp_obter_canais_patrocinados_com_valores_por_empresa(
    p_nome_empresa VARCHAR DEFAULT NULL)
RETURNS TABLE (
    nome_canal VARCHAR,
    nro_plataforma INTEGER,
    nome_empresa VARCHAR,
    vr_total_patrocinio NUMERIC
) LANGUAGE sql STABLE AS $$
    SELECT cn.nome, cn.nro_plataforma, e.nome, p.valor
    FROM steam_do_bedo.patrocinio p
    JOIN steam_do_bedo.empresa e ON e.nro = p.nro_empresa
    JOIN steam_do_bedo.canal cn  ON cn.id_canal = p.id_canal
    WHERE p_nome_empresa IS NULL OR e.nome = p_nome_empresa
    ORDER BY p.valor DESC, cn.nome, e.nome;
$$;

-- ---------------------------------------------------------------------
-- 6. De quantos canais cada usuário é membro e quanto desembolsa por mês,
--    em moeda local e em USD. Filtro opcional: nick do usuário.
-- Como: lê a V2 (inscrições com o valor convertido).
-- Sem data de referência: o modelo não tem data de inscrição, e só os
--   membros vigentes ficam no banco.
-- Cuidado: o filtro por nick acha o usuário pelo UNIQUE (nick); achar as
--   inscrições dele precisa de um índice em Inscricao (id_membro), porque
--   a PK começa por id_canal.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS steam_do_bedo.sp_obter_qtd_canais_e_gasto_mensal_por_usuario(VARCHAR);
DROP FUNCTION IF EXISTS steam_do_bedo.sp_obter_qtd_canais_e_gasto_mensal_por_usuario(VARCHAR, DATE);

CREATE FUNCTION steam_do_bedo.sp_obter_qtd_canais_e_gasto_mensal_por_usuario(
    p_nick_usuario VARCHAR DEFAULT NULL)
RETURNS TABLE (
    nick_usuario VARCHAR,
    qtd_canais BIGINT,
    moeda VARCHAR,
    vr_mensal_moeda_local NUMERIC,
    vr_mensal_usd NUMERIC
) LANGUAGE sql STABLE AS $$
    SELECT i.nick_membro, count(*), i.moeda,
           sum(i.valor_local),
           round(sum(i.valor_usd), 2)
    FROM steam_do_bedo.vw_inscricao_usd i                            -- V2
    WHERE p_nick_usuario IS NULL OR i.nick_membro = p_nick_usuario
    GROUP BY i.id_membro, i.nick_membro, i.moeda
    ORDER BY 5 DESC, i.nick_membro;
$$;

-- ---------------------------------------------------------------------
-- 7. Canais que já receberam doações e a soma recebida. Filtro opcional:
--    nome do canal.
-- Como: lê a V1. Com filtro, o nome desce para Canal (UNIQUE (nome,
--   nro_plataforma)), os vídeos vêm pelo índice que começa por id_canal e
--   as doações pelo prefixo da PK (id_video, ...).
-- Cuidado: o mesmo nome pode existir em mais de uma plataforma: uma linha
--   por canal.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS steam_do_bedo.sp_obter_canais_com_doacoes_recebidas(VARCHAR);

CREATE FUNCTION steam_do_bedo.sp_obter_canais_com_doacoes_recebidas(p_nome_canal VARCHAR DEFAULT NULL)
RETURNS TABLE (
    nome_canal VARCHAR,
    nro_plataforma INTEGER,
    qtd_doacoes BIGINT,
    soma_vr_doacao NUMERIC
) LANGUAGE sql STABLE AS $$
    SELECT d.nome_canal, d.nro_plataforma, count(*), sum(d.valor_usd)
    FROM steam_do_bedo.vw_doacao_recebida d                          -- V1
    WHERE p_nome_canal IS NULL OR d.nome_canal = p_nome_canal
    GROUP BY d.id_canal, d.nome_canal, d.nro_plataforma
    ORDER BY 4 DESC, d.nome_canal;
$$;

-- ---------------------------------------------------------------------
-- 8. Top-k canais que mais recebem patrocínio (USD).
-- Como: top-k sobre a V4. p_k nulo devolve todos (LIMIT NULL).
-- Cuidado: dado do último refresh da V4.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS steam_do_bedo.sp_obter_top_k_canais_por_patrocinio(INT);

CREATE FUNCTION steam_do_bedo.sp_obter_top_k_canais_por_patrocinio(p_k INT)
RETURNS TABLE (
    nome_canal VARCHAR,
    nro_plataforma INTEGER,
    qtd_patrocinadores BIGINT,
    vr_total_patrocinio NUMERIC
) LANGUAGE sql STABLE AS $$
    SELECT c.nome, c.nro_plataforma, f.qtd_patrocinadores, f.vr_patrocinio
    FROM steam_do_bedo.mv_faturamento_canal f                        -- V4
    JOIN steam_do_bedo.canal c ON c.id_canal = f.id_canal
    WHERE f.qtd_patrocinadores > 0
    ORDER BY f.vr_patrocinio DESC, c.nome
    LIMIT p_k;
$$;

-- ---------------------------------------------------------------------
-- 9. Top-k canais que mais recebem aportes de membros (USD por mês).
-- Como: top-k sobre a V4 (que soma a V2 por canal).
-- Sem data de referência: o modelo não tem data de inscrição, e só os
--   membros vigentes ficam no banco.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS steam_do_bedo.sp_obter_top_k_canais_por_aportes_de_membros(INT);
DROP FUNCTION IF EXISTS steam_do_bedo.sp_obter_top_k_canais_por_aportes_de_membros(INT, DATE);

CREATE FUNCTION steam_do_bedo.sp_obter_top_k_canais_por_aportes_de_membros(p_k INT)
RETURNS TABLE (
    nome_canal VARCHAR,
    nro_plataforma INTEGER,
    qtd_membros BIGINT,
    vr_total_aportes NUMERIC
) LANGUAGE sql STABLE AS $$
    SELECT c.nome, c.nro_plataforma, f.qtd_membros, f.vr_membros
    FROM steam_do_bedo.mv_faturamento_canal f                        -- V4
    JOIN steam_do_bedo.canal c ON c.id_canal = f.id_canal
    WHERE f.qtd_membros > 0
    ORDER BY f.vr_membros DESC, c.nome
    LIMIT p_k;
$$;

-- ---------------------------------------------------------------------
-- 10. Top-k canais que mais receberam doações, considerando todos os
--     vídeos (USD).
-- Como: top-k sobre a V4 (que soma a V1 por canal).
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS steam_do_bedo.sp_obter_top_k_canais_por_doacoes_recebidas(INT);

CREATE FUNCTION steam_do_bedo.sp_obter_top_k_canais_por_doacoes_recebidas(p_k INT)
RETURNS TABLE (
    nome_canal VARCHAR,
    nro_plataforma INTEGER,
    qtd_videos_com_doacao BIGINT,
    qtd_doacoes BIGINT,
    vr_total_doacoes NUMERIC
) LANGUAGE sql STABLE AS $$
    SELECT c.nome, c.nro_plataforma, f.qtd_videos_com_doacao, f.qtd_doacoes, f.vr_doacoes
    FROM steam_do_bedo.mv_faturamento_canal f                        -- V4
    JOIN steam_do_bedo.canal c ON c.id_canal = f.id_canal
    WHERE f.qtd_doacoes > 0
    ORDER BY f.vr_doacoes DESC, c.nome
    LIMIT p_k;
$$;

-- ---------------------------------------------------------------------
-- 11. Top-k canais que mais faturam: patrocínio + membros + doações, USD.
-- Como: top-k sobre a V4.
-- As três fontes já estão em USD (a doação é convertida no INSERT).
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS steam_do_bedo.sp_obter_top_k_canais_por_faturamento(INT);
DROP FUNCTION IF EXISTS steam_do_bedo.sp_obter_top_k_canais_por_faturamento(INT, DATE);

CREATE FUNCTION steam_do_bedo.sp_obter_top_k_canais_por_faturamento(p_k INT)
RETURNS TABLE (
    nome_canal VARCHAR,
    nro_plataforma INTEGER,
    vr_patrocinio NUMERIC,
    vr_membros NUMERIC,
    vr_doacoes NUMERIC,
    vr_faturamento_total NUMERIC
) LANGUAGE sql STABLE AS $$
    SELECT c.nome, c.nro_plataforma, f.vr_patrocinio, f.vr_membros, f.vr_doacoes, f.vr_faturamento_total
    FROM steam_do_bedo.mv_faturamento_canal f                        -- V4
    JOIN steam_do_bedo.canal c ON c.id_canal = f.id_canal
    ORDER BY f.vr_faturamento_total DESC, c.nome
    LIMIT p_k;
$$;

-- ---------------------------------------------------------------------
-- 12. DESAFIO: top-k plataformas pela quantidade de streamers E de
--     canais. Filtro opcional: plataforma.
-- Interpretação (decidida antes do código; ver decisoes_detalhamento.md):
--   * streamer da plataforma = streamer DONO de ao menos um canal nela,
--     contado uma vez só (COUNT(DISTINCT id_streamer)). Ter só conta
--     (PlataformaUsuario) não publica nada e não traz público; participar
--     do vídeo de outro (Participa) já está no canal de quem publicou.
--   * o "E" = ordenação lexicográfica: primeiro streamers, depois canais.
--     Responde ao "alcance de público" do minimundo: cada streamer
--     distinto é uma audiência própria; canais a mais do mesmo streamer
--     ampliam pouco. A soma (streamers + canais) contaria o mesmo streamer
--     duas vezes, e "exigir os dois" (dominância) não dá um ranking total.
--   * posição = rank() calculado sobre TODAS as plataformas, antes de
--     qualquer filtro: com filtro, a plataforma mostra a posição real
--     (por exemplo 6º), e não "1º de 1".
--   * empates: plataformas com os mesmos streamers e canais dividem a
--     posição (rank), e o corte em k inclui todas as empatadas na k-ésima
--     posição (equivale a FETCH FIRST k ROWS WITH TIES). Dentro do empate,
--     a ordem de saída é pelo nome, para ser determinística.
-- Parâmetros e bordas:
--   * p_k NULL devolve todas as plataformas; p_k < 1 é erro (22023).
--   * p_nro_plataforma informado: devolve só essa plataforma, com a posição
--     global e no_top_k dizendo se ela entra no corte de k (o filtro não
--     some com a plataforma só porque ela ficou fora do top-k). Plataforma
--     inexistente é erro (22023), para não confundir com "sem canais".
--   * plataforma sem canal aparece com 0 streamers e 0 canais (LEFT JOIN),
--     no fim do ranking.
-- Métricas auxiliares (reforçam a interpretação):
--   * canais_por_streamer: mostra por que o critério principal é o
--     streamer (plataformas com muitos canais por streamer têm menos
--     audiências independentes do que o número de canais sugere);
--   * qtd_visualizacoes: soma do derivado Canal.qtd_visualizacoes dos canais
--     da plataforma, o alcance de público em visualizações;
--   * qtd_users: o derivado Plataforma.qtd_users (T2) = CONTAS na
--     plataforma, de streamers ou não. É outra métrica, só de contexto.
-- Por que plpgsql (exceção ao padrão LANGUAGE sql do arquivo): a posição
--   global obriga a agregar todas as plataformas antes de filtrar, então a
--   expansão inline não traria ganho; e plpgsql permite rejeitar parâmetros
--   inválidos com mensagem clara. O custo é ler Canal inteira (~36 mil
--   linhas, 5 MB), medido no benchmark.md.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS steam_do_bedo.sp_obter_top_k_plataformas_por_streamers_e_canais(INT, INTEGER);

CREATE FUNCTION steam_do_bedo.sp_obter_top_k_plataformas_por_streamers_e_canais(
    p_k INT DEFAULT NULL,
    p_nro_plataforma INTEGER DEFAULT NULL)
RETURNS TABLE (
    posicao BIGINT,
    nro_plataforma INTEGER,
    nome_plataforma VARCHAR,
    qtd_streamers BIGINT,
    qtd_canais BIGINT,
    canais_por_streamer NUMERIC,
    qtd_visualizacoes BIGINT,
    qtd_users BIGINT,
    no_top_k BOOLEAN
) LANGUAGE plpgsql STABLE AS $$
BEGIN
    IF p_k IS NOT NULL AND p_k < 1 THEN
        RAISE EXCEPTION 'item 12: k deve ser maior ou igual a 1 (recebido %); use NULL para todas', p_k
            USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF p_nro_plataforma IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM steam_do_bedo.plataforma p WHERE p.nro = p_nro_plataforma) THEN
        RAISE EXCEPTION 'item 12: a plataforma % não existe', p_nro_plataforma
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    RETURN QUERY
    WITH por_plataforma AS (
        -- uma linha por plataforma, inclusive as sem canal (LEFT JOIN)
        SELECT p.nro, p.nome, p.qtd_users,
               count(DISTINCT c.id_streamer)              AS n_streamers,  -- cada streamer conta 1 vez
               count(c.id_canal)                          AS n_canais,
               coalesce(sum(c.qtd_visualizacoes), 0)::BIGINT AS n_visualizacoes
        FROM steam_do_bedo.plataforma p
        LEFT JOIN steam_do_bedo.canal c ON c.nro_plataforma = p.nro
        GROUP BY p.nro, p.nome, p.qtd_users
    ),
    ranking AS (
        -- posição global, ANTES do filtro: o filtro não muda a posição
        SELECT pp.*, rank() OVER (ORDER BY pp.n_streamers DESC, pp.n_canais DESC) AS pos
        FROM por_plataforma pp
    )
    SELECT r.pos, r.nro, r.nome, r.n_streamers, r.n_canais,
           round(r.n_canais::NUMERIC / nullif(r.n_streamers, 0), 2),
           r.n_visualizacoes,
           r.qtd_users,
           (p_k IS NULL OR r.pos <= p_k)
    FROM ranking r
    WHERE (p_nro_plataforma IS NOT NULL AND r.nro = p_nro_plataforma)     -- com filtro: só ela
       OR (p_nro_plataforma IS NULL AND (p_k IS NULL OR r.pos <= p_k))    -- sem filtro: top-k com empates
    ORDER BY r.pos, r.nome;
END;
$$;


-- #####################################################################
-- PARTE 2: índices de apoio (item mandatório 4)
-- #####################################################################

-- =====================================================================
-- Projeto de Banco de Dados 2026/2 - Stream do Bedo
-- Arquivo 4/6, parte 2: índices de apoio (item mandatório 4) - PostgreSQL 17
--
-- O que faz: cria os índices secundários escolhidos pelo grupo, além dos
-- criados automaticamente por PRIMARY KEY e UNIQUE.
--
-- Ordem de execução: ddl.sql -> seed.sql -> views.sql ->
-- functions.sql -> triggers.sql -> tests.sql.
-- Depois da carga: criar o índice sobre a tabela pronta é mais rápido do
-- que mantê-lo linha a linha durante a inserção.
--
-- Teto de 5 índices de apoio (enunciado, item 4). O índice de view
-- materializada CONTA no teto:
--   1. ux_mv_interacoes_video (id_canal, id_video)   views.sql, V3
--   2. ux_mv_faturamento_canal (id_canal)            views.sql, V4
--   3. idx_inscricao_id_membro                       este arquivo
--   4. idx_canal_id_streamer                         este arquivo
--   5. idx_video_id_canal_cobertura                  este arquivo
-- Medido e descartado: Canal (nro_plataforma), de uma versão anterior
-- (sem ganho a frio). Hash foi medido no lugar dos B-tree de igualdade
-- (Inscricao.id_membro, Canal.id_streamer) e não trouxe vantagem.
--
-- Metodologia (professor, 07:03-08:16): inventário dos predicados
-- das functions -> distribuição de cada coluna em
-- pg_stats -> tipo do índice pelo tipo do predicado -> medida a frio com
-- e sem o índice e do overhead de inserção. Os números estão no
-- benchmark.md e no decisoes_detalhamento.md; o EXPLAIN ANALYZE de cada
-- medida está em bench/planos/.
-- =====================================================================

\set ON_ERROR_STOP on

SET search_path TO steam_do_bedo;

DROP INDEX IF EXISTS steam_do_bedo.idx_inscricao_id_membro;
DROP INDEX IF EXISTS steam_do_bedo.idx_canal_id_streamer;
DROP INDEX IF EXISTS steam_do_bedo.idx_canal_nro_plataforma;
DROP INDEX IF EXISTS steam_do_bedo.idx_video_id_canal_cobertura;

-- ---------------------------------------------------------------------
-- 3. idx_inscricao_id_membro
-- O quê: B-tree em Inscricao (id_membro).
-- Por quê: item 6 com filtro por usuário (nick -> id_usuario -> as
--   inscrições dele). A PK de Inscricao é (id_canal, id_membro): com
--   id_canal na frente, não serve para achar as inscrições de um membro,
--   e o plano varre a tabela inteira. Predicado de igualdade muito
--   seletivo (poucas inscrições por usuário). Também atende a FK
--   inscricao_id_membro_fkey quando um Usuario é removido.
-- Substitui idx_inscricao_nick_membro, de uma versão anterior: a chave
--   do membro agora é id_usuario.
-- Medido (a frio, mediana de 5): item 6 com filtro 155 -> 4,5 ms; páginas
--   lidas 4.135 -> 123 (do disco: 4.040 -> 54). Overhead de INSERT em
--   lote: +63% (300 mil linhas, ordem aleatória); 10 MB na tabela inteira.
-- Hash x B-tree: o predicado é só de igualdade, então o hash foi medido.
--   Leu as mesmas páginas, no mesmo tempo, e ficou maior (10,1 MB contra
--   8,4 MB no lote de 300 mil). Neste lote inseriu mais rápido (+27%
--   contra +63%), mas em Canal foi mais lento, e as rodadas variam muito.
--   Fica o B-tree, que lê o mesmo, ocupa menos e também entrega em ordem.
-- Planos: bench/planos/base/i06_com__final__sem_apoio__frio.txt e
--   bench/planos/final/i06_com__final__final__frio.txt (benchmark.md).
-- Cuidado: inscrição é escrita rara (o usuário assina um canal de vez em
--   quando) e a busca por usuário é leitura frequente.
-- ---------------------------------------------------------------------
CREATE INDEX idx_inscricao_id_membro
    ON steam_do_bedo.inscricao (id_membro);

-- ---------------------------------------------------------------------
-- 4. idx_canal_id_streamer
-- O quê: B-tree em Canal (id_streamer).
-- Por quê: item 3 com filtro por streamer (nick -> canais dele). Também
--   atende as verificações dos triggers T9 e T10 do lado de StreamerPais e
--   PlataformaUsuario ("este usuário tem canal?") e a FK
--   canal_id_streamer_fkey. Igualdade, poucos canais por streamer.
-- Medido: item 3 com filtro, páginas lidas 1.689 -> 1.027; a quente 11 ->
--   1,8 ms (a frio a diferença some no ruído, ~220 ms nos dois). 736 kB.
--   Overhead de INSERT: +18% numa tabela de escrita rara.
-- Hash x B-tree: mesmas páginas lidas, mesmo tempo, hash maior: B-tree.
-- ---------------------------------------------------------------------
CREATE INDEX idx_canal_id_streamer
    ON steam_do_bedo.canal (id_streamer);

-- ---------------------------------------------------------------------
-- 5. idx_video_id_canal_cobertura
-- O quê: B-tree em Video (id_canal) com visu_total no INCLUDE (índice de
--   cobertura).
-- Por quê: o item 1 conta os vídeos e soma visu_total por canal. Com
--   filtro de plataforma, mesmo poucos canais faziam o plano varrer Video
--   inteira (155 MB): video_canal_titulo_datah_key começa por id_canal, mas
--   não tem visu_total, e os vídeos de um canal estão espalhados pela
--   tabela (correlação física de id_canal = 0,001, porque a ordem física é
--   a do UUID, e não a do canal). Com o INCLUDE, a contagem e a soma saem
--   só do índice (Index Only Scan), sem visitar a tabela.
-- Medido: item 1 com plataforma pequena (Kick, 3,5% dos canais): 749 ->
--   444 ms a frio e 261 -> 21 ms a quente; páginas 25.526 -> 9.530.
--   38 MB; overhead de INSERT em Video +7%.
-- Cuidado:
--   * Sem filtro ou com plataforma grande (YouTube, 28% dos canais) o
--     planejador continua varrendo a tabela: o predicado é concentrado
--     demais (o exemplo do professor, 07:44). O ganho é das plataformas
--     pequenas, que são a maioria das 28.
--   * Index-only scan depende do visibility map: precisa de VACUUM em dia
--     numa tabela com inserção contínua.
--   * Substitui Canal (nro_plataforma), de uma versão anterior, que foi medido de novo e
--     não teve ganho: Canal tem 665 páginas e é lida em milissegundos; o
--     custo dos itens 1, 4 e 12 estava em Video.
-- ---------------------------------------------------------------------
CREATE INDEX idx_video_id_canal_cobertura
    ON steam_do_bedo.video (id_canal) INCLUDE (visu_total);

ANALYZE steam_do_bedo.inscricao;
ANALYZE steam_do_bedo.canal;
VACUUM (ANALYZE) steam_do_bedo.video;   -- visibility map em dia para o index-only scan
