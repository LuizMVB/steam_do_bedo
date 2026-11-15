-- =====================================================================
-- Projeto de Banco de Dados 2026/2 - Stream do Bedo
-- Arquivo 6/7: índices de apoio (item mandatório 4) - PostgreSQL 17
--
-- O que faz: cria os índices secundários escolhidos pelo grupo, além dos
-- criados automaticamente por PRIMARY KEY e UNIQUE.
--
-- Ordem de execução (DEC-030): ddl.sql -> seed_v3.sql -> views.sql ->
-- procedures.sql -> triggers.sql -> indices.sql -> queries.sql.
-- Depois da carga: criar o índice sobre a tabela pronta é mais rápido do
-- que mantê-lo linha a linha durante a inserção.
--
-- Teto de 5 índices de apoio (enunciado, item 4). O índice de view
-- materializada CONTA no teto (P09, DEC-028):
--   1. ux_mv_interacoes_video (id_canal, id_video)   views.sql, V3
--   2. ux_mv_faturamento_canal (id_canal)            views.sql, V4
--   3. idx_inscricao_id_membro                       este arquivo
--   4. idx_canal_id_streamer                         este arquivo
--   5. idx_video_id_canal_cobertura                  este arquivo
-- Medido e descartado: Canal (nro_plataforma), da DEC-018 (sem ganho a
-- frio; ver DEC-034). Hash foi medido no lugar dos B-tree de igualdade
-- (Inscricao.id_membro, Canal.id_streamer) e não trouxe vantagem.
--
-- Metodologia (professor, 07:03-08:16; DEC-034): inventário dos predicados
-- das functions (bench/predicados.md) -> distribuição de cada coluna em
-- pg_stats -> tipo do índice pelo tipo do predicado -> medida a frio com
-- e sem o índice (bench/resultados.csv) e do overhead de inserção
-- (bench/escrita.csv). Os números estão na DEC-034.
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
-- DEC-034 (substitui idx_inscricao_nick_membro da DEC-018: a chave agora
--   é id_usuario, DEC-022)
-- Medido (a frio, mediana de 5): item 6 com filtro 160 -> 7 ms; páginas
--   lidas 4.040 -> 54. Overhead de INSERT em lote: +59% (300 mil linhas,
--   ordem aleatória); 10 MB na tabela inteira.
-- Hash x B-tree: o predicado é só de igualdade, então o hash foi medido.
--   Leu as mesmas 54 páginas, ficou maior (10,6 MB contra 8,7 MB no lote
--   de 300 mil) e não inseriu mais rápido. Fica o B-tree, que também
--   entrega em ordem e serve à verificação de FK.
-- Cuidado: inscrição é escrita rara (o usuário assina um canal de vez em
--   quando) e a busca por usuário é leitura frequente.
-- ---------------------------------------------------------------------
CREATE INDEX idx_inscricao_id_membro
    ON steam_do_bedo.inscricao (id_membro);                    -- DEC-034

-- ---------------------------------------------------------------------
-- 4. idx_canal_id_streamer
-- O quê: B-tree em Canal (id_streamer).
-- Por quê: item 3 com filtro por streamer (nick -> canais dele). Também
--   atende as verificações dos triggers T9 e T10 do lado de StreamerPais e
--   PlataformaUsuario ("este usuário tem canal?") e a FK
--   canal_id_streamer_fkey. Igualdade, poucos canais por streamer.
-- DEC-034
-- Medido: item 3 com filtro, páginas lidas 1.554 -> 892; a quente 9 -> 1,3
--   ms (a frio a diferença some no ruído, ~150 ms nos dois). 736 kB.
--   Overhead de INSERT: +17% numa tabela de escrita rara.
-- Hash x B-tree: mesmas páginas lidas, mesmo tempo, hash maior: B-tree.
-- ---------------------------------------------------------------------
CREATE INDEX idx_canal_id_streamer
    ON steam_do_bedo.canal (id_streamer);                      -- DEC-034

-- ---------------------------------------------------------------------
-- 5. idx_video_id_canal_cobertura
-- O quê: B-tree em Video (id_canal) com visu_total no INCLUDE (índice de
--   cobertura).
-- Por quê: o item 1 conta os vídeos e soma visu_total por canal. Com
--   filtro de plataforma, mesmo poucos canais faziam o plano varrer Video
--   inteira (155 MB): video_canal_titulo_datah_key começa por id_canal, mas
--   não tem visu_total, e os vídeos de um canal estão espalhados pela
--   tabela (correlação física de id_canal = 0,01, porque a ordem física é a
--   do UUID v7, isto é, do tempo). Com o INCLUDE, a contagem e a soma saem
--   só do índice (Index Only Scan), sem visitar a tabela.
-- DEC-034
-- Medido: item 1 com plataforma pequena (Kick, 3,5% dos canais): 587 ->
--   341 ms a frio e 257 -> 22 ms a quente; páginas 25.526 -> 9.530.
--   38 MB; overhead de INSERT em Video +9%.
-- Cuidado:
--   * Sem filtro ou com plataforma grande (YouTube, 28% dos canais) o
--     planejador continua varrendo a tabela: o predicado é concentrado
--     demais (o exemplo do professor, 07:44). O ganho é das plataformas
--     pequenas, que são a maioria das 28.
--   * Index-only scan depende do visibility map: precisa de VACUUM em dia
--     numa tabela com inserção contínua.
--   * Substitui Canal (nro_plataforma), da DEC-018, que foi medido de novo e
--     não teve ganho: Canal tem 951 páginas e é lida em milissegundos; o
--     custo dos itens 1, 4 e 12 estava em Video.
-- ---------------------------------------------------------------------
CREATE INDEX idx_video_id_canal_cobertura
    ON steam_do_bedo.video (id_canal) INCLUDE (visu_total);    -- DEC-034

ANALYZE steam_do_bedo.inscricao;
ANALYZE steam_do_bedo.canal;
VACUUM (ANALYZE) steam_do_bedo.video;   -- visibility map em dia para o index-only scan
