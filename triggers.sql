-- =====================================================================
-- Projeto de Banco de Dados 2026/2 - Stream do Bedo
-- Arquivo 5/7: triggers (item mandatório 5) - PostgreSQL 17
--
-- O que faz: cria as functions de trigger e os triggers T1 a T11, que
-- mantêm a consistência exigida pelo minimundo e que não cabe em
-- PRIMARY KEY, UNIQUE, FOREIGN KEY ou CHECK (DEC-027).
--
-- Ordem de execução (DEC-030): ddl.sql -> seed_v3.sql -> views.sql ->
-- procedures.sql -> triggers.sql -> indices.sql -> queries.sql.
-- Este arquivo roda DEPOIS da carga, como o professor orientou (11:30:
-- "vou colocar as triggers separadas para não ter problema na hora de
-- fazer inserção"). Por isso o seed_v3.sql obedece às mesmas regras e
-- calcula sozinho os atributos derivados (qtd_users, qtd_visualizacoes).
-- Rodar este arquivo sobre uma carga que viola alguma regra não dá erro:
-- os triggers só valem para as escritas seguintes.
--
-- Mapa dos triggers (detalhes em DEC-027):
--   T1  Video              -> Canal.qtd_visualizacoes (derivado, delta)
--   T2  PlataformaUsuario  -> Plataforma.qtd_users (derivado, delta)
--   T3  Comentario         seq = max(seq) + 1 por vídeo
--   T4  Doacao             seq_pg = max(seq_pg) + 1 por comentário
--   T5  MecanismoPlat      seq_plataforma sequencial por (usuário, plataforma)
--   T6  4 especializações  doação disjunta (uma forma só) e total (ao menos uma)
--   T7  Comentario/Video/Canal/Plataforma  ordem temporal das datas
--   T8  NivelCanal         no máximo 5 níveis por canal
--   T9  Canal/Participa/StreamerPais  streamer = usuário com passaporte
--   T10 Canal/PlataformaUsuario  dono do canal tem conta na plataforma
--   T11 Doacao             converte o valor para USD no INSERT (DEC-026)
--
-- Convenções: function fn_tNN_<assunto>, trigger trg_tNN_<assunto>[_evento].
-- Triggers BEFORE da mesma tabela disparam em ordem alfabética do nome,
-- então o número no nome também fixa a ordem (T4 antes de T11 em Doacao).
-- Mensagens de erro usam ERRCODE de violação de integridade (23xxx) para
-- que a aplicação as trate como as das constraints.
-- =====================================================================

\set ON_ERROR_STOP on

SET search_path TO steam_do_bedo;

-- =====================================================================
-- T1 · Canal.qtd_visualizacoes = soma bruta de Video.visu_total
-- O quê: aplica a diferença (NEW - OLD, nulo conta como 0) no canal a cada
--   INSERT, UPDATE ou DELETE em Video. Se id_canal mudar, subtrai do canal
--   antigo e soma no novo.
-- Por quê: qtd_visualizacoes é atributo derivado do modelo relacional
--   ("requer atualização"). O professor (16:20-17:38) orientou guardar a
--   soma bruta e manter por trigger.
-- DEC-027
-- Cuidado:
--   * Trigger POR COMANDO com tabelas de transição (REFERENCING ... TABLE):
--     um INSERT de 10 mil vídeos do mesmo canal faz 1 UPDATE no canal, e
--     não 10 mil. O PostgreSQL não aceita tabela de transição em trigger
--     com mais de um evento nem com lista de colunas (UPDATE OF), por isso
--     são três triggers com a mesma function, e o de UPDATE dispara em
--     qualquer UPDATE de Video (a function ignora deltas zero).
--   * Os canais afetados são atualizados um a um em ordem de id_canal:
--     dois comandos concorrentes que mexem nos mesmos canais travam as
--     linhas na mesma ordem e não entram em deadlock.
--   * Soma via delta: se alguém desligar o trigger e alterar Video, o
--     derivado fica errado. A conferência está no testes_triggers.sql.
-- =====================================================================
CREATE OR REPLACE FUNCTION steam_do_bedo.fn_t01_video_qtd_visualizacoes()
RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    r RECORD;
BEGIN
    -- Um UPDATE por canal afetado, em ordem crescente de id_canal (trava
    -- sempre na mesma ordem: sem deadlock entre comandos concorrentes).
    IF TG_OP = 'INSERT' THEN
        FOR r IN SELECT id_canal, sum(coalesce(visu_total, 0)) AS delta
                 FROM t01_novos GROUP BY id_canal ORDER BY id_canal LOOP
            IF r.delta <> 0 THEN
                UPDATE steam_do_bedo.canal SET qtd_visualizacoes = qtd_visualizacoes + r.delta
                WHERE id_canal = r.id_canal;
            END IF;
        END LOOP;
    ELSIF TG_OP = 'DELETE' THEN
        FOR r IN SELECT id_canal, -sum(coalesce(visu_total, 0)) AS delta
                 FROM t01_antigos GROUP BY id_canal ORDER BY id_canal LOOP
            IF r.delta <> 0 THEN
                UPDATE steam_do_bedo.canal SET qtd_visualizacoes = qtd_visualizacoes + r.delta
                WHERE id_canal = r.id_canal;
            END IF;
        END LOOP;
    ELSE  -- UPDATE: novo menos antigo, por canal (cobre a troca de id_canal)
        FOR r IN SELECT id_canal, sum(v) AS delta FROM (
                     SELECT id_canal,  coalesce(visu_total, 0) AS v FROM t01_novos
                     UNION ALL
                     SELECT id_canal, -coalesce(visu_total, 0)      FROM t01_antigos
                 ) x
                 GROUP BY id_canal ORDER BY id_canal LOOP
            IF r.delta <> 0 THEN
                UPDATE steam_do_bedo.canal SET qtd_visualizacoes = qtd_visualizacoes + r.delta
                WHERE id_canal = r.id_canal;
            END IF;
        END LOOP;
    END IF;
    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_t01_video_qtd_visualizacoes_ins
    AFTER INSERT ON steam_do_bedo.video
    REFERENCING NEW TABLE AS t01_novos
    FOR EACH STATEMENT EXECUTE FUNCTION steam_do_bedo.fn_t01_video_qtd_visualizacoes();

CREATE TRIGGER trg_t01_video_qtd_visualizacoes_upd
    AFTER UPDATE ON steam_do_bedo.video
    REFERENCING OLD TABLE AS t01_antigos NEW TABLE AS t01_novos
    FOR EACH STATEMENT EXECUTE FUNCTION steam_do_bedo.fn_t01_video_qtd_visualizacoes();

CREATE TRIGGER trg_t01_video_qtd_visualizacoes_del
    AFTER DELETE ON steam_do_bedo.video
    REFERENCING OLD TABLE AS t01_antigos
    FOR EACH STATEMENT EXECUTE FUNCTION steam_do_bedo.fn_t01_video_qtd_visualizacoes();

-- =====================================================================
-- T2 · Plataforma.qtd_users = número de contas em PlataformaUsuario
-- O quê: soma +1 a cada conta criada e -1 a cada conta removida; se a
--   conta mudar de plataforma, -1 na antiga e +1 na nova.
-- Por quê: qtd_users é atributo derivado ("requer atualização
--   periódica"); o professor citou os dois derivados juntos (17:38).
--   Interpretação: usuários com conta na plataforma (relacionamento
--   "tem conta" do ER).
-- DEC-027
-- Cuidado: mesmo desenho do T1 (por comando, tabelas de transição, trava
--   em ordem). O "periódica" do enunciado permitiria um recálculo por job;
--   o trigger mantém o valor sempre exato, com custo de 1 UPDATE por
--   plataforma afetada por comando.
-- =====================================================================
CREATE OR REPLACE FUNCTION steam_do_bedo.fn_t02_plataformausuario_qtd_users()
RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    r RECORD;
BEGIN
    IF TG_OP = 'INSERT' THEN
        FOR r IN SELECT nro_plataforma, count(*) AS delta
                 FROM t02_novos GROUP BY nro_plataforma ORDER BY nro_plataforma LOOP
            UPDATE steam_do_bedo.plataforma SET qtd_users = qtd_users + r.delta WHERE nro = r.nro_plataforma;
        END LOOP;
    ELSIF TG_OP = 'DELETE' THEN
        FOR r IN SELECT nro_plataforma, -count(*) AS delta
                 FROM t02_antigos GROUP BY nro_plataforma ORDER BY nro_plataforma LOOP
            UPDATE steam_do_bedo.plataforma SET qtd_users = qtd_users + r.delta WHERE nro = r.nro_plataforma;
        END LOOP;
    ELSE
        FOR r IN SELECT nro_plataforma, sum(v) AS delta FROM (
                     SELECT nro_plataforma,  1 AS v FROM t02_novos
                     UNION ALL
                     SELECT nro_plataforma, -1      FROM t02_antigos
                 ) x
                 GROUP BY nro_plataforma ORDER BY nro_plataforma LOOP
            IF r.delta <> 0 THEN
                UPDATE steam_do_bedo.plataforma SET qtd_users = qtd_users + r.delta WHERE nro = r.nro_plataforma;
            END IF;
        END LOOP;
    END IF;
    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_t02_plataformausuario_qtd_users_ins
    AFTER INSERT ON steam_do_bedo.plataformausuario
    REFERENCING NEW TABLE AS t02_novos
    FOR EACH STATEMENT EXECUTE FUNCTION steam_do_bedo.fn_t02_plataformausuario_qtd_users();

CREATE TRIGGER trg_t02_plataformausuario_qtd_users_upd
    AFTER UPDATE ON steam_do_bedo.plataformausuario
    REFERENCING OLD TABLE AS t02_antigos NEW TABLE AS t02_novos
    FOR EACH STATEMENT EXECUTE FUNCTION steam_do_bedo.fn_t02_plataformausuario_qtd_users();

CREATE TRIGGER trg_t02_plataformausuario_qtd_users_del
    AFTER DELETE ON steam_do_bedo.plataformausuario
    REFERENCING OLD TABLE AS t02_antigos
    FOR EACH STATEMENT EXECUTE FUNCTION steam_do_bedo.fn_t02_plataformausuario_qtd_users();

-- =====================================================================
-- T3 · Comentario.seq sequencial por vídeo
-- O quê: se o INSERT não informar seq, usa max(seq) + 1 do vídeo.
-- Por quê: "Cada comentário tem um número sequencial que depende do
--   vídeo" (minimundo). Uma SEQUENCE global não serve (numeraria todos os
--   vídeos juntos); a geração estava em aberto na DEC-017.
-- DEC-027 (resolve o ponto em aberto da DEC-017)
-- Cuidado:
--   * Concorrência: duas inserções simultâneas no mesmo vídeo calculariam
--     o mesmo max + 1 e a segunda falharia pela PK. Por isso a linha do
--     vídeo é travada com SELECT ... FOR UPDATE antes de ler o max: a
--     segunda transação espera a primeira terminar e então enxerga o seq
--     já usado. Custo: comentários no mesmo vídeo ficam serializados (e
--     esperam também um UPDATE de visu_total do vídeo). Vídeos diferentes
--     não se bloqueiam.
--   * O max(seq) é barato: a PK (id_video, seq) é lida de trás para frente
--     e para na primeira linha (Index Only Scan Backward).
--   * Num INSERT de várias linhas, cada linha enxerga as anteriores do
--     mesmo comando (regra dos triggers BEFORE ROW), então a numeração
--     continua correta.
--   * Se seq vier informado, é respeitado (a PK garante a unicidade).
-- =====================================================================
CREATE OR REPLACE FUNCTION steam_do_bedo.fn_t03_comentario_seq()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.seq IS NULL THEN
        PERFORM 1 FROM steam_do_bedo.video WHERE id_video = NEW.id_video FOR UPDATE;
        SELECT coalesce(max(c.seq), 0) + 1 INTO NEW.seq
        FROM steam_do_bedo.comentario c
        WHERE c.id_video = NEW.id_video;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_t03_comentario_seq
    BEFORE INSERT ON steam_do_bedo.comentario
    FOR EACH ROW EXECUTE FUNCTION steam_do_bedo.fn_t03_comentario_seq();

-- =====================================================================
-- T4 · Doacao.seq_pg sequencial por comentário
-- O quê: se o INSERT não informar seq_pg, usa max(seq_pg) + 1 do
--   comentário.
-- Por quê: "Cada doação é identificada por um número sequencial que
--   depende do vídeo, do usuário e do comentário" (minimundo). O
--   comentário (id_video, seq) já determina o vídeo e o usuário.
-- DEC-027
-- Cuidado: trava a linha do comentário (FOR UPDATE), mesmo motivo do T3.
--   O max usa o prefixo da PK (id_video, seq_comentario, seq_pg).
-- =====================================================================
CREATE OR REPLACE FUNCTION steam_do_bedo.fn_t04_doacao_seq_pg()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.seq_pg IS NULL THEN
        PERFORM 1 FROM steam_do_bedo.comentario
        WHERE id_video = NEW.id_video AND seq = NEW.seq_comentario
        FOR UPDATE;
        SELECT coalesce(max(d.seq_pg), 0) + 1 INTO NEW.seq_pg
        FROM steam_do_bedo.doacao d
        WHERE d.id_video = NEW.id_video AND d.seq_comentario = NEW.seq_comentario;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_t04_doacao_seq_pg
    BEFORE INSERT ON steam_do_bedo.doacao
    FOR EACH ROW EXECUTE FUNCTION steam_do_bedo.fn_t04_doacao_seq_pg();

-- =====================================================================
-- T5 · MecanismoPlat.seq_plataforma sequencial por (usuário, plataforma)
-- O quê: se o INSERT não informar seq_plataforma, numera as doações via
--   mecanismo da plataforma de cada usuário em cada plataforma: 1, 2, 3...
--   Exige que o usuário tenha conta na plataforma do vídeo.
-- Por quê: "deve-se ser associado um número sequencial que depende do
--   usuário, do comentário e da plataforma" (minimundo). Interpretação do
--   grupo: o contador é do par (usuário, plataforma), como o número de um
--   Super Chat na conta do usuário; o comentário identifica a doação.
--   Pagar pelo mecanismo da plataforma exige ter conta nela ("tem conta").
-- DEC-027
-- Cuidado:
--   * Trava a conta do usuário na plataforma (PlataformaUsuario, FOR
--     UPDATE): duas doações simultâneas do mesmo usuário na mesma
--     plataforma ficam em fila e não repetem o número.
--   * O usuário e a plataforma não estão em MecanismoPlat; o max percorre
--     MecanismoPlat e confere cada linha pela PK de Comentario e de Video.
--     O custo cresce com o tamanho de MecanismoPlat (a menor das tabelas
--     de doação no seed). Num volume real, o próximo passo seria um
--     índice de apoio; não foi criado para não gastar o teto de 5 com uma
--     escrita rara (DEC-034).
-- =====================================================================
CREATE OR REPLACE FUNCTION steam_do_bedo.fn_t05_mecanismoplat_seq_plataforma()
RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_usuario    BIGINT;
    v_plataforma INTEGER;
BEGIN
    IF NEW.seq_plataforma IS NOT NULL THEN
        RETURN NEW;
    END IF;

    SELECT c.id_usuario, ca.nro_plataforma
    INTO v_usuario, v_plataforma
    FROM steam_do_bedo.comentario c
    JOIN steam_do_bedo.video v  ON v.id_video = c.id_video
    JOIN steam_do_bedo.canal ca ON ca.id_canal = v.id_canal
    WHERE c.id_video = NEW.id_video AND c.seq = NEW.seq_comentario;

    IF NOT FOUND THEN
        RETURN NEW;  -- a FK para Doacao rejeita a linha logo em seguida
    END IF;

    PERFORM 1 FROM steam_do_bedo.plataformausuario
    WHERE nro_plataforma = v_plataforma AND id_usuario = v_usuario
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'T5: o usuário % não tem conta na plataforma %; doação via mecanismo da plataforma exige conta',
                        v_usuario, v_plataforma
            USING ERRCODE = 'foreign_key_violation';
    END IF;

    -- Nested loop a partir de MecanismoPlat (pequena) com acesso pela PK de
    -- Comentario: evita varrer Comentario inteira atrás do usuário.
    SELECT coalesce(max(m.seq_plataforma), 0) + 1 INTO NEW.seq_plataforma
    FROM steam_do_bedo.mecanismoplat m
    JOIN steam_do_bedo.comentario c ON c.id_video = m.id_video AND c.seq = m.seq_comentario
    JOIN steam_do_bedo.video v      ON v.id_video = m.id_video
    JOIN steam_do_bedo.canal ca     ON ca.id_canal = v.id_canal
    WHERE c.id_usuario = v_usuario
      AND ca.nro_plataforma = v_plataforma;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_t05_mecanismoplat_seq_plataforma
    BEFORE INSERT ON steam_do_bedo.mecanismoplat
    FOR EACH ROW EXECUTE FUNCTION steam_do_bedo.fn_t05_mecanismoplat_seq_plataforma();

-- =====================================================================
-- T6 · Especialização de Doacao: disjunta e total
-- O quê:
--   (a) disjunta: rejeita a linha numa das 4 formas se a mesma doação já
--       existe em outra forma;
--   (b) total: ao fim da transação, toda doação precisa estar em uma das
--       4 formas (constraint trigger adiado).
-- Por quê: o ER marca a especialização com "d" (disjunta) e o minimundo
--   diz que "a doação pode ser feita de quatro formas": cada doação é
--   feita de exatamente uma forma.
-- DEC-027
-- Cuidado:
--   * (a) trava a linha de Doacao (FOR UPDATE) antes de conferir as
--     outras tabelas: sem isso, dois INSERT simultâneos em BitCoin e
--     PayPal para a mesma doação passariam os dois.
--   * (b) é DEFERRABLE INITIALLY DEFERRED: a doação e a sua forma são
--     inseridas em comandos separados da mesma transação, e a conferência
--     só acontece no COMMIT. Também confere no COMMIT a remoção ou troca
--     de chave de uma forma que deixaria a doação sem forma.
-- =====================================================================
CREATE OR REPLACE FUNCTION steam_do_bedo.fn_t06_doacao_disjunta()
RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_outra TEXT;
BEGIN
    PERFORM 1 FROM steam_do_bedo.doacao
    WHERE id_video = NEW.id_video AND seq_comentario = NEW.seq_comentario AND seq_pg = NEW.seq_doacao
    FOR UPDATE;

    SELECT forma INTO v_outra FROM (
        SELECT 'bitcoin' AS forma FROM steam_do_bedo.bitcoin
         WHERE id_video = NEW.id_video AND seq_comentario = NEW.seq_comentario AND seq_doacao = NEW.seq_doacao
        UNION ALL
        SELECT 'paypal' FROM steam_do_bedo.paypal
         WHERE id_video = NEW.id_video AND seq_comentario = NEW.seq_comentario AND seq_doacao = NEW.seq_doacao
        UNION ALL
        SELECT 'cartaocredito' FROM steam_do_bedo.cartaocredito
         WHERE id_video = NEW.id_video AND seq_comentario = NEW.seq_comentario AND seq_doacao = NEW.seq_doacao
        UNION ALL
        SELECT 'mecanismoplat' FROM steam_do_bedo.mecanismoplat
         WHERE id_video = NEW.id_video AND seq_comentario = NEW.seq_comentario AND seq_doacao = NEW.seq_doacao
    ) f
    WHERE forma <> TG_TABLE_NAME   -- a própria tabela é protegida pela PK
    LIMIT 1;

    IF v_outra IS NOT NULL THEN
        RAISE EXCEPTION 'T6: a doação (%, %, %) já está registrada como %; a especialização é disjunta',
                        NEW.id_video, NEW.seq_comentario, NEW.seq_doacao, v_outra
            USING ERRCODE = 'unique_violation';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_t06_bitcoin_disjunta
    BEFORE INSERT OR UPDATE OF id_video, seq_comentario, seq_doacao ON steam_do_bedo.bitcoin
    FOR EACH ROW EXECUTE FUNCTION steam_do_bedo.fn_t06_doacao_disjunta();
CREATE TRIGGER trg_t06_paypal_disjunta
    BEFORE INSERT OR UPDATE OF id_video, seq_comentario, seq_doacao ON steam_do_bedo.paypal
    FOR EACH ROW EXECUTE FUNCTION steam_do_bedo.fn_t06_doacao_disjunta();
CREATE TRIGGER trg_t06_cartaocredito_disjunta
    BEFORE INSERT OR UPDATE OF id_video, seq_comentario, seq_doacao ON steam_do_bedo.cartaocredito
    FOR EACH ROW EXECUTE FUNCTION steam_do_bedo.fn_t06_doacao_disjunta();
CREATE TRIGGER trg_t06_mecanismoplat_disjunta
    BEFORE INSERT OR UPDATE OF id_video, seq_comentario, seq_doacao ON steam_do_bedo.mecanismoplat
    FOR EACH ROW EXECUTE FUNCTION steam_do_bedo.fn_t06_doacao_disjunta();

-- (b) totalidade, conferida no COMMIT
CREATE OR REPLACE FUNCTION steam_do_bedo.fn_t06_doacao_total()
RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_video UUID;
    v_seq   INTEGER;
    v_pg    INTEGER;
BEGIN
    IF TG_TABLE_NAME = 'doacao' THEN
        v_video := NEW.id_video; v_seq := NEW.seq_comentario; v_pg := NEW.seq_pg;
    ELSE  -- DELETE ou troca de chave numa forma: confere a doação antiga
        v_video := OLD.id_video; v_seq := OLD.seq_comentario; v_pg := OLD.seq_doacao;
    END IF;

    -- doação apagada na mesma transação: nada a conferir
    IF NOT EXISTS (SELECT 1 FROM steam_do_bedo.doacao
                   WHERE id_video = v_video AND seq_comentario = v_seq AND seq_pg = v_pg) THEN
        RETURN NULL;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM steam_do_bedo.bitcoin       WHERE id_video = v_video AND seq_comentario = v_seq AND seq_doacao = v_pg)
       AND NOT EXISTS (SELECT 1 FROM steam_do_bedo.paypal        WHERE id_video = v_video AND seq_comentario = v_seq AND seq_doacao = v_pg)
       AND NOT EXISTS (SELECT 1 FROM steam_do_bedo.cartaocredito WHERE id_video = v_video AND seq_comentario = v_seq AND seq_doacao = v_pg)
       AND NOT EXISTS (SELECT 1 FROM steam_do_bedo.mecanismoplat WHERE id_video = v_video AND seq_comentario = v_seq AND seq_doacao = v_pg)
    THEN
        RAISE EXCEPTION 'T6: a doação (%, %, %) não tem forma de pagamento; a especialização é total',
                        v_video, v_seq, v_pg
            USING ERRCODE = 'foreign_key_violation';
    END IF;
    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_t06_doacao_total
    AFTER INSERT ON steam_do_bedo.doacao
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION steam_do_bedo.fn_t06_doacao_total();
CREATE CONSTRAINT TRIGGER trg_t06_bitcoin_total
    AFTER DELETE OR UPDATE OF id_video, seq_comentario, seq_doacao ON steam_do_bedo.bitcoin
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION steam_do_bedo.fn_t06_doacao_total();
CREATE CONSTRAINT TRIGGER trg_t06_paypal_total
    AFTER DELETE OR UPDATE OF id_video, seq_comentario, seq_doacao ON steam_do_bedo.paypal
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION steam_do_bedo.fn_t06_doacao_total();
CREATE CONSTRAINT TRIGGER trg_t06_cartaocredito_total
    AFTER DELETE OR UPDATE OF id_video, seq_comentario, seq_doacao ON steam_do_bedo.cartaocredito
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION steam_do_bedo.fn_t06_doacao_total();
CREATE CONSTRAINT TRIGGER trg_t06_mecanismoplat_total
    AFTER DELETE OR UPDATE OF id_video, seq_comentario, seq_doacao ON steam_do_bedo.mecanismoplat
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION steam_do_bedo.fn_t06_doacao_total();

-- =====================================================================
-- T7 · Coerência temporal
-- O quê: exige fundação da plataforma <= criação do canal <= postagem do
--   vídeo <= data do comentário. Confere nos dois sentidos: ao inserir ou
--   alterar o filho (comparando com o pai) e ao alterar a data do pai
--   (comparando com os filhos).
-- Por quê: escolha do grupo. Um comentário anterior ao vídeo ou um canal
--   anterior à plataforma são fatos impossíveis. Não cabe em CHECK porque
--   envolve outra tabela.
-- DEC-027
-- Cuidado:
--   * Canal.data é TIMESTAMPTZ e Plataforma.data_fund é DATE: a
--     comparação usa a data em UTC, para não depender do fuso da sessão.
--   * O minimundo não guarda a data de encerramento da plataforma (o
--     Mixer acabou em 2020), então isso não é conferido aqui; o seed
--     respeita.
--   * A verificação no pai (UPDATE de data) percorre os filhos pelo
--     índice que começa pela chave do pai: Comentario pela PK, Video pelo
--     UNIQUE (id_canal, ...). Canal por plataforma não tem índice próprio
--     (é um UPDATE raro em tabela pequena).
-- =====================================================================
CREATE OR REPLACE FUNCTION steam_do_bedo.fn_t07_comentario_temporal()
RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_data_video TIMESTAMPTZ;
BEGIN
    SELECT dataH INTO v_data_video FROM steam_do_bedo.video WHERE id_video = NEW.id_video;
    IF FOUND AND NEW.dataH < v_data_video THEN
        RAISE EXCEPTION 'T7: comentário em % é anterior à postagem do vídeo (%)', NEW.dataH, v_data_video
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_t07_comentario_temporal
    BEFORE INSERT OR UPDATE OF dataH, id_video ON steam_do_bedo.comentario
    FOR EACH ROW EXECUTE FUNCTION steam_do_bedo.fn_t07_comentario_temporal();

CREATE OR REPLACE FUNCTION steam_do_bedo.fn_t07_video_temporal()
RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_data_canal TIMESTAMPTZ;
BEGIN
    SELECT data INTO v_data_canal FROM steam_do_bedo.canal WHERE id_canal = NEW.id_canal;
    IF FOUND AND NEW.dataH < v_data_canal THEN
        RAISE EXCEPTION 'T7: vídeo postado em % é anterior à criação do canal (%)', NEW.dataH, v_data_canal
            USING ERRCODE = 'check_violation';
    END IF;

    IF TG_OP = 'UPDATE' AND NEW.dataH > OLD.dataH AND EXISTS (
        SELECT 1 FROM steam_do_bedo.comentario c
        WHERE c.id_video = NEW.id_video AND c.dataH < NEW.dataH) THEN
        RAISE EXCEPTION 'T7: o vídeo já tem comentários anteriores a %', NEW.dataH
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_t07_video_temporal
    BEFORE INSERT OR UPDATE OF dataH, id_canal ON steam_do_bedo.video
    FOR EACH ROW EXECUTE FUNCTION steam_do_bedo.fn_t07_video_temporal();

CREATE OR REPLACE FUNCTION steam_do_bedo.fn_t07_canal_temporal()
RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_fundacao DATE;
BEGIN
    SELECT data_fund INTO v_fundacao FROM steam_do_bedo.plataforma WHERE nro = NEW.nro_plataforma;
    IF FOUND AND (NEW.data AT TIME ZONE 'UTC')::DATE < v_fundacao THEN
        RAISE EXCEPTION 'T7: canal criado em % é anterior à fundação da plataforma (%)', NEW.data, v_fundacao
            USING ERRCODE = 'check_violation';
    END IF;

    IF TG_OP = 'UPDATE' AND NEW.data > OLD.data AND EXISTS (
        SELECT 1 FROM steam_do_bedo.video v
        WHERE v.id_canal = NEW.id_canal AND v.dataH < NEW.data) THEN
        RAISE EXCEPTION 'T7: o canal já tem vídeos anteriores a %', NEW.data
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_t07_canal_temporal
    BEFORE INSERT OR UPDATE OF data, nro_plataforma ON steam_do_bedo.canal
    FOR EACH ROW EXECUTE FUNCTION steam_do_bedo.fn_t07_canal_temporal();

CREATE OR REPLACE FUNCTION steam_do_bedo.fn_t07_plataforma_temporal()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.data_fund > OLD.data_fund AND EXISTS (
        SELECT 1 FROM steam_do_bedo.canal c
        WHERE c.nro_plataforma = NEW.nro AND (c.data AT TIME ZONE 'UTC')::DATE < NEW.data_fund) THEN
        RAISE EXCEPTION 'T7: a plataforma já tem canais criados antes de %', NEW.data_fund
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_t07_plataforma_temporal
    BEFORE UPDATE OF data_fund ON steam_do_bedo.plataforma
    FOR EACH ROW EXECUTE FUNCTION steam_do_bedo.fn_t07_plataforma_temporal();

-- =====================================================================
-- T8 · No máximo 5 níveis de membro por canal
-- O quê: rejeita o sexto nível de um canal.
-- Por quê: "Existem cinco níveis de membros e os nomes e os valores de
--   cada nível são definidos para cada canal" (minimundo).
-- DEC-027
-- Cuidado: trava a linha do canal (FOR NO KEY UPDATE) antes de contar,
--   para que dois INSERT simultâneos de nível no mesmo canal não passem
--   os dois com 4 níveis. NO KEY UPDATE não bloqueia as verificações de
--   FK (KEY SHARE) de quem insere vídeos no canal. No UPDATE só dispara
--   se o nível mudar de canal (cláusula WHEN).
-- =====================================================================
CREATE OR REPLACE FUNCTION steam_do_bedo.fn_t08_nivelcanal_maximo()
RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_qtd INTEGER;
BEGIN
    PERFORM 1 FROM steam_do_bedo.canal WHERE id_canal = NEW.id_canal FOR NO KEY UPDATE;
    SELECT count(*) INTO v_qtd FROM steam_do_bedo.nivelcanal WHERE id_canal = NEW.id_canal;
    IF v_qtd >= 5 THEN
        RAISE EXCEPTION 'T8: o canal % já tem 5 níveis de membro', NEW.id_canal
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_t08_nivelcanal_maximo_ins
    BEFORE INSERT ON steam_do_bedo.nivelcanal
    FOR EACH ROW EXECUTE FUNCTION steam_do_bedo.fn_t08_nivelcanal_maximo();

CREATE TRIGGER trg_t08_nivelcanal_maximo_upd
    BEFORE UPDATE OF id_canal ON steam_do_bedo.nivelcanal
    FOR EACH ROW WHEN (OLD.id_canal IS DISTINCT FROM NEW.id_canal)
    EXECUTE FUNCTION steam_do_bedo.fn_t08_nivelcanal_maximo();

-- =====================================================================
-- T9 · Streamer é o usuário com passaporte (StreamerPais)
-- O quê: o dono do canal (Canal.id_streamer) e quem participa do vídeo
--   (Participa.id_streamer) precisam ter ao menos uma linha em
--   StreamerPais. Remover o último passaporte de quem ainda tem canal ou
--   participação é rejeitado.
-- Por quê: no ER, Streamer é especialização de Usuario com passaporte e
--   país de passaporte ("tem nacionalidade"), e só streamers têm canal
--   ("um ou mais canais estão associados a cada streamer") e participam
--   de vídeos.
-- DEC-027
-- Cuidado: as linhas de passaporte encontradas são travadas com FOR KEY
--   SHARE, como faz uma FK: um DELETE concorrente do passaporte espera o
--   fim desta transação e então passa pela verificação do lado de
--   StreamerPais, que enxerga o canal novo.
-- =====================================================================
CREATE OR REPLACE FUNCTION steam_do_bedo.fn_t09_exige_streamer()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM 1 FROM steam_do_bedo.streamerpais WHERE id_streamer = NEW.id_streamer FOR KEY SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'T9: o usuário % não é streamer (não tem passaporte em StreamerPais)', NEW.id_streamer
            USING ERRCODE = 'foreign_key_violation';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_t09_canal_streamer
    BEFORE INSERT OR UPDATE OF id_streamer ON steam_do_bedo.canal
    FOR EACH ROW EXECUTE FUNCTION steam_do_bedo.fn_t09_exige_streamer();

CREATE TRIGGER trg_t09_participa_streamer
    BEFORE INSERT OR UPDATE OF id_streamer ON steam_do_bedo.participa
    FOR EACH ROW EXECUTE FUNCTION steam_do_bedo.fn_t09_exige_streamer();

CREATE OR REPLACE FUNCTION steam_do_bedo.fn_t09_streamerpais_remocao()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND NEW.id_streamer = OLD.id_streamer THEN
        RETURN NULL;  -- só trocou país ou número; continua streamer
    END IF;
    IF NOT EXISTS (SELECT 1 FROM steam_do_bedo.streamerpais WHERE id_streamer = OLD.id_streamer)
       AND (EXISTS (SELECT 1 FROM steam_do_bedo.canal WHERE id_streamer = OLD.id_streamer)
            OR EXISTS (SELECT 1 FROM steam_do_bedo.participa WHERE id_streamer = OLD.id_streamer)) THEN
        RAISE EXCEPTION 'T9: o usuário % ainda tem canal ou participação; não pode deixar de ser streamer', OLD.id_streamer
            USING ERRCODE = 'foreign_key_violation';
    END IF;
    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_t09_streamerpais_remocao
    AFTER DELETE OR UPDATE OF id_streamer ON steam_do_bedo.streamerpais
    FOR EACH ROW EXECUTE FUNCTION steam_do_bedo.fn_t09_streamerpais_remocao();

-- =====================================================================
-- T10 · Dono do canal tem conta na plataforma do canal
-- O quê: Canal (id_streamer, nro_plataforma) exige a linha
--   correspondente em PlataformaUsuario. Remover ou mudar essa conta
--   enquanto o canal existe é rejeitado.
-- Por quê: relacionamento "tem conta" do ER: o streamer cria o canal com
--   a conta que tem na plataforma. Funciona como uma FK composta de Canal
--   para PlataformaUsuario.
-- DEC-027
-- Cuidado:
--   * Daria para declarar FOREIGN KEY (nro_plataforma, id_streamer)
--     REFERENCES PlataformaUsuario. O grupo preferiu o trigger para não
--     mudar os relacionamentos do modelo relacional dado (DEC-019): no
--     enunciado, Canal referencia Plataforma e Usuario, e não
--     PlataformaUsuario.
--   * Não vale para Comentario nem Inscricao: conferir a conta a cada
--     comentário custaria uma busca extra na maior tabela.
--   * FOR KEY SHARE na conta: um DELETE concorrente da conta espera.
-- =====================================================================
CREATE OR REPLACE FUNCTION steam_do_bedo.fn_t10_canal_conta()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM 1 FROM steam_do_bedo.plataformausuario
    WHERE nro_plataforma = NEW.nro_plataforma AND id_usuario = NEW.id_streamer
    FOR KEY SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'T10: o streamer % não tem conta na plataforma %', NEW.id_streamer, NEW.nro_plataforma
            USING ERRCODE = 'foreign_key_violation';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_t10_canal_conta
    BEFORE INSERT OR UPDATE OF id_streamer, nro_plataforma ON steam_do_bedo.canal
    FOR EACH ROW EXECUTE FUNCTION steam_do_bedo.fn_t10_canal_conta();

CREATE OR REPLACE FUNCTION steam_do_bedo.fn_t10_conta_remocao()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND NEW.nro_plataforma = OLD.nro_plataforma AND NEW.id_usuario = OLD.id_usuario THEN
        RETURN NEW;
    END IF;
    IF EXISTS (SELECT 1 FROM steam_do_bedo.canal
               WHERE id_streamer = OLD.id_usuario AND nro_plataforma = OLD.nro_plataforma) THEN
        RAISE EXCEPTION 'T10: o usuário % tem canal na plataforma %; a conta não pode ser removida',
                        OLD.id_usuario, OLD.nro_plataforma
            USING ERRCODE = 'foreign_key_violation';
    END IF;
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_t10_conta_remocao
    BEFORE DELETE OR UPDATE OF nro_plataforma, id_usuario ON steam_do_bedo.plataformausuario
    FOR EACH ROW EXECUTE FUNCTION steam_do_bedo.fn_t10_conta_remocao();

-- =====================================================================
-- T11 · Doação gravada em USD
-- O quê: no INSERT, o valor informado está na moeda do país de residência
--   de quem fez o comentário; o trigger multiplica pelo fator de
--   Conversao e grava em USD, com 2 casas.
-- Por quê: patrocínio sempre em USD e doação convertida pelo país de
--   residência do usuário (professor, 12:09-15:14). O grupo escolheu
--   gravar o valor histórico (quanto valia no dia da doação), uma das duas
--   formas que o professor aceitou.
-- DEC-026
-- Cuidado:
--   * O valor em moeda local não fica guardado: não pode criar coluna
--     (DEC-019). Para reconstruí-lo seria preciso o fator do dia, que a
--     tabela Conversao não tem histórico.
--   * Só no INSERT. Um UPDATE de valor é tratado como correção já em USD.
--   * Valor que vira menos de US$ 0,01 é rejeitado, porque a coluna tem 2
--     casas e o CHECK (valor > 0) recusaria o zero de qualquer forma.
--   * O seed grava direto em USD (o trigger não existe na carga).
-- =====================================================================
CREATE OR REPLACE FUNCTION steam_do_bedo.fn_t11_doacao_usd()
RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_fator NUMERIC;
    v_moeda VARCHAR(3);
BEGIN
    SELECT cv.fator_conver, cv.moeda INTO v_fator, v_moeda
    FROM steam_do_bedo.comentario c
    JOIN steam_do_bedo.usuario u    ON u.id_usuario = c.id_usuario
    JOIN steam_do_bedo.pais p       ON p.ddi = u.pais_residencia
    JOIN steam_do_bedo.conversao cv ON cv.moeda = p.moeda
    WHERE c.id_video = NEW.id_video AND c.seq = NEW.seq_comentario;

    IF NOT FOUND THEN
        RETURN NEW;  -- comentário inexistente: a FK rejeita em seguida
    END IF;

    NEW.valor := round(NEW.valor * v_fator, 2);
    IF NEW.valor < 0.01 THEN
        RAISE EXCEPTION 'T11: a doação convertida de % para USD fica abaixo de US$ 0,01', v_moeda
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_t11_doacao_usd
    BEFORE INSERT ON steam_do_bedo.doacao
    FOR EACH ROW EXECUTE FUNCTION steam_do_bedo.fn_t11_doacao_usd();
