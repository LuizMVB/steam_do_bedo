-- Consultas (chamadas) das stored procedures definidas em procedures.sql
-- Cada procedure é chamada sem parâmetro (sem filtro) e com o parâmetro opcional.
-- Ajuste os valores dos filtros conforme os dados carregados pelo seed.sql.
--
-- Ordem de execução: ddl.sql -> seed.sql -> procedures.sql -> queries.sql
-- DEC-007: os itens 6, 9 e 11 aceitam p_data_ref (padrão CURRENT_DATE) e só
-- consideram as inscrições com data_inscricao <= p_data_ref.

-- 1. Streamers com maior quantidade de vídeos publicados (filtro opcional: plataforma)

-- Sem filtro
SELECT * FROM steam_do_bedo.sp_obter_streamers_com_maior_qtd_videos_publicados();

-- Filtrando pela plataforma nº 1 (YouTube)
SELECT * FROM steam_do_bedo.sp_obter_streamers_com_maior_qtd_videos_publicados(1);

-- 2. Vídeos mais comentados: comentários online, offline e total (filtro opcional: canal)

-- Sem filtro
SELECT * FROM steam_do_bedo.sp_obter_videos_mais_comentados();

-- Filtrando por um canal (substituir pelo nome de um canal existente)
SELECT * FROM steam_do_bedo.sp_obter_videos_mais_comentados('ninja_1962 TV');

-- 3. Canais por quantidade total de interações e média por vídeo (filtro opcional: streamer)

-- Sem filtro
SELECT * FROM steam_do_bedo.sp_obter_canais_por_qtd_total_interacoes();

-- Filtrando por um streamer (substituir pelo nick de um streamer existente)
SELECT * FROM steam_do_bedo.sp_obter_canais_por_qtd_total_interacoes('ninja_1962');

-- 4. Canais pelo valor médio de doações por comentário (filtro opcional: plataforma)

-- Sem filtro
SELECT * FROM steam_do_bedo.sp_obter_canais_pela_media_doacoes_por_comentario();

-- Filtrando pela plataforma nº 2 (Twitch)
SELECT * FROM steam_do_bedo.sp_obter_canais_pela_media_doacoes_por_comentario(2);

-- 5. Canais patrocinados e valores pagos por empresa (filtro opcional: nome da empresa)

-- Sem filtro
SELECT * FROM steam_do_bedo.sp_obter_canais_patrocinados_com_valores_por_empresa();

-- Filtrando por uma empresa (nome completo, como em Empresa.nome)
SELECT * FROM steam_do_bedo.sp_obter_canais_patrocinados_com_valores_por_empresa('Google LLC');

-- 6. Qtd de canais em que cada usuário é membro e gasto mensal (moeda local e USD)
--    (filtro opcional: usuário)

-- Sem filtro
SELECT * FROM steam_do_bedo.sp_obter_qtd_canais_e_gasto_mensal_por_usuario();

-- Filtrando por um usuário (substituir pelo nick de um usuário com inscrição)
SELECT * FROM steam_do_bedo.sp_obter_qtd_canais_e_gasto_mensal_por_usuario('ninja_1962');

-- DEC-007: gasto mensal considerando só as inscrições feitas até 01/01/2020
SELECT * FROM steam_do_bedo.sp_obter_qtd_canais_e_gasto_mensal_por_usuario(p_data_ref => DATE '2020-01-01');

-- Os 10 usuários que mais gastam por mês (em USD)
SELECT * FROM steam_do_bedo.sp_obter_qtd_canais_e_gasto_mensal_por_usuario() LIMIT 10;

-- Usuários membros de 3 ou mais canais
SELECT * FROM steam_do_bedo.sp_obter_qtd_canais_e_gasto_mensal_por_usuario()
WHERE qtd_canais >= 3;

-- Gasto mensal total e médio por moeda de residência (em USD)
SELECT moeda,
       COUNT(*)                     AS qtd_usuarios,
       SUM(vr_mensal_usd)           AS vr_total_usd,
       ROUND(AVG(vr_mensal_usd), 2) AS vr_medio_usd
FROM steam_do_bedo.sp_obter_qtd_canais_e_gasto_mensal_por_usuario()
GROUP BY moeda
ORDER BY vr_total_usd DESC;

-- 7. Canais que já receberam doações e a soma dos valores (filtro opcional: canal)

-- Sem filtro
SELECT * FROM steam_do_bedo.sp_obter_canais_com_doacoes_recebidas();

-- Filtrando por um canal (substituir pelo nome de um canal com doações; se o nome
-- existir em mais de uma plataforma, retorna uma linha por plataforma)
SELECT * FROM steam_do_bedo.sp_obter_canais_com_doacoes_recebidas('ninja_1962 TV');

-- Os 10 canais que mais receberam doações
SELECT * FROM steam_do_bedo.sp_obter_canais_com_doacoes_recebidas() LIMIT 10;

-- Canais com mais de 100 doações recebidas
SELECT * FROM steam_do_bedo.sp_obter_canais_com_doacoes_recebidas()
WHERE qtd_doacoes > 100;

-- Valor médio por doação de cada canal
SELECT nome_canal, nro_plataforma, qtd_doacoes, soma_vr_doacao,
       ROUND(soma_vr_doacao / qtd_doacoes, 2) AS vr_medio_doacao
FROM steam_do_bedo.sp_obter_canais_com_doacoes_recebidas()
ORDER BY vr_medio_doacao DESC;

-- 8. Top-k canais que mais recebem patrocínio e os valores recebidos

-- Top 5 canais
SELECT * FROM steam_do_bedo.sp_obter_top_k_canais_por_patrocinio(5);

-- Top 10 canais
SELECT * FROM steam_do_bedo.sp_obter_top_k_canais_por_patrocinio(10);

-- 9. Top-k canais que mais recebem aportes de membros e os valores recebidos (em USD)

-- Top 5 canais
SELECT * FROM steam_do_bedo.sp_obter_top_k_canais_por_aportes_de_membros(5);

-- Top 10 canais
SELECT * FROM steam_do_bedo.sp_obter_top_k_canais_por_aportes_de_membros(10);

-- DEC-007: top 10 considerando só as inscrições feitas até 01/01/2020
SELECT * FROM steam_do_bedo.sp_obter_top_k_canais_por_aportes_de_membros(10, DATE '2020-01-01');

-- Top 3 canais, com o aporte médio por membro (USD)
SELECT nome_canal, nro_plataforma, qtd_membros, vr_total_aportes,
       ROUND(vr_total_aportes / qtd_membros, 2) AS vr_medio_por_membro
FROM steam_do_bedo.sp_obter_top_k_canais_por_aportes_de_membros(3);

-- Top 10 canais, com a participação de cada um no total do top 10
SELECT nome_canal, nro_plataforma, vr_total_aportes,
       ROUND(100 * vr_total_aportes / SUM(vr_total_aportes) OVER (), 2) AS pct_do_top
FROM steam_do_bedo.sp_obter_top_k_canais_por_aportes_de_membros(10);

-- Top 10 canais por aportes de membros, com o nome do streamer responsável
SELECT t.nome_canal, c.nick_streamer, t.qtd_membros, t.vr_total_aportes
FROM steam_do_bedo.sp_obter_top_k_canais_por_aportes_de_membros(10) t
JOIN steam_do_bedo.canal c ON c.nome = t.nome_canal AND c.nro_plataforma = t.nro_plataforma
ORDER BY t.vr_total_aportes DESC, t.nome_canal;

-- 10. Top-k canais que mais receberam doações considerando todos os vídeos

-- Top 5 canais
SELECT * FROM steam_do_bedo.sp_obter_top_k_canais_por_doacoes_recebidas(5);

-- Top 10 canais
SELECT * FROM steam_do_bedo.sp_obter_top_k_canais_por_doacoes_recebidas(10);

-- Top 10 canais, com o valor médio por doação
SELECT nome_canal, nro_plataforma, qtd_videos_com_doacao, qtd_doacoes, vr_total_doacoes,
       ROUND(vr_total_doacoes / qtd_doacoes, 2) AS vr_medio_doacao
FROM steam_do_bedo.sp_obter_top_k_canais_por_doacoes_recebidas(10);

-- 11. Top-k canais que mais faturam (patrocínio + membros + doações)

-- Top 5 canais
SELECT * FROM steam_do_bedo.sp_obter_top_k_canais_por_faturamento(5);

-- Top 10 canais
SELECT * FROM steam_do_bedo.sp_obter_top_k_canais_por_faturamento(10);

-- DEC-007: top 10 com membros inscritos até 01/01/2020
SELECT * FROM steam_do_bedo.sp_obter_top_k_canais_por_faturamento(10, DATE '2020-01-01');

-- Top 10 canais, com a participação de cada fonte no faturamento do canal
SELECT nome_canal, nro_plataforma, vr_faturamento_total,
       ROUND(100 * vr_patrocinio / vr_faturamento_total, 1) AS pct_patrocinio,
       ROUND(100 * vr_membros    / vr_faturamento_total, 1) AS pct_membros,
       ROUND(100 * vr_doacoes    / vr_faturamento_total, 1) AS pct_doacoes
FROM steam_do_bedo.sp_obter_top_k_canais_por_faturamento(10);

-- 12: ainda não implementada em procedures.sql; incluir as consultas aqui
-- quando for criada.
