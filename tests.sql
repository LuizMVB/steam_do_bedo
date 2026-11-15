-- =====================================================================
-- Projeto de Banco de Dados 2026/2 - Stream do Bedo
-- Arquivo 6/6: chamadas das functions (consultas 1 a 12) - PostgreSQL 17
--
-- O que faz: chama cada function do functions.sql em vários cenários:
--   * sem filtro (o parâmetro opcional fica no DEFAULT NULL);
--   * com filtro de um valor grande e de um valor pequeno;
--   * com filtro de um valor que não existe (devolve zero linhas, sem erro);
--   * nos top-k, com k pequeno, k = 10 e k nulo (todos).
-- O arquivo só lê: não insere, não altera e não apaga nada.
--
-- Ordem de execução (DEC-030): ddl.sql -> seed.sql -> views.sql ->
-- functions.sql -> triggers.sql -> tests.sql.
--
-- Valores dos filtros: o seed é determinístico, então na escala 1 os
-- valores abaixo existem e são sempre os mesmos.
--   plataforma grande: 'YouTube'          plataforma pequena: 'Kick'
--   plataforma fora do top-10 do item 12: 'Rooter'
--   canal: 'Echo.Queen 136733 TV'          (o canal com mais visualizações)
--   streamer: 'echo.queen_136733'          (dono desse canal)
--   usuário: 'ghost.yt_297686'             (o membro com mais inscrições)
--   empresa: 'Red Bull GmbH'               (a que mais patrocina)
-- As plataformas são passadas pelo nome, numa subconsulta, para o arquivo
-- não depender do número gerado pela IDENTITY.
--
-- As consultas sem filtro devolvem milhares de linhas; aqui vêm com LIMIT
-- para a saída caber na tela. Como as functions SQL são expandidas pelo
-- planejador (inlining), o LIMIT também reduz o trabalho da consulta.
--
-- Itens 2, 3 e 8 a 11 leem views materializadas: refletem a última
-- CALL steam_do_bedo.sp_refresh_views() (DEC-028).
-- DEC-029, DEC-035
-- =====================================================================

\set ON_ERROR_STOP on
SET search_path TO steam_do_bedo;

-- ---------------------------------------------------------------------
-- 1. Streamers com mais vídeos publicados e soma das visualizações
--    (filtro opcional: plataforma)
-- ---------------------------------------------------------------------
-- sem filtro
SELECT * FROM sp_obter_streamers_com_maior_qtd_videos_publicados() LIMIT 10;
-- plataforma grande
SELECT * FROM sp_obter_streamers_com_maior_qtd_videos_publicados(
    (SELECT nro FROM plataforma WHERE nome = 'YouTube')) LIMIT 10;
-- plataforma pequena (usa o índice de cobertura em Video, DEC-034)
SELECT * FROM sp_obter_streamers_com_maior_qtd_videos_publicados(
    (SELECT nro FROM plataforma WHERE nome = 'Kick')) LIMIT 10;
-- plataforma inexistente: zero linhas
SELECT * FROM sp_obter_streamers_com_maior_qtd_videos_publicados(-1);

-- ---------------------------------------------------------------------
-- 2. Vídeos mais comentados: comentários online, offline e total
--    (filtro opcional: canal)
-- ---------------------------------------------------------------------
-- sem filtro
SELECT * FROM sp_obter_videos_mais_comentados() LIMIT 10;
-- canal com mais visualizações
SELECT * FROM sp_obter_videos_mais_comentados('Echo.Queen 136733 TV') LIMIT 10;
-- canal inexistente: zero linhas
SELECT * FROM sp_obter_videos_mais_comentados('Canal que não existe');

-- ---------------------------------------------------------------------
-- 3. Canais por total de interações (online + offline) e média por vídeo
--    (filtro opcional: streamer)
-- ---------------------------------------------------------------------
-- sem filtro
SELECT * FROM sp_obter_canais_por_qtd_total_interacoes() LIMIT 10;
-- streamer dono do canal mais visto
SELECT * FROM sp_obter_canais_por_qtd_total_interacoes('echo.queen_136733');
-- streamer inexistente: zero linhas
SELECT * FROM sp_obter_canais_por_qtd_total_interacoes('streamer_inexistente');

-- ---------------------------------------------------------------------
-- 4. Canais pelo valor médio das doações por comentário, com quantidade e
--    total recebido em USD (filtro opcional: plataforma)
-- ---------------------------------------------------------------------
-- sem filtro
SELECT * FROM sp_obter_canais_pela_media_doacoes_por_comentario() LIMIT 10;
-- plataforma grande
SELECT * FROM sp_obter_canais_pela_media_doacoes_por_comentario(
    (SELECT nro FROM plataforma WHERE nome = 'YouTube')) LIMIT 10;
-- plataforma pequena
SELECT * FROM sp_obter_canais_pela_media_doacoes_por_comentario(
    (SELECT nro FROM plataforma WHERE nome = 'Kick')) LIMIT 10;

-- ---------------------------------------------------------------------
-- 5. Canais patrocinados e valor pago por empresa, em USD
--    (filtro opcional: empresa)
-- ---------------------------------------------------------------------
-- sem filtro
SELECT * FROM sp_obter_canais_patrocinados_com_valores_por_empresa() LIMIT 10;
-- empresa que mais patrocina
SELECT * FROM sp_obter_canais_patrocinados_com_valores_por_empresa('Red Bull GmbH') LIMIT 10;
-- empresa inexistente: zero linhas
SELECT * FROM sp_obter_canais_patrocinados_com_valores_por_empresa('Empresa Inexistente S.A.');

-- ---------------------------------------------------------------------
-- 6. De quantos canais cada usuário é membro e quanto gasta por mês, em
--    moeda local e em USD (filtro opcional: usuário)
-- ---------------------------------------------------------------------
-- sem filtro
SELECT * FROM sp_obter_qtd_canais_e_gasto_mensal_por_usuario() LIMIT 10;
-- membro com mais inscrições (usa idx_inscricao_id_membro, DEC-034)
SELECT * FROM sp_obter_qtd_canais_e_gasto_mensal_por_usuario('ghost.yt_297686');
-- usuário inexistente: zero linhas
SELECT * FROM sp_obter_qtd_canais_e_gasto_mensal_por_usuario('usuario_inexistente');

-- ---------------------------------------------------------------------
-- 7. Canais que já receberam doações e a soma recebida, em USD
--    (filtro opcional: canal)
-- ---------------------------------------------------------------------
-- sem filtro
SELECT * FROM sp_obter_canais_com_doacoes_recebidas() LIMIT 10;
-- canal com mais visualizações
SELECT * FROM sp_obter_canais_com_doacoes_recebidas('Echo.Queen 136733 TV');
-- canal inexistente: zero linhas
SELECT * FROM sp_obter_canais_com_doacoes_recebidas('Canal que não existe');

-- ---------------------------------------------------------------------
-- 8. Top-k canais por patrocínio recebido (USD)
-- ---------------------------------------------------------------------
SELECT * FROM sp_obter_top_k_canais_por_patrocinio(3);
SELECT * FROM sp_obter_top_k_canais_por_patrocinio(10);
-- k nulo devolve todos os canais patrocinados; aqui, só a contagem
SELECT count(*) AS canais_patrocinados FROM sp_obter_top_k_canais_por_patrocinio(NULL);

-- ---------------------------------------------------------------------
-- 9. Top-k canais por aportes mensais de membros (USD)
-- ---------------------------------------------------------------------
SELECT * FROM sp_obter_top_k_canais_por_aportes_de_membros(3);
SELECT * FROM sp_obter_top_k_canais_por_aportes_de_membros(10);
SELECT count(*) AS canais_com_membros FROM sp_obter_top_k_canais_por_aportes_de_membros(NULL);

-- ---------------------------------------------------------------------
-- 10. Top-k canais por doações recebidas em todos os vídeos (USD)
-- ---------------------------------------------------------------------
SELECT * FROM sp_obter_top_k_canais_por_doacoes_recebidas(3);
SELECT * FROM sp_obter_top_k_canais_por_doacoes_recebidas(10);
SELECT count(*) AS canais_com_doacoes FROM sp_obter_top_k_canais_por_doacoes_recebidas(NULL);

-- ---------------------------------------------------------------------
-- 11. Top-k canais por faturamento total: patrocínio + membros + doações
--     (USD)
-- ---------------------------------------------------------------------
SELECT * FROM sp_obter_top_k_canais_por_faturamento(3);
SELECT * FROM sp_obter_top_k_canais_por_faturamento(10);
-- participação de cada fonte de receita no faturamento dos 10 primeiros
SELECT nome_canal, nro_plataforma, vr_faturamento_total,
       round(100 * vr_patrocinio / vr_faturamento_total, 1) AS pct_patrocinio,
       round(100 * vr_membros    / vr_faturamento_total, 1) AS pct_membros,
       round(100 * vr_doacoes    / vr_faturamento_total, 1) AS pct_doacoes
FROM sp_obter_top_k_canais_por_faturamento(10);

-- ---------------------------------------------------------------------
-- 12. DESAFIO: top-k plataformas pela quantidade de streamers E de canais
--     (filtro opcional: plataforma). Interpretação na DEC-035:
--     streamer = dono de canal na plataforma, contado uma vez; ordena por
--     streamers e desempata por canais; a posição é a do ranking global,
--     mesmo com filtro; empates no corte de k entram todos.
-- ---------------------------------------------------------------------
-- top-3 e top-10
SELECT * FROM sp_obter_top_k_plataformas_por_streamers_e_canais(3);
SELECT * FROM sp_obter_top_k_plataformas_por_streamers_e_canais(10);
-- k nulo: todas as plataformas
SELECT * FROM sp_obter_top_k_plataformas_por_streamers_e_canais();
-- k maior que o número de plataformas: devolve todas, sem erro
SELECT count(*) AS plataformas_devolvidas
FROM sp_obter_top_k_plataformas_por_streamers_e_canais(100);
-- filtro por plataforma grande: posição global 1
SELECT * FROM sp_obter_top_k_plataformas_por_streamers_e_canais(
    10, (SELECT nro FROM plataforma WHERE nome = 'YouTube'));
-- filtro por plataforma pequena dentro do top-10: mostra a posição real,
-- e não "1º de 1"
SELECT * FROM sp_obter_top_k_plataformas_por_streamers_e_canais(
    10, (SELECT nro FROM plataforma WHERE nome = 'Kick'));
-- filtro por plataforma fora do top-10: volta com no_top_k = false
SELECT * FROM sp_obter_top_k_plataformas_por_streamers_e_canais(
    10, (SELECT nro FROM plataforma WHERE nome = 'Rooter'));
