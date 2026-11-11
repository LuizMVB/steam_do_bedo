-- =====================================================================
-- Projeto de Banco de Dados 2026/2 - Stream do Bedo
-- Functions parametrizadas das consultas (PostgreSQL 17)
--
-- Ordem de execução: ddl.sql -> seed.sql -> procedures.sql -> queries.sql
--
-- Modelo com chaves artificiais: Canal.id_canal (DEC-014) e Video.id_video
-- (DEC-015, DEC-017). As tabelas filhas não repetem mais nome_canal,
-- nro_plataforma, titulo_video e dataH_video; nome e plataforma do canal vêm
-- por JOIN com Canal. nro_plataforma passa a INTEGER (DEC-005).
-- Os DROP FUNCTION removem as assinaturas antigas: CREATE OR REPLACE não
-- troca o tipo de retorno nem a lista de parâmetros.
-- =====================================================================

-- 1. Listar os streamers que possuem a maior quantidade de vídeos publicados, apresentando
-- a quantidade total de vídeos e a soma das visualizações destes vídeos. Dar a opção de
-- filtrar por plataforma como parâmetro opcional na forma de uma stored procedure.

-- O tipo de retorno mudou (nova coluna), e CREATE OR REPLACE não permite isso.
DROP FUNCTION IF EXISTS steam_do_bedo.sp_obter_streamers_com_maior_qtd_videos_publicados(BIGINT);
DROP FUNCTION IF EXISTS steam_do_bedo.sp_obter_streamers_com_maior_qtd_videos_publicados(INTEGER);

-- DEC-005: p_plataforma passa a INTEGER
CREATE OR REPLACE FUNCTION steam_do_bedo.sp_obter_streamers_com_maior_qtd_videos_publicados(p_plataforma INTEGER DEFAULT NULL)
RETURNS TABLE (nick VARCHAR, qtd_video_publicados BIGINT, soma_visualizacoes BIGINT)
LANGUAGE sql STABLE as $$
    SELECT c.nick_streamer,
           COUNT(*) as qtd_video_publicados,
           COALESCE(SUM(v.visu_total), 0)::BIGINT as soma_visualizacoes
    FROM steam_do_bedo.video v
    JOIN steam_do_bedo.canal c ON c.id_canal = v.id_canal   -- DEC-015
    WHERE p_plataforma IS NULL OR c.nro_plataforma = p_plataforma   -- parâmetro opcional
    GROUP BY c.nick_streamer
    ORDER BY qtd_video_publicados DESC;
$$;

-- 2. Listar e ordenar os vídeos que possuem a maior quantidade de comentários, apresentando
-- a quantidade de comentários online, offline e total. Dar a opção de filtrar por canal como
-- parâmetro opcional na forma de uma stored procedure.

CREATE OR REPLACE FUNCTION steam_do_bedo.sp_obter_videos_mais_comentados(p_nome_canal VARCHAR DEFAULT NULL)
RETURNS TABLE (
    video_titulo VARCHAR,
    nome_canal VARCHAR,
    qtd_comentarios_online BIGINT,
    qtd_comentarios_offline BIGINT,
    qtd_comentarios_total BIGINT
) LANGUAGE sql STABLE AS $$
    -- DEC-015/DEC-017: o nome do canal vem de Canal e os comentários são
    -- ligados ao vídeo por id_video
    SELECT
        v.titulo,
        cn.nome,
        COALESCE(SUM(c.qtd_online), 0) AS qtd_comentarios_online,
        COALESCE(SUM(c.qtd_offline), 0) AS qtd_comentarios_offline,
        COALESCE(SUM(c.qtd_online + c.qtd_offline), 0) AS qtd_comentarios_total
    FROM steam_do_bedo.video v
    JOIN steam_do_bedo.canal cn ON cn.id_canal = v.id_canal
    LEFT JOIN (
        SELECT
            id_video,
            COUNT(*) AS qtd_online,
            0 AS qtd_offline
        FROM steam_do_bedo.comentario
        WHERE coment_on = TRUE
        GROUP BY id_video

        UNION ALL

        SELECT
            id_video,
            0 AS qtd_online,
            COUNT(*) AS qtd_offline
        FROM steam_do_bedo.comentario
        WHERE coment_on = FALSE
        GROUP BY id_video
    ) AS c ON v.id_video = c.id_video
    WHERE p_nome_canal IS NULL OR cn.nome = p_nome_canal
    GROUP BY
        cn.nome,
        cn.nro_plataforma,
        v.titulo,
        v.datah
    ORDER BY qtd_comentarios_total DESC;
$$;

-- 3. Listar e ordenar os canais pela quantidade total de interações, considerando os
-- comentários online e offline de todos os seus vídeos. Apresentar também a média de
-- interações por vídeo. Dar a opção de filtrar por streamer como parâmetro opcional na
-- forma de uma stored procedure.

DROP FUNCTION IF EXISTS steam_do_bedo.sp_obter_canais_por_qtd_total_interacoes(VARCHAR);

CREATE OR REPLACE FUNCTION steam_do_bedo.sp_obter_canais_por_qtd_total_interacoes(p_nick_streamer VARCHAR DEFAULT NULL)
RETURNS TABLE (
    nick_streamer VARCHAR,
    nome_canal VARCHAR,
    nro_plataforma INTEGER,   -- DEC-005
    qtd_interacoes NUMERIC,
    qtd_videos BIGINT,
    media_interacoes_por_video NUMERIC
) LANGUAGE sql STABLE AS $$
    SELECT
        cn.nick_streamer,
        cn.nome,
        cn.nro_plataforma,
        COALESCE(SUM(cm.qtd_comentarios), 0) AS qtd_interacoes,
        COUNT(v.titulo) AS qtd_videos,
        ROUND(COALESCE(SUM(cm.qtd_comentarios), 0) / NULLIF(COUNT(v.titulo), 0), 2) AS media_interacoes_por_video
    FROM steam_do_bedo.canal cn
    LEFT JOIN steam_do_bedo.video v ON
        v.id_canal = cn.id_canal                -- DEC-015
    LEFT JOIN (
        SELECT id_video, COUNT(*) AS qtd_comentarios
        FROM steam_do_bedo.comentario
        GROUP BY id_video
    ) cm
        ON cm.id_video = v.id_video             -- DEC-017
    WHERE p_nick_streamer IS NULL OR cn.nick_streamer = p_nick_streamer
    GROUP BY cn.nick_streamer, cn.nome, cn.nro_plataforma
    ORDER BY qtd_interacoes DESC, cn.nome;
$$;

-- 4. Listar e ordenar os canais pelo valor médio das doações recebidas por comentário.
-- Apresentar também a quantidade de doações e o valor total recebido. Dar a opção de
-- filtrar por plataforma como parâmetro opcional na forma de uma stored procedure.

DROP FUNCTION IF EXISTS steam_do_bedo.sp_obter_canais_pela_media_doacoes_por_comentario(BIGINT);
DROP FUNCTION IF EXISTS steam_do_bedo.sp_obter_canais_pela_media_doacoes_por_comentario(INTEGER);

-- DEC-005: p_nro_plataforma e nro_plataforma passam a INTEGER
CREATE OR REPLACE FUNCTION steam_do_bedo.sp_obter_canais_pela_media_doacoes_por_comentario(p_nro_plataforma INTEGER DEFAULT NULL)
RETURNS TABLE (
    nome_canal VARCHAR,
    nro_plataforma INTEGER,
    vr_medio_doacoes_por_comentario NUMERIC,
    qtd_doacoes BIGINT,
    vr_total_doacoes NUMERIC
) LANGUAGE sql STABLE AS $$
    SELECT
        dc.nome_canal,
        dc.nro_plataforma,
        ROUND(AVG(dc.vr_comentario), 2) AS vr_medio_doacoes_por_comentario,
        SUM(dc.qtd_doacoes)::BIGINT AS qtd_doacoes,
        SUM(dc.vr_comentario) AS vr_total_doacoes
    FROM (
        -- DEC-017: o comentário é (id_video, seq_comentario); canal via Video e Canal
        SELECT cn.nome AS nome_canal, cn.nro_plataforma, d.id_video, d.seq_comentario,
               COUNT(*) AS qtd_doacoes,
               SUM(d.valor) AS vr_comentario
        FROM steam_do_bedo.doacao d
        JOIN steam_do_bedo.video v ON v.id_video = d.id_video
        JOIN steam_do_bedo.canal cn ON cn.id_canal = v.id_canal
        WHERE d.status <> 'recusado'
          AND (p_nro_plataforma IS NULL OR cn.nro_plataforma = p_nro_plataforma)
        GROUP BY cn.nome, cn.nro_plataforma, d.id_video, d.seq_comentario
    ) dc
    GROUP BY dc.nome_canal, dc.nro_plataforma
    ORDER BY vr_medio_doacoes_por_comentario DESC, dc.nome_canal;
$$;

-- 5. Identificar quais são os canais patrocinados e os valores de patrocínio pagos por empresa.
-- Dar a opção de filtrar os resultados por empresa como um parâmetro opcional na forma
-- de uma stored procedure.

CREATE OR REPLACE FUNCTION steam_do_bedo.sp_obter_canais_patrocinados_com_valores_por_empresa(p_nome_empresa VARCHAR DEFAULT NULL)
RETURNS TABLE (
    nome_canal VARCHAR,
    nome_empresa VARCHAR,
    vr_total_patrocinio NUMERIC
) LANGUAGE sql STABLE AS $$
    SELECT
        cn.nome,
        e.nome,
        SUM(p.valor) as vr_total_patrocinio
    FROM steam_do_bedo.canal cn
    JOIN steam_do_bedo.patrocinio p ON cn.id_canal = p.id_canal   -- DEC-014
    JOIN steam_do_bedo.empresa e ON p.nro_empresa = e.nro
    WHERE p_nome_empresa IS NULL OR e.nome = p_nome_empresa
    GROUP BY cn.nome, e.nome
$$;

-- 6. Descobrir de quantos canais cada usuário é membro e a soma do valor desembolsado por
-- usuário por mês. Dar a opção de filtrar os resultados por usuário como um parâmetro
-- opcional na forma de uma stored procedure.

DROP FUNCTION IF EXISTS steam_do_bedo.sp_obter_qtd_canais_e_gasto_mensal_por_usuario(VARCHAR);
DROP FUNCTION IF EXISTS steam_do_bedo.sp_obter_qtd_canais_e_gasto_mensal_por_usuario(VARCHAR, DATE);

-- DEC-007: p_data_ref considera só as inscrições feitas até a data de referência
CREATE OR REPLACE FUNCTION steam_do_bedo.sp_obter_qtd_canais_e_gasto_mensal_por_usuario(
    p_nick_usuario VARCHAR DEFAULT NULL,
    p_data_ref DATE DEFAULT CURRENT_DATE)
RETURNS TABLE (
    nick_usuario VARCHAR,
    qtd_canais BIGINT,
    moeda VARCHAR,
    vr_mensal_moeda_local NUMERIC,
    vr_mensal_usd NUMERIC
) LANGUAGE sql STABLE AS $$
    -- O valor do nível é pago na moeda do país de residência do usuário e
    -- convertido para USD por Conversao.fator_conver (moeda -> USD).
    -- Usuário sem país de residência é tratado como USD (fator 1).
    SELECT
        u.nick,
        COUNT(*) AS qtd_canais,
        COALESCE(pa.moeda, 'USD')::VARCHAR AS moeda,
        SUM(n.valor) AS vr_mensal_moeda_local,
        ROUND(SUM(n.valor * COALESCE(cv.fator_conver, 1)), 2) AS vr_mensal_usd
    FROM steam_do_bedo.usuario u
    JOIN steam_do_bedo.inscricao i ON i.nick_membro = u.nick
    JOIN steam_do_bedo.nivelcanal n ON n.id_canal = i.id_canal   -- DEC-014
        AND n.nivel = i.nivel
    LEFT JOIN steam_do_bedo.pais pa ON pa.ddi = u.pais_residencia
    LEFT JOIN steam_do_bedo.conversao cv ON cv.moeda = pa.moeda
    WHERE (p_nick_usuario IS NULL OR u.nick = p_nick_usuario)
      AND i.data_inscricao <= p_data_ref                          -- DEC-007
    GROUP BY u.nick, pa.moeda
    ORDER BY vr_mensal_usd DESC, u.nick;
$$;

-- 7. Listar e ordenar os canais que já receberam doações e a soma dos valores recebidos em
-- doação. Dar a opção de filtrar os resultados por canal como um parâmetro opcional na
-- forma de uma stored procedure.

DROP FUNCTION IF EXISTS steam_do_bedo.sp_obter_canais_com_doacoes_recebidas(VARCHAR);

CREATE OR REPLACE FUNCTION steam_do_bedo.sp_obter_canais_com_doacoes_recebidas(p_nome_canal VARCHAR DEFAULT NULL)
RETURNS TABLE (
    nome_canal VARCHAR,
    nro_plataforma INTEGER,   -- DEC-005
    qtd_doacoes BIGINT,
    soma_vr_doacao NUMERIC
) LANGUAGE sql STABLE AS $$
    SELECT
        cn.nome,
        cn.nro_plataforma,
        COUNT(*) AS qtd_doacoes,
        SUM(d.valor) AS soma_vr_doacao
    FROM steam_do_bedo.canal cn
    JOIN steam_do_bedo.video v ON v.id_canal = cn.id_canal    -- DEC-015
    JOIN steam_do_bedo.doacao d ON d.id_video = v.id_video    -- DEC-017
    WHERE d.status <> 'recusado'
      AND (p_nome_canal IS NULL OR cn.nome = p_nome_canal)
    GROUP BY cn.nome, cn.nro_plataforma
    ORDER BY soma_vr_doacao DESC, cn.nome;
$$;

-- 8. Listar e ordenar os k canais que mais recebem patrocínio e os valores recebidos.

DROP FUNCTION IF EXISTS steam_do_bedo.sp_obter_top_k_canais_por_patrocinio(INT);

CREATE OR REPLACE FUNCTION steam_do_bedo.sp_obter_top_k_canais_por_patrocinio(p_k INT)
RETURNS TABLE (
    nome_canal VARCHAR,
    nro_plataforma INTEGER,   -- DEC-005
    vr_total_patrocinio NUMERIC
) LANGUAGE sql STABLE AS $$
    SELECT c.nome, c.nro_plataforma, SUM(p.valor) AS vr_total_patrocinio
    FROM steam_do_bedo.patrocinio p
    JOIN steam_do_bedo.canal c ON c.id_canal = p.id_canal   -- DEC-014
    GROUP BY c.nome, c.nro_plataforma
    ORDER BY vr_total_patrocinio DESC, c.nome
    LIMIT p_k;
$$;

-- 9. Listar e ordenar os k canais que mais recebem aportes de membros e os valores recebidos.

DROP FUNCTION IF EXISTS steam_do_bedo.sp_obter_top_k_canais_por_aportes_de_membros(INT);
DROP FUNCTION IF EXISTS steam_do_bedo.sp_obter_top_k_canais_por_aportes_de_membros(INT, DATE);

-- DEC-007: p_data_ref considera só as inscrições feitas até a data de referência
CREATE OR REPLACE FUNCTION steam_do_bedo.sp_obter_top_k_canais_por_aportes_de_membros(
    p_k INT,
    p_data_ref DATE DEFAULT CURRENT_DATE)
RETURNS TABLE (
    nome_canal VARCHAR,
    nro_plataforma INTEGER,   -- DEC-005
    qtd_membros BIGINT,
    vr_total_aportes NUMERIC
) LANGUAGE sql STABLE AS $$
    SELECT
        c.nome,
        c.nro_plataforma,
        COUNT(*) AS qtd_membros,
        ROUND(SUM(n.valor * COALESCE(cv.fator_conver, 1)), 2) AS vr_total_aportes
    FROM steam_do_bedo.inscricao i
    JOIN steam_do_bedo.canal c ON c.id_canal = i.id_canal          -- DEC-014
    JOIN steam_do_bedo.nivelcanal n ON n.id_canal = i.id_canal     -- DEC-014
        AND n.nivel = i.nivel
    JOIN steam_do_bedo.usuario u ON u.nick = i.nick_membro
    LEFT JOIN steam_do_bedo.pais pa ON pa.ddi = u.pais_residencia
    LEFT JOIN steam_do_bedo.conversao cv ON cv.moeda = pa.moeda
    WHERE i.data_inscricao <= p_data_ref                           -- DEC-007
    GROUP BY c.nome, c.nro_plataforma
    ORDER BY vr_total_aportes DESC, c.nome
    LIMIT p_k;
$$;

-- 10. Listar e ordenar os k canais que mais receberam doações considerando todos os vídeos.

DROP FUNCTION IF EXISTS steam_do_bedo.sp_obter_top_k_canais_por_doacoes_recebidas(INT);

CREATE OR REPLACE FUNCTION steam_do_bedo.sp_obter_top_k_canais_por_doacoes_recebidas(p_k INT)
RETURNS TABLE (
    nome_canal VARCHAR,
    nro_plataforma INTEGER,   -- DEC-005
    qtd_videos_com_doacao BIGINT,
    qtd_doacoes BIGINT,
    vr_total_doacoes NUMERIC
) LANGUAGE sql STABLE AS $$
    -- Doacao carrega a chave do vídeo, então basta agrupar por canal para somar
    -- as doações de todos os vídeos. Doações recusadas não foram recebidas e
    -- ficam de fora (mesmo critério dos itens 4 e 7).
    -- DEC-017: a chave do vídeo agora é id_video; o canal vem por Video e Canal.
    SELECT
        c.nome,
        c.nro_plataforma,
        COUNT(DISTINCT d.id_video) AS qtd_videos_com_doacao,
        COUNT(*) AS qtd_doacoes,
        SUM(d.valor) AS vr_total_doacoes
    FROM steam_do_bedo.doacao d
    JOIN steam_do_bedo.video v ON v.id_video = d.id_video
    JOIN steam_do_bedo.canal c ON c.id_canal = v.id_canal
    WHERE d.status <> 'recusado'
    GROUP BY c.nome, c.nro_plataforma
    ORDER BY vr_total_doacoes DESC, c.nome
    LIMIT p_k;
$$;

-- 11. Listar os k canais que mais faturam considerando as três fontes de receita: patrocínio,
-- membros inscritos e doações.

DROP FUNCTION IF EXISTS steam_do_bedo.sp_obter_top_k_canais_por_faturamento(INT);
DROP FUNCTION IF EXISTS steam_do_bedo.sp_obter_top_k_canais_por_faturamento(INT, DATE);

-- DEC-007: p_data_ref vale para a parte de membros
CREATE OR REPLACE FUNCTION steam_do_bedo.sp_obter_top_k_canais_por_faturamento(
    p_k INT,
    p_data_ref DATE DEFAULT CURRENT_DATE)
RETURNS TABLE (
    nome_canal VARCHAR,
    nro_plataforma INTEGER,   -- DEC-005
    vr_patrocinio NUMERIC,
    vr_membros NUMERIC,
    vr_doacoes NUMERIC,
    vr_faturamento_total NUMERIC
) LANGUAGE sql STABLE AS $$
    -- Cada fonte é agregada por canal em uma CTE própria e só depois combinada
    -- (UNION ALL), para que os joins de uma fonte não multipliquem as linhas da outra.
    -- DEC-014/DEC-017: cada fonte devolve id_canal; nome e plataforma vêm de Canal no final.
    WITH receitas AS (
        -- Patrocínio: já em USD
        SELECT p.id_canal,
               p.valor AS vr_patrocinio, 0::NUMERIC AS vr_membros, 0::NUMERIC AS vr_doacoes
        FROM steam_do_bedo.patrocinio p

        UNION ALL

        -- Membros: valor do nível convertido para USD (mesma premissa dos itens 6 e 9)
        SELECT i.id_canal,
               0::NUMERIC, n.valor * COALESCE(cv.fator_conver, 1), 0::NUMERIC
        FROM steam_do_bedo.inscricao i
        JOIN steam_do_bedo.nivelcanal n ON n.id_canal = i.id_canal
            AND n.nivel = i.nivel
        JOIN steam_do_bedo.usuario u ON u.nick = i.nick_membro
        LEFT JOIN steam_do_bedo.pais pa ON pa.ddi = u.pais_residencia
        LEFT JOIN steam_do_bedo.conversao cv ON cv.moeda = pa.moeda
        WHERE i.data_inscricao <= p_data_ref                       -- DEC-007

        UNION ALL

        -- Doações recebidas (exclui recusadas), somadas como estão (sem conversão)
        SELECT v.id_canal,
               0::NUMERIC, 0::NUMERIC, d.valor
        FROM steam_do_bedo.doacao d
        JOIN steam_do_bedo.video v ON v.id_video = d.id_video
        WHERE d.status <> 'recusado'
    )
    SELECT
        c.nome,
        c.nro_plataforma,
        ROUND(SUM(r.vr_patrocinio), 2) AS vr_patrocinio,
        ROUND(SUM(r.vr_membros), 2) AS vr_membros,
        ROUND(SUM(r.vr_doacoes), 2) AS vr_doacoes,
        ROUND(SUM(r.vr_patrocinio + r.vr_membros + r.vr_doacoes), 2) AS vr_faturamento_total
    FROM receitas r
    JOIN steam_do_bedo.canal c ON c.id_canal = r.id_canal
    GROUP BY c.nome, c.nro_plataforma
    ORDER BY vr_faturamento_total DESC, c.nome
    LIMIT p_k;
$$;

-- 12. DESAFIO/PONTO-EXTRA: Listar as top-k plataformas pela quantidade de streamers
-- E canais. Dar a opção de filtrar por plataforma como parâmetro opcional na forma de
-- uma stored procedure.