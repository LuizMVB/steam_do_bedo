-- =====================================================================
-- Projeto de Banco de Dados 2026/2 - Stream do Bedo
-- Arquivo 7/7: chamadas das functions (consultas 1 a 12) - PostgreSQL 17
--
-- O que faz: chama cada function sem filtro e com o parâmetro opcional,
-- com valores reais da carga do seed_v3.sql (escala 1), mais algumas
-- consultas de exemplo em cima do resultado.
--
-- Ordem de execução (DEC-030): ddl.sql -> seed_v3.sql -> views.sql ->
-- procedures.sql -> triggers.sql -> indices.sql -> queries.sql.
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
