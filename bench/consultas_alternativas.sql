-- =====================================================================
-- Projeto de Banco de Dados 2026/2 - Stream do Bedo
-- bench/consultas_alternativas.sql: versões alternativas das consultas,
-- usadas SÓ na aferição (P13 e P17). Não fazem parte da entrega.
--
-- O que faz: cria o schema "bench" com functions que respondem às mesmas
-- perguntas das functions de procedures.sql, mas de outro jeito, para
-- comparar no mesmo banco:
--   *_original  a forma da versão anterior do procedures.sql, só adaptada
--               às chaves novas (linha de base da reescrita, DEC-033);
--   *_direta    a forma reescrita sobre as tabelas base (sem view);
--   *_virtual   a mesma lógica escrita sobre as views virtuais V1 e V2.
-- As versões finais (procedures.sql) leem as materializadas V3 e V4.
--
-- Ordem: depois de views.sql e procedures.sql, no banco de aferição.
-- DEC-033 (reescrita) e DEC-028 (views).
-- Cuidado: o schema bench é apagado e recriado a cada execução.
-- =====================================================================

\set ON_ERROR_STOP on

DROP SCHEMA IF EXISTS bench CASCADE;
CREATE SCHEMA bench;

-- ---------------------------------------------------------------------
-- Item 2 · original: conta Comentario INTEIRA duas vezes (UNION ALL de
-- online e offline, cada uma com GROUP BY) e só depois junta com o vídeo
-- e filtra o canal. Com filtro, ainda lê os 5 mi de comentários.
-- ---------------------------------------------------------------------
CREATE FUNCTION bench.item2_original(p_nome_canal VARCHAR DEFAULT NULL)
RETURNS TABLE (video_titulo VARCHAR, nome_canal VARCHAR, qtd_on BIGINT, qtd_off BIGINT, qtd_total BIGINT)
LANGUAGE sql STABLE AS $$
    SELECT v.titulo, cn.nome,
           coalesce(sum(c.qtd_online), 0)::BIGINT,
           coalesce(sum(c.qtd_offline), 0)::BIGINT,
           coalesce(sum(c.qtd_online + c.qtd_offline), 0)::BIGINT
    FROM steam_do_bedo.video v
    JOIN steam_do_bedo.canal cn ON cn.id_canal = v.id_canal
    LEFT JOIN (
        SELECT id_video, count(*) AS qtd_online, 0 AS qtd_offline
        FROM steam_do_bedo.comentario WHERE coment_on = TRUE GROUP BY id_video
        UNION ALL
        SELECT id_video, 0, count(*)
        FROM steam_do_bedo.comentario WHERE coment_on = FALSE GROUP BY id_video
    ) c ON c.id_video = v.id_video
    WHERE p_nome_canal IS NULL OR cn.nome = p_nome_canal
    GROUP BY cn.nome, cn.nro_plataforma, v.titulo, v.dataH
    ORDER BY 5 DESC;
$$;

-- ---------------------------------------------------------------------
-- Item 2 · direta reescrita: filtra o canal ANTES de agregar e conta
-- online/offline numa passada só (FILTER). Com filtro, os comentários
-- são lidos só dos vídeos do canal, pela PK (id_video, seq).
-- ---------------------------------------------------------------------
CREATE FUNCTION bench.item2_direta(p_nome_canal VARCHAR DEFAULT NULL)
RETURNS TABLE (video_titulo VARCHAR, nome_canal VARCHAR, nro_plataforma INTEGER,
               qtd_on BIGINT, qtd_off BIGINT, qtd_total BIGINT)
LANGUAGE sql STABLE AS $$
    SELECT v.titulo, cn.nome, cn.nro_plataforma,
           count(c.seq) FILTER (WHERE c.coment_on),
           count(c.seq) FILTER (WHERE NOT c.coment_on),
           count(c.seq)
    FROM steam_do_bedo.canal cn
    JOIN steam_do_bedo.video v ON v.id_canal = cn.id_canal
    LEFT JOIN steam_do_bedo.comentario c ON c.id_video = v.id_video
    WHERE p_nome_canal IS NULL OR cn.nome = p_nome_canal
    GROUP BY v.id_video, cn.nome, cn.nro_plataforma, v.titulo
    ORDER BY 6 DESC, v.titulo;
$$;

-- ---------------------------------------------------------------------
-- Item 3 · original: conta Comentario inteira por vídeo e só depois junta
-- com canal e vídeo e filtra o streamer.
-- ---------------------------------------------------------------------
CREATE FUNCTION bench.item3_original(p_nick_streamer VARCHAR DEFAULT NULL)
RETURNS TABLE (nick_streamer VARCHAR, nome_canal VARCHAR, nro_plataforma INTEGER,
               qtd_interacoes NUMERIC, qtd_videos BIGINT, media NUMERIC)
LANGUAGE sql STABLE AS $$
    SELECT u.nick, cn.nome, cn.nro_plataforma,
           coalesce(sum(cm.qtd), 0),
           count(v.id_video),
           round(coalesce(sum(cm.qtd), 0) / nullif(count(v.id_video), 0), 2)
    FROM steam_do_bedo.canal cn
    JOIN steam_do_bedo.usuario u ON u.id_usuario = cn.id_streamer
    LEFT JOIN steam_do_bedo.video v ON v.id_canal = cn.id_canal
    LEFT JOIN (SELECT id_video, count(*) AS qtd FROM steam_do_bedo.comentario GROUP BY id_video) cm
           ON cm.id_video = v.id_video
    WHERE p_nick_streamer IS NULL OR u.nick = p_nick_streamer
    GROUP BY u.nick, cn.nome, cn.nro_plataforma
    ORDER BY 4 DESC, cn.nome;
$$;

-- ---------------------------------------------------------------------
-- Item 3 · direta reescrita: filtra o streamer antes, conta por vídeo
-- (subconsulta agrupada depois do JOIN) e só então soma por canal.
-- ---------------------------------------------------------------------
CREATE FUNCTION bench.item3_direta(p_nick_streamer VARCHAR DEFAULT NULL)
RETURNS TABLE (nick_streamer VARCHAR, nome_canal VARCHAR, nro_plataforma INTEGER,
               qtd_interacoes BIGINT, qtd_videos BIGINT, media NUMERIC)
LANGUAGE sql STABLE AS $$
    SELECT x.nick, x.nome, x.nro_plataforma,
           coalesce(sum(x.n), 0)::BIGINT,
           count(x.id_video),
           round(sum(x.n)::NUMERIC / nullif(count(x.id_video), 0), 2)
    FROM (
        SELECT u.nick, cn.id_canal, cn.nome, cn.nro_plataforma, v.id_video, count(c.seq) AS n
        FROM steam_do_bedo.canal cn
        JOIN steam_do_bedo.usuario u ON u.id_usuario = cn.id_streamer
        LEFT JOIN steam_do_bedo.video v ON v.id_canal = cn.id_canal
        LEFT JOIN steam_do_bedo.comentario c ON c.id_video = v.id_video
        WHERE p_nick_streamer IS NULL OR u.nick = p_nick_streamer
        GROUP BY u.nick, cn.id_canal, cn.nome, cn.nro_plataforma, v.id_video
    ) x
    GROUP BY x.id_canal, x.nick, x.nome, x.nro_plataforma
    ORDER BY 4 DESC, x.nome;
$$;

-- ---------------------------------------------------------------------
-- Item 10 · direta: agrega Doacao (sem recusadas) por canal nas tabelas
-- base, sem view.
-- ---------------------------------------------------------------------
CREATE FUNCTION bench.item10_direta(p_k INT)
RETURNS TABLE (nome_canal VARCHAR, nro_plataforma INTEGER, qtd_videos BIGINT, qtd_doacoes BIGINT, vr NUMERIC)
LANGUAGE sql STABLE AS $$
    SELECT c.nome, c.nro_plataforma, count(DISTINCT d.id_video), count(*), sum(d.valor)
    FROM steam_do_bedo.doacao d
    JOIN steam_do_bedo.video v ON v.id_video = d.id_video
    JOIN steam_do_bedo.canal c ON c.id_canal = v.id_canal
    WHERE d.status <> 'recusado'
    GROUP BY c.id_canal, c.nome, c.nro_plataforma
    ORDER BY 5 DESC, c.nome
    LIMIT p_k;
$$;

-- Item 10 · virtual: a mesma consulta sobre a V1.
CREATE FUNCTION bench.item10_virtual(p_k INT)
RETURNS TABLE (nome_canal VARCHAR, nro_plataforma INTEGER, qtd_videos BIGINT, qtd_doacoes BIGINT, vr NUMERIC)
LANGUAGE sql STABLE AS $$
    SELECT d.nome_canal, d.nro_plataforma, count(DISTINCT d.id_video), count(*), sum(d.valor_usd)
    FROM steam_do_bedo.vw_doacao_recebida d
    GROUP BY d.id_canal, d.nome_canal, d.nro_plataforma
    ORDER BY 5 DESC, d.nome_canal
    LIMIT p_k;
$$;

-- ---------------------------------------------------------------------
-- Item 11 · direta: as três fontes por UNION ALL sobre as tabelas base
-- (forma da versão anterior, já com a doação em USD).
-- ---------------------------------------------------------------------
CREATE FUNCTION bench.item11_direta(p_k INT)
RETURNS TABLE (nome_canal VARCHAR, nro_plataforma INTEGER, vr_pat NUMERIC, vr_mem NUMERIC, vr_doa NUMERIC, vr_total NUMERIC)
LANGUAGE sql STABLE AS $$
    WITH receitas AS (
        SELECT p.id_canal, p.valor AS vp, 0::NUMERIC AS vm, 0::NUMERIC AS vd
        FROM steam_do_bedo.patrocinio p
        UNION ALL
        SELECT i.id_canal, 0, n.valor * cv.fator_conver, 0
        FROM steam_do_bedo.inscricao i
        JOIN steam_do_bedo.nivelcanal n ON n.id_canal = i.id_canal AND n.nivel = i.nivel
        JOIN steam_do_bedo.usuario u ON u.id_usuario = i.id_membro
        JOIN steam_do_bedo.pais pa ON pa.ddi = u.pais_residencia
        JOIN steam_do_bedo.conversao cv ON cv.moeda = pa.moeda
        UNION ALL
        SELECT v.id_canal, 0, 0, d.valor
        FROM steam_do_bedo.doacao d
        JOIN steam_do_bedo.video v ON v.id_video = d.id_video
        WHERE d.status <> 'recusado'
    )
    SELECT c.nome, c.nro_plataforma,
           round(sum(r.vp), 2), round(sum(r.vm), 2), round(sum(r.vd), 2),
           round(sum(r.vp + r.vm + r.vd), 2)
    FROM receitas r
    JOIN steam_do_bedo.canal c ON c.id_canal = r.id_canal
    GROUP BY c.id_canal, c.nome, c.nro_plataforma
    ORDER BY 6 DESC, c.nome
    LIMIT p_k;
$$;

-- Item 11 · virtual: a mesma lógica sobre V1 e V2.
CREATE FUNCTION bench.item11_virtual(p_k INT)
RETURNS TABLE (nome_canal VARCHAR, nro_plataforma INTEGER, vr_pat NUMERIC, vr_mem NUMERIC, vr_doa NUMERIC, vr_total NUMERIC)
LANGUAGE sql STABLE AS $$
    WITH receitas AS (
        SELECT p.id_canal, p.valor AS vp, 0::NUMERIC AS vm, 0::NUMERIC AS vd FROM steam_do_bedo.patrocinio p
        UNION ALL
        SELECT i.id_canal, 0, i.valor_usd, 0 FROM steam_do_bedo.vw_inscricao_usd i
        UNION ALL
        SELECT d.id_canal, 0, 0, d.valor_usd FROM steam_do_bedo.vw_doacao_recebida d
    )
    SELECT c.nome, c.nro_plataforma,
           round(sum(r.vp), 2), round(sum(r.vm), 2), round(sum(r.vd), 2),
           round(sum(r.vp + r.vm + r.vd), 2)
    FROM receitas r
    JOIN steam_do_bedo.canal c ON c.id_canal = r.id_canal
    GROUP BY c.id_canal, c.nome, c.nro_plataforma
    ORDER BY 6 DESC, c.nome
    LIMIT p_k;
$$;

-- =====================================================================
-- Item 12 (DEC-035): alternativas para comparar com a versão final
-- (steam_do_bedo.sp_obter_top_k_plataformas_por_streamers_e_canais).
-- =====================================================================

-- Versão anterior (DEC-029): agregação direta, sem posição global; com
-- filtro, a plataforma vira "1ª de 1" e o corte em k não trata empates.
CREATE FUNCTION bench.item12_anterior(p_k INT, p_plataforma INTEGER DEFAULT NULL)
RETURNS TABLE (nro INTEGER, nome VARCHAR, qtd_streamers BIGINT, qtd_canais BIGINT)
LANGUAGE sql STABLE AS $$
    SELECT p.nro, p.nome, count(DISTINCT c.id_streamer), count(c.id_canal)
    FROM steam_do_bedo.plataforma p
    LEFT JOIN steam_do_bedo.canal c ON c.nro_plataforma = p.nro
    WHERE p_plataforma IS NULL OR p.nro = p_plataforma
    GROUP BY p.nro, p.nome
    ORDER BY 3 DESC, 4 DESC, p.nome
    LIMIT p_k;
$$;

-- V5 candidata, virtual: o agregado por plataforma como view.
CREATE VIEW bench.vw5_plataforma AS
SELECT p.nro, p.nome, p.qtd_users,
       count(DISTINCT c.id_streamer) AS n_streamers,
       count(c.id_canal)             AS n_canais,
       coalesce(sum(c.qtd_visualizacoes), 0)::BIGINT AS n_visualizacoes
FROM steam_do_bedo.plataforma p
LEFT JOIN steam_do_bedo.canal c ON c.nro_plataforma = p.nro
GROUP BY p.nro, p.nome, p.qtd_users;

-- V5 candidata, materializada: 28 linhas; sem índice (não gastaria o teto),
-- refresh comum.
CREATE MATERIALIZED VIEW bench.mv5_plataforma AS SELECT * FROM bench.vw5_plataforma;
ANALYZE bench.mv5_plataforma;

-- Mesma lógica da versão final, lendo a V5 (virtual ou materializada).
CREATE FUNCTION bench.item12_v5(p_mat BOOLEAN, p_k INT DEFAULT NULL, p_nro_plataforma INTEGER DEFAULT NULL)
RETURNS TABLE (posicao BIGINT, nro INTEGER, nome VARCHAR, qtd_streamers BIGINT, qtd_canais BIGINT, no_top_k BOOLEAN)
LANGUAGE plpgsql STABLE AS $$
BEGIN
    IF p_mat THEN
        RETURN QUERY
        SELECT r.pos, r.nro, r.nome, r.n_streamers, r.n_canais, (p_k IS NULL OR r.pos <= p_k)
        FROM (SELECT v.*, rank() OVER (ORDER BY v.n_streamers DESC, v.n_canais DESC) AS pos FROM bench.mv5_plataforma v) r
        WHERE (p_nro_plataforma IS NOT NULL AND r.nro = p_nro_plataforma)
           OR (p_nro_plataforma IS NULL AND (p_k IS NULL OR r.pos <= p_k))
        ORDER BY r.pos, r.nome;
    ELSE
        RETURN QUERY
        SELECT r.pos, r.nro, r.nome, r.n_streamers, r.n_canais, (p_k IS NULL OR r.pos <= p_k)
        FROM (SELECT v.*, rank() OVER (ORDER BY v.n_streamers DESC, v.n_canais DESC) AS pos FROM bench.vw5_plataforma v) r
        WHERE (p_nro_plataforma IS NOT NULL AND r.nro = p_nro_plataforma)
           OR (p_nro_plataforma IS NULL AND (p_k IS NULL OR r.pos <= p_k))
        ORDER BY r.pos, r.nome;
    END IF;
END;
$$;
