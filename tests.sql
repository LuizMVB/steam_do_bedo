-- =====================================================================
-- Projeto de Banco de Dados 2026/2 - Stream do Bedo
-- Arquivo 6/6: chamadas das functions (consultas 1 a 12) - PostgreSQL 17
--
-- O que faz: chama cada function sem filtro e com o parâmetro opcional,
-- com valores reais da carga do seed.sql (escala 1), mais algumas
-- consultas de exemplo em cima do resultado.
--
-- Ordem de execução (DEC-030): ddl.sql -> seed.sql -> views.sql ->
-- functions.sql -> triggers.sql -> tests.sql.
--
-- Valores dos filtros (o seed é determinístico, então os valores são os
-- mesmos a cada carga na escala 1; em outra escala, troque pelos da
-- consulta de apoio logo abaixo):
--   plataforma pequena: 6 (Kick)   plataforma grande: 1 (YouTube)
--   canal: 'Echo.Queen 136733 TV'   (o canal com mais visualizações)
--   streamer: 'echo.queen_136733'   (dono desse canal)
--   usuário: 'ghost.yt_297686'   (o membro com mais inscrições)
--   empresa: 'Red Bull GmbH'   (a que mais patrocina)
-- As consultas sem filtro que listam todos os vídeos ou canais devolvem
-- muitas linhas; aqui elas vêm com LIMIT para a saída caber na tela (o
-- LIMIT é aplicado em cima da function, que é expandida pelo planejador).
--
-- Itens 2, 3 e 8 a 11 leem views materializadas: refletem o último
-- CALL steam_do_bedo.sp_refresh_views() (DEC-028).
-- DEC-029
-- =====================================================================

\set ON_ERROR_STOP on
SET search_path TO steam_do_bedo;

-- Consulta de apoio: os valores de filtro usados abaixo
SELECT (SELECT nro FROM plataforma WHERE nome = 'Kick')    AS plataforma_pequena,
       (SELECT nro FROM plataforma WHERE nome = 'YouTube') AS plataforma_grande,
       (SELECT nome FROM canal ORDER BY qtd_visualizacoes DESC, id_canal LIMIT 1) AS canal_mais_visto;

-- 1. Streamers com mais vídeos publicados (filtro opcional: plataforma)
SELECT * FROM sp_obter_streamers_com_maior_qtd_videos_publicados() LIMIT 10;
SELECT * FROM sp_obter_streamers_com_maior_qtd_videos_publicados(6) LIMIT 10;   -- Kick
SELECT * FROM sp_obter_streamers_com_maior_qtd_videos_publicados(1) LIMIT 10;   -- YouTube

-- 2. Vídeos mais comentados: online, offline e total (filtro opcional: canal)
SELECT * FROM sp_obter_videos_mais_comentados() LIMIT 10;
SELECT * FROM sp_obter_videos_mais_comentados('Echo.Queen 136733 TV') LIMIT 10;

-- 3. Canais por total de interações e média por vídeo (filtro opcional: streamer)
SELECT * FROM sp_obter_canais_por_qtd_total_interacoes() LIMIT 10;
SELECT * FROM sp_obter_canais_por_qtd_total_interacoes('echo.queen_136733');

-- 4. Canais pelo valor médio de doação por comentário, em USD (filtro opcional: plataforma)
SELECT * FROM sp_obter_canais_pela_media_doacoes_por_comentario() LIMIT 10;
SELECT * FROM sp_obter_canais_pela_media_doacoes_por_comentario(6) LIMIT 10;   -- Kick

-- 5. Canais patrocinados e valor por empresa, em USD (filtro opcional: empresa)
SELECT * FROM sp_obter_canais_patrocinados_com_valores_por_empresa() LIMIT 10;
SELECT * FROM sp_obter_canais_patrocinados_com_valores_por_empresa('Red Bull GmbH') LIMIT 10;

-- 6. De quantos canais cada usuário é membro e quanto gasta por mês (filtro opcional: usuário)
SELECT * FROM sp_obter_qtd_canais_e_gasto_mensal_por_usuario() LIMIT 10;
SELECT * FROM sp_obter_qtd_canais_e_gasto_mensal_por_usuario('ghost.yt_297686');

-- Gasto mensal médio por moeda de residência (USD), as 10 maiores
SELECT moeda, count(*) AS qtd_usuarios, round(avg(vr_mensal_usd), 2) AS vr_medio_usd
FROM sp_obter_qtd_canais_e_gasto_mensal_por_usuario()
GROUP BY moeda ORDER BY qtd_usuarios DESC LIMIT 10;

-- 7. Canais que receberam doações e a soma, em USD (filtro opcional: canal)
SELECT * FROM sp_obter_canais_com_doacoes_recebidas() LIMIT 10;
SELECT * FROM sp_obter_canais_com_doacoes_recebidas('Echo.Queen 136733 TV');

-- 8. Top-k canais por patrocínio (USD)
SELECT * FROM sp_obter_top_k_canais_por_patrocinio(10);

-- 9. Top-k canais por aportes de membros (USD por mês)
SELECT * FROM sp_obter_top_k_canais_por_aportes_de_membros(10);

-- 10. Top-k canais por doações recebidas em todos os vídeos (USD)
SELECT * FROM sp_obter_top_k_canais_por_doacoes_recebidas(10);

-- 11. Top-k canais por faturamento total (patrocínio + membros + doações, USD)
SELECT * FROM sp_obter_top_k_canais_por_faturamento(10);

-- Participação de cada fonte no faturamento dos 10 primeiros
SELECT nome_canal, nro_plataforma, vr_faturamento_total,
       round(100 * vr_patrocinio / vr_faturamento_total, 1) AS pct_patrocinio,
       round(100 * vr_membros    / vr_faturamento_total, 1) AS pct_membros,
       round(100 * vr_doacoes    / vr_faturamento_total, 1) AS pct_doacoes
FROM sp_obter_top_k_canais_por_faturamento(10);

-- 12. DESAFIO: top-k plataformas por streamers E canais (filtro opcional: plataforma)
-- Interpretação e validação: DEC-035. Posição global (rank) calculada antes
-- do filtro; empates no corte de k entram todos; streamer = dono de canal.

-- (a) sem filtro: as 10 primeiras (mais as empatadas na 10ª posição)
SELECT * FROM sp_obter_top_k_plataformas_por_streamers_e_canais(10);

-- (b) filtro por plataforma grande (YouTube): posição global real
SELECT * FROM sp_obter_top_k_plataformas_por_streamers_e_canais(10, (SELECT nro FROM plataforma WHERE nome = 'YouTube'));

-- (c) filtro por plataforma pequena (Kick, dentro do top-10) e por uma fora
--     do top-10 (Rooter): aparece com a posição real e no_top_k = false
SELECT * FROM sp_obter_top_k_plataformas_por_streamers_e_canais(10, (SELECT nro FROM plataforma WHERE nome = 'Kick'));
SELECT * FROM sp_obter_top_k_plataformas_por_streamers_e_canais(10, (SELECT nro FROM plataforma WHERE nome = 'Rooter'));

-- (d) k maior que o número de plataformas: devolve todas (28), sem erro
SELECT count(*) AS plataformas_devolvidas FROM sp_obter_top_k_plataformas_por_streamers_e_canais(100);

-- (e) desempate por canais, empate no corte de k e plataforma sem canal.
--     No seed cada streamer tem no máximo um canal por plataforma (os canais
--     saem das contas), então canais = streamers e o desempate nunca aparece
--     na carga. Este bloco monta o caso e desfaz tudo (ROLLBACK):
--       A: 1 streamer com 2 canais;  B: o mesmo streamer com 1 canal;
--       C e D: nenhum canal (0 e 0, empatadas).
--     Esperado: A antes de B (mesmos streamers, mais canais); C e D na mesma
--     posição; com k igual à posição de C, as duas entram (empate no corte).
BEGIN;
INSERT INTO plataforma (nome, empresa_fund, empresa_resp, data_fund)
SELECT 'Teste ' || x, e.nro, e.nro, DATE '2026-01-01'
FROM unnest(ARRAY['A', 'B', 'C', 'D']) AS x CROSS JOIN (SELECT min(nro) AS nro FROM empresa) e;
-- um streamer qualquer ganha conta em A e B (T10 exige a conta para abrir canal)
INSERT INTO plataformausuario (nro_plataforma, id_usuario, nro_usuario)
SELECT p.nro, s.id_streamer, 1
FROM plataforma p CROSS JOIN (SELECT min(id_streamer) AS id_streamer FROM streamerpais) s
WHERE p.nome IN ('Teste A', 'Teste B');
INSERT INTO canal (nome, nro_plataforma, tipo, id_streamer)
SELECT c.nome, p.nro, 'publico', s.id_streamer
FROM (VALUES ('Teste A', 'Canal principal'), ('Teste A', 'Canal de cortes'), ('Teste B', 'Canal principal')) AS c(plat, nome)
JOIN plataforma p ON p.nome = c.plat
CROSS JOIN (SELECT min(id_streamer) AS id_streamer FROM streamerpais) s;
SELECT posicao, nome_plataforma, qtd_streamers, qtd_canais, canais_por_streamer, no_top_k
FROM sp_obter_top_k_plataformas_por_streamers_e_canais(NULL)
WHERE posicao >= 28;
-- C e D empatam na posição 31: com k = 31 entram as duas (32 linhas, não 31)
SELECT count(*) AS linhas_com_k_31 FROM sp_obter_top_k_plataformas_por_streamers_e_canais(31);
ROLLBACK;

-- (f) parâmetros inválidos: k < 1 e plataforma inexistente dão erro claro
--     (capturado aqui para o arquivo seguir rodando)
DO $$
BEGIN
    BEGIN
        PERFORM * FROM steam_do_bedo.sp_obter_top_k_plataformas_por_streamers_e_canais(0);
    EXCEPTION WHEN invalid_parameter_value THEN
        RAISE NOTICE 'item 12, k = 0: %', SQLERRM;
    END;
    BEGIN
        PERFORM * FROM steam_do_bedo.sp_obter_top_k_plataformas_por_streamers_e_canais(10, -1);
    EXCEPTION WHEN invalid_parameter_value THEN
        RAISE NOTICE 'item 12, plataforma -1: %', SQLERRM;
    END;
END $$;

-- (g) conferência independente: streamers e canais contados plataforma a
--     plataforma por subconsultas correlacionadas, e a posição recalculada
--     como 1 + número de plataformas estritamente à frente (mais streamers,
--     ou mesmos streamers e mais canais). Esperado: 0 divergências.
WITH funcao AS (
    SELECT * FROM sp_obter_top_k_plataformas_por_streamers_e_canais(NULL)
),
manual AS (
    SELECT p.nro,
           (SELECT count(*) FROM (SELECT DISTINCT c.id_streamer FROM canal c WHERE c.nro_plataforma = p.nro) d) AS s,
           (SELECT count(*) FROM canal c WHERE c.nro_plataforma = p.nro) AS n
    FROM plataforma p
),
manual_pos AS (
    SELECT m.*, 1 + (SELECT count(*) FROM manual o WHERE o.s > m.s OR (o.s = m.s AND o.n > m.n)) AS pos
    FROM manual m
)
SELECT count(*) AS plataformas_conferidas,
       count(*) FILTER (WHERE f.qtd_streamers <> m.s OR f.qtd_canais <> m.n OR f.posicao <> m.pos) AS divergencias,
       sum(f.qtd_canais) = (SELECT count(*) FROM canal) AS soma_canais_bate
FROM funcao f JOIN manual_pos m ON m.nro = f.nro_plataforma;


-- #####################################################################
-- PARTE 2: testes dos triggers T1 a T11
-- #####################################################################

-- =====================================================================
-- Projeto de Banco de Dados 2026/2 - Stream do Bedo
-- Arquivo 6/6, parte 2: testes dos triggers T1 a T11
--
-- O que faz: para cada trigger, executa um caso que deve passar e um que
-- deve ser rejeitado, e confere os atributos derivados (qtd_visualizacoes,
-- qtd_users) depois de INSERT, UPDATE e DELETE. Imprime uma tabela com o
-- resultado de cada caso.
--
-- Ordem de execução: depois de triggers.sql (DEC-030), sobre a carga do
-- seed.sql. Os dados de teste são escolhidos por consulta (nenhum id
-- fixo), então o arquivo roda em qualquer escala do seed.
--
-- Não suja a carga: tudo roda numa transação que termina em ROLLBACK.
-- Se algum caso falhar, o último bloco levanta exceção e o psql sai com
-- código diferente de 0 (ON_ERROR_STOP).
--
-- Como cada caso é isolado: cada caso é um bloco DO; um caso "rejeitado"
-- roda o comando dentro de BEGIN ... EXCEPTION, que desfaz só aquele
-- comando (subtransação) e registra o SQLSTATE recebido.
-- Cuidado: concorrência (as travas FOR UPDATE de T3, T4, T5 e T8) não é
-- testada aqui, porque exigiria duas sessões simultâneas.
-- DEC-027
-- =====================================================================

\set ON_ERROR_STOP on
SET search_path TO steam_do_bedo;
\pset footer off

BEGIN;

-- Saída dos comandos de teste descartada; o resultado sai na tabela final.
\o /dev/null

CREATE TEMP TABLE resultado (
    ordem  serial,
    caso   text,
    ok     boolean,
    detalhe text
) ON COMMIT DROP;

-- Registra um caso. Usada por todos os blocos.
CREATE FUNCTION pg_temp.registra(p_caso text, p_ok boolean, p_detalhe text) RETURNS void
LANGUAGE sql AS $$ INSERT INTO resultado (caso, ok, detalhe) VALUES (p_caso, p_ok, p_detalhe) $$;

-- Executa um comando que DEVE ser rejeitado com o SQLSTATE esperado.
CREATE FUNCTION pg_temp.espera_erro(p_caso text, p_sql text, p_sqlstate text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        EXECUTE p_sql;
        PERFORM pg_temp.registra(p_caso, false, 'aceito, mas deveria ser rejeitado');
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp.registra(p_caso, SQLSTATE = p_sqlstate,
                                 'rejeitado [' || SQLSTATE || '] ' || left(SQLERRM, 110));
    END;
END;
$$;

-- ---------------------------------------------------------------------
-- T1 · Canal.qtd_visualizacoes
-- ---------------------------------------------------------------------
DO $$
DECLARE
    c1 bigint; c2 bigint; d1 timestamptz; v uuid; antes1 bigint; antes2 bigint; agora bigint;
BEGIN
    SELECT id_canal, data, qtd_visualizacoes INTO c1, d1, antes1 FROM canal WHERE qtd_visualizacoes > 0 ORDER BY id_canal LIMIT 1;
    SELECT id_canal, qtd_visualizacoes INTO c2, antes2 FROM canal WHERE id_canal <> c1 AND data <= d1 ORDER BY id_canal LIMIT 1;

    -- INSERT de 1 vídeo
    INSERT INTO video (id_canal, titulo, dataH, visu_total) VALUES (c1, 'teste T1', d1 + interval '1 day', 1000)
    RETURNING id_video INTO v;
    SELECT qtd_visualizacoes INTO agora FROM canal WHERE id_canal = c1;
    PERFORM pg_temp.registra('T1 INSERT soma visu_total no canal', agora = antes1 + 1000, antes1 || ' -> ' || agora);

    -- UPDATE de visu_total
    UPDATE video SET visu_total = 1500 WHERE id_video = v;
    SELECT qtd_visualizacoes INTO agora FROM canal WHERE id_canal = c1;
    PERFORM pg_temp.registra('T1 UPDATE aplica o delta', agora = antes1 + 1500, antes1 || ' -> ' || agora);

    -- UPDATE de id_canal: sai de c1 e entra em c2
    UPDATE video SET id_canal = c2 WHERE id_video = v;
    PERFORM pg_temp.registra('T1 troca de canal: antigo volta, novo soma',
        (SELECT qtd_visualizacoes FROM canal WHERE id_canal = c1) = antes1
        AND (SELECT qtd_visualizacoes FROM canal WHERE id_canal = c2) = antes2 + 1500,
        'c1=' || (SELECT qtd_visualizacoes FROM canal WHERE id_canal = c1) || ' c2=' || (SELECT qtd_visualizacoes FROM canal WHERE id_canal = c2));

    -- DELETE
    DELETE FROM video WHERE id_video = v;
    PERFORM pg_temp.registra('T1 DELETE subtrai',
        (SELECT qtd_visualizacoes FROM canal WHERE id_canal = c2) = antes2, 'c2 de volta a ' || antes2);

    -- INSERT em lote (um comando, 200 vídeos): 1 UPDATE no canal
    INSERT INTO video (id_canal, titulo, dataH, visu_total)
    SELECT c1, 'lote T1 #' || g, d1 + g * interval '1 hour', g FROM generate_series(1, 200) g;
    PERFORM pg_temp.registra('T1 INSERT em lote (trigger por comando)',
        (SELECT qtd_visualizacoes FROM canal WHERE id_canal = c1)
          = (SELECT sum(visu_total) FROM video WHERE id_canal = c1),
        'derivado = SUM(visu_total)');
END $$;

-- rejeitado: visu_total negativo (CHECK), e o derivado não muda
SELECT pg_temp.espera_erro('T1 rejeita visu_total negativo (CHECK) sem mexer no derivado',
    'UPDATE steam_do_bedo.video SET visu_total = -1 WHERE id_video = (SELECT id_video FROM steam_do_bedo.video ORDER BY id_video LIMIT 1)',
    '23514');

-- ---------------------------------------------------------------------
-- T2 · Plataforma.qtd_users
-- ---------------------------------------------------------------------
DO $$
DECLARE
    u bigint; p1 integer; p2 integer; a1 bigint; a2 bigint;
BEGIN
    -- usuário sem conta em duas plataformas e sem canal
    SELECT us.id_usuario INTO u FROM usuario us
    WHERE NOT EXISTS (SELECT 1 FROM canal c WHERE c.id_streamer = us.id_usuario)
    ORDER BY us.id_usuario LIMIT 1;
    SELECT nro INTO p1 FROM plataforma p WHERE NOT EXISTS (SELECT 1 FROM plataformausuario pu WHERE pu.id_usuario = u AND pu.nro_plataforma = p.nro) ORDER BY nro LIMIT 1;
    SELECT nro INTO p2 FROM plataforma p WHERE p.nro <> p1 AND NOT EXISTS (SELECT 1 FROM plataformausuario pu WHERE pu.id_usuario = u AND pu.nro_plataforma = p.nro) ORDER BY nro LIMIT 1;
    SELECT qtd_users INTO a1 FROM plataforma WHERE nro = p1;
    SELECT qtd_users INTO a2 FROM plataforma WHERE nro = p2;

    INSERT INTO plataformausuario VALUES (p1, u, 999999999);
    PERFORM pg_temp.registra('T2 INSERT soma 1', (SELECT qtd_users FROM plataforma WHERE nro = p1) = a1 + 1, '');

    UPDATE plataformausuario SET nro_plataforma = p2 WHERE nro_plataforma = p1 AND id_usuario = u;
    PERFORM pg_temp.registra('T2 troca de plataforma: -1 e +1',
        (SELECT qtd_users FROM plataforma WHERE nro = p1) = a1 AND (SELECT qtd_users FROM plataforma WHERE nro = p2) = a2 + 1, '');

    DELETE FROM plataformausuario WHERE nro_plataforma = p2 AND id_usuario = u;
    PERFORM pg_temp.registra('T2 DELETE subtrai 1', (SELECT qtd_users FROM plataforma WHERE nro = p2) = a2, '');

    PERFORM pg_temp.registra('T2 derivado = COUNT(PlataformaUsuario) em todas as plataformas',
        NOT EXISTS (SELECT 1 FROM plataforma p WHERE p.qtd_users <> (SELECT count(*) FROM plataformausuario pu WHERE pu.nro_plataforma = p.nro)),
        '');
END $$;

-- rejeitado: remover a conta de um dono de canal (T10, lado da conta);
-- o derivado não muda porque o DELETE é desfeito
SELECT pg_temp.espera_erro('T2/T10 rejeita remover a conta de dono de canal',
    'DELETE FROM steam_do_bedo.plataformausuario pu USING steam_do_bedo.canal c
      WHERE c.id_streamer = pu.id_usuario AND c.nro_plataforma = pu.nro_plataforma
        AND c.id_canal = (SELECT min(id_canal) FROM steam_do_bedo.canal)',
    '23503');

-- ---------------------------------------------------------------------
-- T3 · Comentario.seq
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v uuid; dv timestamptz; n integer; u bigint; s integer; v0 uuid; s0 integer;
BEGIN
    SELECT id_video, dataH INTO v, dv FROM video WHERE EXISTS (SELECT 1 FROM comentario c WHERE c.id_video = video.id_video) ORDER BY id_video LIMIT 1;
    SELECT max(seq) INTO n FROM comentario WHERE id_video = v;
    SELECT min(id_usuario) INTO u FROM usuario;

    INSERT INTO comentario (id_video, id_usuario, texto, dataH, coment_on) VALUES (v, u, 'teste T3', dv + interval '1 minute', false)
    RETURNING seq INTO s;
    PERFORM pg_temp.registra('T3 seq = max + 1 no vídeo', s = n + 1, 'max ' || n || ' -> ' || s);

    INSERT INTO comentario (id_video, id_usuario, texto, dataH, coment_on)
    SELECT v, u, 'lote T3', dv + interval '2 minutes', false FROM generate_series(1, 3);
    PERFORM pg_temp.registra('T3 INSERT de 3 linhas continua a sequência',
        (SELECT max(seq) FROM comentario WHERE id_video = v) = n + 4
        AND (SELECT count(*) FROM comentario WHERE id_video = v) = n + 4, '');

    SELECT id_video, dataH INTO v0, dv FROM video WHERE NOT EXISTS (SELECT 1 FROM comentario c WHERE c.id_video = video.id_video) ORDER BY id_video LIMIT 1;
    INSERT INTO comentario (id_video, id_usuario, dataH, coment_on) VALUES (v0, u, dv, false) RETURNING seq INTO s0;
    PERFORM pg_temp.registra('T3 primeiro comentário do vídeo recebe seq 1', s0 = 1, '');
END $$;

-- rejeitado: comentário anterior à postagem do vídeo (T7)
SELECT pg_temp.espera_erro('T3/T7 rejeita comentário anterior ao vídeo',
    'INSERT INTO steam_do_bedo.comentario (id_video, id_usuario, dataH, coment_on)
     SELECT id_video, (SELECT min(id_usuario) FROM steam_do_bedo.usuario), dataH - interval ''1 day'', false
     FROM steam_do_bedo.video ORDER BY id_video LIMIT 1',
    '23514');

-- ---------------------------------------------------------------------
-- T4 · Doacao.seq_pg, T11 · conversão para USD, T6 · forma de pagamento
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v uuid; s integer; n integer; pg integer; fator numeric; valor_gravado numeric;
BEGIN
    -- comentário que já tem doação, de um usuário que não mora num país de USD
    -- (assim o teste do T11 mostra a conversão de fato)
    SELECT d.id_video, d.seq_comentario INTO v, s
    FROM doacao d
    JOIN comentario c ON c.id_video = d.id_video AND c.seq = d.seq_comentario
    JOIN usuario u ON u.id_usuario = c.id_usuario
    JOIN pais p ON p.ddi = u.pais_residencia
    WHERE p.moeda <> 'USD'
    ORDER BY d.id_video, d.seq_comentario LIMIT 1;
    SELECT max(seq_pg) INTO n FROM doacao WHERE id_video = v AND seq_comentario = s;
    SELECT cv.fator_conver INTO fator
    FROM comentario c JOIN usuario u ON u.id_usuario = c.id_usuario
    JOIN pais p ON p.ddi = u.pais_residencia JOIN conversao cv ON cv.moeda = p.moeda
    WHERE c.id_video = v AND c.seq = s;

    INSERT INTO doacao (id_video, seq_comentario, valor, status) VALUES (v, s, 1000, 'recebido')
    RETURNING seq_pg, valor INTO pg, valor_gravado;
    INSERT INTO paypal VALUES (v, s, pg, 'PAYID-TESTE-T4');
    PERFORM pg_temp.registra('T4 seq_pg = max + 1 no comentário', pg = n + 1, 'max ' || n || ' -> ' || pg);
    PERFORM pg_temp.registra('T11 grava em USD: 1000 na moeda local × fator',
        valor_gravado = round(1000 * fator, 2), '1000 × ' || fator || ' = ' || valor_gravado);

    -- totalidade conferida agora (sem esperar o COMMIT)
    SET CONSTRAINTS ALL IMMEDIATE;
    SET CONSTRAINTS ALL DEFERRED;
    PERFORM pg_temp.registra('T6 doação com uma forma passa na totalidade', true, '');
END $$;

-- rejeitado (T6 disjunta): a mesma doação em BitCoin, já estando em PayPal
SELECT pg_temp.espera_erro('T6 rejeita a segunda forma de pagamento',
    'INSERT INTO steam_do_bedo.bitcoin
     SELECT id_video, seq_comentario, seq_doacao, ''txid-teste-t6'' FROM steam_do_bedo.paypal ORDER BY 1, 2, 3 LIMIT 1',
    '23505');

-- rejeitado (T6 total): doação sem nenhuma forma, conferida no fim do comando
DO $$
BEGIN
    BEGIN
        SET CONSTRAINTS ALL IMMEDIATE;
        INSERT INTO doacao (id_video, seq_comentario, valor, status)
        SELECT id_video, seq, 10, 'lido' FROM comentario ORDER BY id_video, seq LIMIT 1;
        PERFORM pg_temp.registra('T6 rejeita doação sem forma (totalidade)', false, 'aceita');
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp.registra('T6 rejeita doação sem forma (totalidade)', SQLSTATE = '23503',
                                 '[' || SQLSTATE || '] ' || left(SQLERRM, 110));
    END;
    SET CONSTRAINTS ALL DEFERRED;
END $$;

-- rejeitado (T11): valor que vira menos de US$ 0,01
SELECT pg_temp.espera_erro('T11 rejeita doação abaixo de US$ 0,01',
    'INSERT INTO steam_do_bedo.doacao (id_video, seq_comentario, valor, status)
     SELECT c.id_video, c.seq, 0.01, ''lido''
     FROM steam_do_bedo.comentario c
     JOIN steam_do_bedo.usuario u ON u.id_usuario = c.id_usuario
     JOIN steam_do_bedo.pais p ON p.ddi = u.pais_residencia
     JOIN steam_do_bedo.conversao cv ON cv.moeda = p.moeda
     WHERE cv.fator_conver < 0.5
     ORDER BY c.id_video, c.seq LIMIT 1',
    '23514');

-- ---------------------------------------------------------------------
-- T5 · MecanismoPlat.seq_plataforma
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v uuid; s integer; u bigint; p integer; n integer; pg integer; sp integer;
BEGIN
    -- comentário de um usuário que já doou pelo mecanismo naquela plataforma
    SELECT c.id_video, c.seq, c.id_usuario, ca.nro_plataforma INTO v, s, u, p
    FROM mecanismoplat m
    JOIN comentario c ON c.id_video = m.id_video AND c.seq = m.seq_comentario
    JOIN video vi ON vi.id_video = c.id_video JOIN canal ca ON ca.id_canal = vi.id_canal
    ORDER BY m.id_video, m.seq_comentario LIMIT 1;

    SELECT max(m.seq_plataforma) INTO n
    FROM mecanismoplat m
    JOIN comentario c ON c.id_video = m.id_video AND c.seq = m.seq_comentario
    JOIN video vi ON vi.id_video = c.id_video JOIN canal ca ON ca.id_canal = vi.id_canal
    WHERE c.id_usuario = u AND ca.nro_plataforma = p;

    INSERT INTO doacao (id_video, seq_comentario, valor, status) VALUES (v, s, 50, 'lido') RETURNING seq_pg INTO pg;
    INSERT INTO mecanismoplat (id_video, seq_comentario, seq_doacao) VALUES (v, s, pg) RETURNING seq_plataforma INTO sp;
    PERFORM pg_temp.registra('T5 seq_plataforma = max + 1 por (usuário, plataforma)', sp = n + 1, 'max ' || n || ' -> ' || sp);
END $$;

-- rejeitado: doador sem conta na plataforma do vídeo
DO $$
DECLARE
    v uuid; dv timestamptz; u bigint; s integer; pg integer;
BEGIN
    SELECT vi.id_video, vi.dataH, us.id_usuario INTO v, dv, u
    FROM video vi JOIN canal ca ON ca.id_canal = vi.id_canal
    CROSS JOIN LATERAL (
        SELECT x.id_usuario FROM usuario x
        WHERE NOT EXISTS (SELECT 1 FROM plataformausuario pu WHERE pu.id_usuario = x.id_usuario AND pu.nro_plataforma = ca.nro_plataforma)
        ORDER BY x.id_usuario LIMIT 1) us
    ORDER BY vi.id_video LIMIT 1;
    INSERT INTO comentario (id_video, id_usuario, dataH, coment_on) VALUES (v, u, dv, false) RETURNING seq INTO s;
    INSERT INTO doacao (id_video, seq_comentario, valor, status) VALUES (v, s, 50, 'lido') RETURNING seq_pg INTO pg;
    BEGIN
        INSERT INTO mecanismoplat (id_video, seq_comentario, seq_doacao) VALUES (v, s, pg);
        PERFORM pg_temp.registra('T5 rejeita doador sem conta na plataforma', false, 'aceito');
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp.registra('T5 rejeita doador sem conta na plataforma', SQLSTATE = '23503',
                                 '[' || SQLSTATE || '] ' || left(SQLERRM, 110));
    END;
    INSERT INTO cartaocredito VALUES (v, s, pg, '4000000000000002', 'Visa');  -- completa a doação (T6)
END $$;

-- ---------------------------------------------------------------------
-- T7 · Coerência temporal (vídeo x canal e canal x plataforma)
-- ---------------------------------------------------------------------
SELECT pg_temp.espera_erro('T7 rejeita vídeo anterior à criação do canal',
    'INSERT INTO steam_do_bedo.video (id_canal, titulo, dataH)
     SELECT id_canal, ''teste T7'', data - interval ''1 day'' FROM steam_do_bedo.canal ORDER BY id_canal LIMIT 1',
    '23514');

SELECT pg_temp.espera_erro('T7 rejeita canal anterior à fundação da plataforma',
    'UPDATE steam_do_bedo.canal c SET data = p.data_fund - 1
     FROM steam_do_bedo.plataforma p
     WHERE p.nro = c.nro_plataforma AND c.id_canal = (SELECT min(id_canal) FROM steam_do_bedo.canal)',
    '23514');

SELECT pg_temp.espera_erro('T7 rejeita adiar a postagem do vídeo para depois dos comentários',
    'UPDATE steam_do_bedo.video v SET dataH = (SELECT max(dataH) + interval ''1 day'' FROM steam_do_bedo.comentario c WHERE c.id_video = v.id_video)
     WHERE v.id_video = (SELECT id_video FROM steam_do_bedo.comentario ORDER BY id_video LIMIT 1)',
    '23514');

DO $$
DECLARE c bigint; d timestamptz;
BEGIN
    SELECT id_canal, data INTO c, d FROM canal ORDER BY id_canal LIMIT 1;
    INSERT INTO video (id_canal, titulo, dataH) VALUES (c, 'teste T7 ok', d + interval '1 minute');
    PERFORM pg_temp.registra('T7 aceita vídeo depois da criação do canal', true, '');
END $$;

-- ---------------------------------------------------------------------
-- T8 · Máximo de 5 níveis por canal
-- ---------------------------------------------------------------------
SELECT pg_temp.espera_erro('T8 rejeita o sexto nível',
    'INSERT INTO steam_do_bedo.nivelcanal (id_canal, nivel, valor, gif)
     SELECT id_canal, ''Sexto'', 1, ''x.gif'' FROM steam_do_bedo.nivelcanal GROUP BY id_canal HAVING count(*) = 5 ORDER BY id_canal LIMIT 1',
    '23514');

DO $$
DECLARE c bigint;
BEGIN
    SELECT id_canal INTO c FROM canal cn WHERE NOT EXISTS (SELECT 1 FROM nivelcanal n WHERE n.id_canal = cn.id_canal) ORDER BY id_canal LIMIT 1;
    INSERT INTO nivelcanal (id_canal, nivel, valor, gif)
    SELECT c, 'Nível ' || g, g * 5, 'n' || g || '.gif' FROM generate_series(1, 5) g;
    PERFORM pg_temp.registra('T8 aceita 5 níveis num canal sem níveis', (SELECT count(*) FROM nivelcanal WHERE id_canal = c) = 5, '');
END $$;

-- ---------------------------------------------------------------------
-- T9 · Streamer = usuário com passaporte
-- ---------------------------------------------------------------------
-- rejeitado: canal de quem tem conta mas não tem passaporte
SELECT pg_temp.espera_erro('T9 rejeita canal de usuário que não é streamer',
    'INSERT INTO steam_do_bedo.canal (nome, nro_plataforma, tipo, id_streamer)
     SELECT ''Canal teste T9'', pu.nro_plataforma, ''publico'', pu.id_usuario
     FROM steam_do_bedo.plataformausuario pu
     WHERE NOT EXISTS (SELECT 1 FROM steam_do_bedo.streamerpais s WHERE s.id_streamer = pu.id_usuario)
     ORDER BY pu.id_usuario LIMIT 1',
    '23503');

SELECT pg_temp.espera_erro('T9 rejeita participação de quem não é streamer',
    'INSERT INTO steam_do_bedo.participa (id_video, id_streamer)
     SELECT (SELECT id_video FROM steam_do_bedo.video ORDER BY id_video LIMIT 1), u.id_usuario
     FROM steam_do_bedo.usuario u
     WHERE NOT EXISTS (SELECT 1 FROM steam_do_bedo.streamerpais s WHERE s.id_streamer = u.id_usuario)
     ORDER BY u.id_usuario LIMIT 1',
    '23503');

SELECT pg_temp.espera_erro('T9 rejeita apagar o último passaporte de quem tem canal',
    'DELETE FROM steam_do_bedo.streamerpais s
     WHERE s.id_streamer = (SELECT c.id_streamer FROM steam_do_bedo.canal c
                            WHERE (SELECT count(*) FROM steam_do_bedo.streamerpais x WHERE x.id_streamer = c.id_streamer) = 1
                            ORDER BY c.id_canal LIMIT 1)',
    '23503');

DO $$
DECLARE v uuid; dono bigint; s bigint;
BEGIN
    SELECT vi.id_video, ca.id_streamer INTO v, dono FROM video vi JOIN canal ca USING (id_canal) ORDER BY vi.id_video LIMIT 1;
    SELECT sp.id_streamer INTO s FROM streamerpais sp
    WHERE sp.id_streamer <> dono AND NOT EXISTS (SELECT 1 FROM participa p WHERE p.id_video = v AND p.id_streamer = sp.id_streamer)
    ORDER BY sp.id_streamer LIMIT 1;
    INSERT INTO participa VALUES (v, s);
    PERFORM pg_temp.registra('T9 aceita participação de streamer', true, '');
END $$;

-- ---------------------------------------------------------------------
-- T10 · Dono do canal tem conta na plataforma
-- ---------------------------------------------------------------------
SELECT pg_temp.espera_erro('T10 rejeita canal em plataforma onde o streamer não tem conta',
    'INSERT INTO steam_do_bedo.canal (nome, nro_plataforma, tipo, id_streamer)
     SELECT ''Canal teste T10'', p.nro, ''publico'', s.id_streamer
     FROM steam_do_bedo.streamerpais s
     CROSS JOIN steam_do_bedo.plataforma p
     WHERE NOT EXISTS (SELECT 1 FROM steam_do_bedo.plataformausuario pu WHERE pu.id_usuario = s.id_streamer AND pu.nro_plataforma = p.nro)
     ORDER BY s.id_streamer, p.nro LIMIT 1',
    '23503');

DO $$
DECLARE s bigint; p integer; c bigint; qtd_antes bigint;
BEGIN
    -- streamer com conta numa plataforma onde ainda não tem canal
    SELECT pu.id_usuario, pu.nro_plataforma INTO s, p
    FROM plataformausuario pu
    JOIN streamerpais sp ON sp.id_streamer = pu.id_usuario
    WHERE NOT EXISTS (SELECT 1 FROM canal c WHERE c.id_streamer = pu.id_usuario AND c.nro_plataforma = pu.nro_plataforma)
    ORDER BY pu.id_usuario, pu.nro_plataforma LIMIT 1;
    INSERT INTO canal (nome, nro_plataforma, tipo, id_streamer) VALUES ('Canal teste T10 ok', p, 'publico', s)
    RETURNING id_canal INTO c;
    PERFORM pg_temp.registra('T10 aceita canal com conta (e T9, T7)', c IS NOT NULL, 'id_canal ' || c);
END $$;

-- ---------------------------------------------------------------------
-- Conferência final dos derivados depois de todos os testes
-- ---------------------------------------------------------------------
DO $$
BEGIN
    PERFORM pg_temp.registra('Derivados: qtd_visualizacoes = SUM(visu_total) em todos os canais',
        NOT EXISTS (SELECT 1 FROM canal c
                    WHERE c.qtd_visualizacoes <> (SELECT coalesce(sum(v.visu_total), 0) FROM video v WHERE v.id_canal = c.id_canal)),
        '');
    PERFORM pg_temp.registra('Derivados: qtd_users = COUNT(PlataformaUsuario) em todas as plataformas',
        NOT EXISTS (SELECT 1 FROM plataforma p
                    WHERE p.qtd_users <> (SELECT count(*) FROM plataformausuario pu WHERE pu.nro_plataforma = p.nro)),
        '');
END $$;

-- Totalidade (T6) de tudo o que os testes inseriram, conferida antes do fim
SET CONSTRAINTS ALL IMMEDIATE;

\o
SELECT ordem AS "#", CASE WHEN ok THEN 'OK' ELSE 'FALHOU' END AS resultado, caso, detalhe
FROM resultado ORDER BY ordem;

DO $$
DECLARE n_falhas int; n_total int;
BEGIN
    SELECT count(*) FILTER (WHERE NOT ok), count(*) INTO n_falhas, n_total FROM resultado;
    IF n_falhas > 0 THEN
        RAISE EXCEPTION 'testes_triggers: % de % casos falharam', n_falhas, n_total;
    END IF;
    RAISE NOTICE 'testes_triggers: % casos, todos OK', n_total;
END $$;

ROLLBACK;
