-- =====================================================================
-- Projeto de Banco de Dados 2026/2 - Stream do Bedo
-- Arquivo 1/7: DDL (PostgreSQL 17)
--
-- O que faz: cria o schema steam_do_bedo com as 20 tabelas do modelo
-- relacional do enunciado, com as chaves remodeladas e as constraints
-- decididas pelo grupo. Também cria a function uuid_v7(), usada como
-- DEFAULT da chave de Video.
--
-- Ordem de execução (DEC-030). Cada arquivo depende dos anteriores:
--   1. ddl.sql            <- este arquivo (recria o schema do zero)
--   2. seed_v3.sql        carga; obedece às regras dos triggers sozinho
--   3. views.sql          views virtuais e materializadas (V1 a V4)
--   4. procedures.sql     functions das 12 consultas
--   5. triggers.sql       triggers T1 a T11 (depois da carga, para não
--                         pesar nem travar a inserção em lote)
--   6. indices.sql        até 5 índices de apoio (depois da carga)
--   7. queries.sql        chamadas das functions
--   (testes_triggers.sql roda depois do 5 e desfaz tudo com ROLLBACK)
--
-- Regra de alteração do modelo (DEC-019, fala do professor em 00:15):
-- o modelo relacional do enunciado não muda de relações. Pode: remodelar
-- chaves (inclusive com surrogate), mudar tipos e criar constraints.
-- Não pode: criar ou remover tabelas, criar colunas que não sejam de
-- chave, remover atributos derivados (qtd_users, qtd_visualizacoes).
-- Toda coluna que não está no enunciado é uma chave artificial:
-- Usuario.id_usuario, Canal.id_canal e Video.id_video, e as colunas que
-- as referenciam (id_streamer, id_membro, id_usuario).
--
-- DECs implementadas aqui: 005, 006, 008, 010, 011, 014, 015, 016, 017
-- (com as revisões das DEC-019 a 025).
--
-- Cuidado: o DROP SCHEMA ... CASCADE apaga tudo o que existe no schema
-- steam_do_bedo, inclusive dados, views, functions e triggers. Rode só
-- num banco que pode ser recriado.
-- =====================================================================

\set ON_ERROR_STOP on

DROP SCHEMA IF EXISTS steam_do_bedo CASCADE;
CREATE SCHEMA steam_do_bedo;

SET search_path TO steam_do_bedo;

-- ---------------------------------------------------------------------
-- uuid_v7(p_ts): gera um UUID versão 7 (RFC 9562).
-- O quê: os 48 primeiros bits são o instante em milissegundos desde
--   1970 (p_ts, por padrão o relógio atual); o resto vem de
--   gen_random_uuid() (v4), com os bits de versão trocados de 4 para 7.
-- Por quê: a chave de Video é UUID v7 (DEC-021). O cenário inclui vídeo
--   curto replicado em várias plataformas (DEC-020), o que leva a
--   geração distribuída do identificador. O v7 é ordenado no tempo e
--   insere perto do fim do B-tree, ao contrário do v4.
-- DEC-021
-- Cuidado: o PostgreSQL 17 não tem uuidv7() nativo (só a partir do 18).
--   set_bit numera os bits do bytea do menos para o mais significativo
--   de cada byte: os bits 52 e 53 são os bits 4 e 5 do byte 6, que
--   transformam o nibble de versão 0100 (v4) em 0111 (v7). Os bits de
--   variante (10) já vêm certos do v4. Dentro do mesmo milissegundo a
--   ordem é aleatória (não há contador), o que é aceito: a localidade
--   no índice continua sendo por milissegundo.
-- ---------------------------------------------------------------------
CREATE FUNCTION steam_do_bedo.uuid_v7(p_ts TIMESTAMPTZ DEFAULT clock_timestamp())
RETURNS UUID
LANGUAGE sql VOLATILE PARALLEL SAFE AS $$
    SELECT encode(
             set_bit(set_bit(
               overlay(uuid_send(gen_random_uuid())
                       PLACING substring(int8send(floor(extract(epoch FROM p_ts) * 1000)::BIGINT) FROM 3)
                       FROM 1 FOR 6),
               52, 1), 53, 1),
             'hex')::UUID;
$$;

COMMENT ON FUNCTION steam_do_bedo.uuid_v7(TIMESTAMPTZ) IS
    'UUID v7 (RFC 9562): 48 bits de timestamp em ms + 74 bits aleatórios. DEC-021';

-- ---------------------------------------------------------------------
-- Empresa
-- O quê: fundadoras, responsáveis e patrocinadoras.
-- DEC-008: nro INTEGER (centenas de milhões de empresas, no máximo).
-- DEC-009: nome único; não há UNIQUE (nome, nome_fantasia).
-- ---------------------------------------------------------------------
CREATE TABLE steam_do_bedo.Empresa (
    nro INTEGER GENERATED ALWAYS AS IDENTITY,                 -- DEC-008: INTEGER
    nome VARCHAR(255) NOT NULL,
    nome_fantasia VARCHAR(255),

    CONSTRAINT empresa_pkey PRIMARY KEY (nro),
    CONSTRAINT empresa_nome_key UNIQUE (nome)                 -- DEC-009
);

-- ---------------------------------------------------------------------
-- Plataforma
-- O quê: plataformas de streaming (vídeo longo e curto, DEC-020).
-- qtd_users é atributo derivado: número de contas em PlataformaUsuario
--   na plataforma. Mantido pelo trigger T2 (triggers.sql) e calculado
--   pelo próprio seed na carga (DEC-027).
-- DEC-005: nro INTEGER (dezenas de plataformas no mundo real).
-- DEC-006: identidade de negócio = nome + empresa fundadora.
-- DEC-025: data_fund NOT NULL (o minimundo dá "uma data de fundação" a
--   toda plataforma, e o T7 compara a data do canal com ela).
-- ---------------------------------------------------------------------
CREATE TABLE steam_do_bedo.Plataforma (
    nro INTEGER GENERATED ALWAYS AS IDENTITY,                 -- DEC-005: INTEGER
    nome VARCHAR(255) NOT NULL,
    qtd_users BIGINT NOT NULL DEFAULT 0,
    empresa_fund INTEGER NOT NULL,                            -- DEC-008: INTEGER
    empresa_resp INTEGER NOT NULL,                            -- DEC-008: INTEGER
    data_fund DATE NOT NULL,                                  -- DEC-025: NOT NULL

    CONSTRAINT plataforma_pkey PRIMARY KEY (nro),
    CONSTRAINT plataforma_nome_fund_key UNIQUE (nome, empresa_fund),           -- DEC-006
    CONSTRAINT plataforma_qtd_users_check CHECK (qtd_users >= 0),               -- DEC-016
    CONSTRAINT plataforma_empresa_fund_fkey FOREIGN KEY (empresa_fund)
        REFERENCES steam_do_bedo.Empresa(nro),
    CONSTRAINT plataforma_empresa_resp_fkey FOREIGN KEY (empresa_resp)
        REFERENCES steam_do_bedo.Empresa(nro)
);

-- ---------------------------------------------------------------------
-- Conversao
-- O quê: uma linha por moeda (código ISO 4217) com o fator moeda -> USD.
-- DEC-010: moeda é a PK (código curto e estável); nome é único.
-- DEC-016: fator positivo.
-- ---------------------------------------------------------------------
CREATE TABLE steam_do_bedo.Conversao (
    moeda VARCHAR(3),
    nome VARCHAR(255) NOT NULL,
    fator_conver NUMERIC(18, 8) NOT NULL,

    CONSTRAINT conversao_pkey PRIMARY KEY (moeda),
    CONSTRAINT conversao_nome_key UNIQUE (nome),                                -- DEC-010
    CONSTRAINT conversao_fator_conver_check CHECK (fator_conver > 0)            -- DEC-016
);

-- ---------------------------------------------------------------------
-- Pais
-- O quê: país identificado pelo DDI, com a moeda corrente.
-- Cuidado: o DDI do mundo real não é único (EUA e Canadá usam +1, Rússia
--   e Cazaquistão usam +7). O enunciado manda identificar o país pelo DDI,
--   então o seed usa o prefixo mais longo que distingue o país (por
--   exemplo 1876 para a Jamaica e 77 para o Cazaquistão). Ver DEC-031.
-- ---------------------------------------------------------------------
CREATE TABLE steam_do_bedo.Pais (
    ddi VARCHAR(4),
    nome VARCHAR(255) NOT NULL,
    moeda VARCHAR(3) NOT NULL,

    CONSTRAINT pais_pkey PRIMARY KEY (ddi),
    CONSTRAINT pais_nome_key UNIQUE (nome),                                     -- DEC-025
    CONSTRAINT pais_moeda_fkey FOREIGN KEY (moeda)
        REFERENCES steam_do_bedo.Conversao(moeda)
);

-- ---------------------------------------------------------------------
-- Usuario
-- O quê: todo usuário; streamers são os usuários com passaporte em
--   StreamerPais (T9) e membros são os que têm Inscricao.
-- DEC-022: PK artificial id_usuario BIGINT; o nick continua único e
--   obrigatório (UNIQUE NOT NULL). Motivos: o nick pode mudar (as
--   plataformas permitem renomear) e era propagado para 6 tabelas,
--   inclusive Comentario; join por inteiro é mais barato que por texto
--   com collation; BIGINT porque a internet já tem 6 bilhões de pessoas,
--   acima dos 2,1 bilhões do INTEGER.
-- DEC-011: email e telefone únicos, cada um sozinho (telefone nulável).
-- DEC-025: pais_residencia NOT NULL. O minimundo dá "um país de
--   residência" a todo usuário, e a conversão da doação (T11, DEC-026)
--   depende dele. Substitui a premissa 2 da DEC-001 (usuário sem país
--   tratado como USD).
-- ---------------------------------------------------------------------
CREATE TABLE steam_do_bedo.Usuario (
    id_usuario BIGINT GENERATED ALWAYS AS IDENTITY,           -- DEC-022
    nick VARCHAR(255) NOT NULL,                               -- DEC-022: sai da PK, segue obrigatório
    email VARCHAR(255) NOT NULL,
    data_nasc DATE NOT NULL,
    telefone VARCHAR(13),
    end_postal VARCHAR(255),
    pais_residencia VARCHAR(4) NOT NULL,                      -- DEC-025

    CONSTRAINT usuario_pkey PRIMARY KEY (id_usuario),                           -- DEC-022
    CONSTRAINT usuario_nick_key UNIQUE (nick),                                  -- DEC-022
    CONSTRAINT usuario_email_key UNIQUE (email),                                -- DEC-011
    CONSTRAINT usuario_telefone_key UNIQUE (telefone),                          -- DEC-011
    CONSTRAINT usuario_pais_residencia_fkey FOREIGN KEY (pais_residencia)
        REFERENCES steam_do_bedo.Pais(ddi)
);

-- ---------------------------------------------------------------------
-- PlataformaUsuario ("tem conta" no ER)
-- O quê: conta de um usuário numa plataforma, com o número de usuário
--   daquela plataforma.
-- DEC-022: referencia Usuario por id_usuario.
-- DEC-025: UNIQUE (nro_plataforma, nro_usuario). O número de usuário
--   "pode ser diferente em cada plataforma", mas dentro de uma
--   plataforma identifica a conta: duas contas com o mesmo número na
--   mesma plataforma seriam o mesmo fato duplicado.
-- Cuidado: o UNIQUE custa um índice numa tabela de ~10^6 linhas no seed;
--   aceito porque é regra de negócio e a tabela tem escrita rara.
-- ---------------------------------------------------------------------
CREATE TABLE steam_do_bedo.PlataformaUsuario (
    nro_plataforma INTEGER,                                   -- DEC-005: INTEGER
    id_usuario BIGINT,                                        -- DEC-022
    nro_usuario BIGINT NOT NULL,

    CONSTRAINT plataformausuario_pkey PRIMARY KEY (nro_plataforma, id_usuario), -- DEC-022
    CONSTRAINT plataformausuario_nro_usuario_key UNIQUE (nro_plataforma, nro_usuario), -- DEC-025
    CONSTRAINT plataformausuario_nro_plataforma_fkey FOREIGN KEY (nro_plataforma)
        REFERENCES steam_do_bedo.Plataforma(nro),
    CONSTRAINT plataformausuario_id_usuario_fkey FOREIGN KEY (id_usuario)       -- DEC-022
        REFERENCES steam_do_bedo.Usuario(id_usuario)
);

-- ---------------------------------------------------------------------
-- StreamerPais ("tem nacionalidade" no ER)
-- O quê: passaporte de um streamer em um país. Ter ao menos uma linha
--   aqui é o que caracteriza o usuário como streamer (T9, DEC-027).
-- DEC-022: referencia Usuario por id_usuario (coluna id_streamer).
-- DEC-025: UNIQUE (ddi_pais, nro_passaporte): o número do passaporte é
--   único dentro do país emissor.
-- ---------------------------------------------------------------------
CREATE TABLE steam_do_bedo.StreamerPais (
    id_streamer BIGINT,                                       -- DEC-022
    ddi_pais VARCHAR(4),
    nro_passaporte VARCHAR(20) NOT NULL,

    CONSTRAINT streamerpais_pkey PRIMARY KEY (id_streamer, ddi_pais),           -- DEC-022
    CONSTRAINT streamerpais_passaporte_key UNIQUE (ddi_pais, nro_passaporte),   -- DEC-025
    CONSTRAINT streamerpais_id_streamer_fkey FOREIGN KEY (id_streamer)          -- DEC-022
        REFERENCES steam_do_bedo.Usuario(id_usuario),
    CONSTRAINT streamerpais_ddi_pais_fkey FOREIGN KEY (ddi_pais)
        REFERENCES steam_do_bedo.Pais(ddi)
);

-- ---------------------------------------------------------------------
-- EmpresaPais ("tem sede" no ER)
-- O quê: identificador nacional (CNPJ, EIN...) da empresa em cada país.
-- DEC-025: id_nacional NOT NULL e UNIQUE (ddi_pais, id_nacional). É a
--   identidade real da empresa (DEC-009) e não se repete no país.
-- ---------------------------------------------------------------------
CREATE TABLE steam_do_bedo.EmpresaPais (
    nro_empresa INTEGER,                                      -- DEC-008: INTEGER
    ddi_pais VARCHAR(4),
    id_nacional VARCHAR(255) NOT NULL,                        -- DEC-025

    CONSTRAINT empresapais_pkey PRIMARY KEY (nro_empresa, ddi_pais),
    CONSTRAINT empresapais_id_nacional_key UNIQUE (ddi_pais, id_nacional),      -- DEC-025
    CONSTRAINT empresapais_nro_empresa_fkey FOREIGN KEY (nro_empresa)
        REFERENCES steam_do_bedo.Empresa(nro),
    CONSTRAINT empresapais_ddi_pais_fkey FOREIGN KEY (ddi_pais)
        REFERENCES steam_do_bedo.Pais(ddi)
);

-- ---------------------------------------------------------------------
-- Canal
-- O quê: canal de um streamer numa plataforma.
-- qtd_visualizacoes é atributo derivado: soma bruta de Video.visu_total
--   dos vídeos do canal (professor, 16:20-17:38). Mantido pelo trigger
--   T1 e calculado pelo seed na carga.
-- DEC-014: PK artificial id_canal; identidade de negócio (nome,
--   nro_plataforma) em UNIQUE.
-- DEC-023: id_canal passa de INTEGER para BIGINT. Com vídeo curto no
--   cenário (DEC-020), todo criador de shorts tem canal, e a soma de
--   canais em dezenas de plataformas pode passar de 2,1 bilhões.
-- DEC-022: o dono é referenciado por id_streamer (id_usuario).
-- DEC-025: data NOT NULL (o T7 compara datas) e CHECK do tipo nomeado.
-- ---------------------------------------------------------------------
CREATE TABLE steam_do_bedo.Canal (
    id_canal BIGINT GENERATED ALWAYS AS IDENTITY,             -- DEC-014 / DEC-023: BIGINT
    nome VARCHAR(255) NOT NULL,                               -- DEC-014
    nro_plataforma INTEGER NOT NULL,                          -- DEC-005 / DEC-014

    tipo VARCHAR(30) NOT NULL,
    data TIMESTAMPTZ NOT NULL DEFAULT now(),                  -- DEC-025: NOT NULL
    descricao VARCHAR(700),
    qtd_visualizacoes BIGINT NOT NULL DEFAULT 0,

    id_streamer BIGINT NOT NULL,                              -- DEC-022

    CONSTRAINT canal_pkey PRIMARY KEY (id_canal),                               -- DEC-014
    CONSTRAINT canal_nome_plataforma_key UNIQUE (nome, nro_plataforma),         -- DEC-014
    CONSTRAINT canal_tipo_check CHECK (tipo IN ('privado', 'publico', 'misto')),-- DEC-025: nomeado
    CONSTRAINT canal_qtd_visualizacoes_check CHECK (qtd_visualizacoes >= 0),    -- DEC-016
    CONSTRAINT canal_id_streamer_fkey FOREIGN KEY (id_streamer)                 -- DEC-022
        REFERENCES steam_do_bedo.Usuario(id_usuario),
    CONSTRAINT canal_nro_plataforma_fkey FOREIGN KEY (nro_plataforma)
        REFERENCES steam_do_bedo.Plataforma(nro)
);

-- ---------------------------------------------------------------------
-- Patrocinio
-- O quê: patrocínio vigente de uma empresa a um canal. O minimundo diz
--   que não há histórico: patrocínio encerrado é apagado (DELETE).
-- DEC-026: valor sempre em USD (contrato externo; professor, 13:26).
-- ---------------------------------------------------------------------
CREATE TABLE steam_do_bedo.Patrocinio (
    nro_empresa INTEGER,                                      -- DEC-008: INTEGER
    id_canal BIGINT,                                          -- DEC-014 / DEC-023
    valor NUMERIC(14, 2) NOT NULL,                            -- DEC-026: USD

    CONSTRAINT patrocinio_pkey PRIMARY KEY (nro_empresa, id_canal),             -- DEC-014
    CONSTRAINT patrocinio_valor_check CHECK (valor > 0),                        -- DEC-016
    CONSTRAINT patrocinio_nro_empresa_fkey FOREIGN KEY (nro_empresa)
        REFERENCES steam_do_bedo.Empresa(nro),
    CONSTRAINT patrocinio_id_canal_fkey FOREIGN KEY (id_canal)                  -- DEC-014
        REFERENCES steam_do_bedo.Canal(id_canal)
);

-- ---------------------------------------------------------------------
-- NivelCanal
-- O quê: os níveis de membro de um canal (nome, valor mensal, gif).
--   "Existem cinco níveis": o limite de 5 por canal é do trigger T8.
-- DEC-001: valor na moeda do país de residência do membro, convertido
--   para USD na consulta (view V2).
-- DEC-025: gif NOT NULL ("para cada nível existe um arquivo .gif").
-- ---------------------------------------------------------------------
CREATE TABLE steam_do_bedo.NivelCanal (
    id_canal BIGINT,                                          -- DEC-014 / DEC-023
    nivel VARCHAR(100),
    valor NUMERIC(14, 2) NOT NULL,
    gif VARCHAR(255) NOT NULL,                                -- DEC-025

    CONSTRAINT nivelcanal_pkey PRIMARY KEY (id_canal, nivel),                   -- DEC-014
    CONSTRAINT nivelcanal_valor_check CHECK (valor > 0),                        -- DEC-016
    CONSTRAINT nivelcanal_id_canal_fkey FOREIGN KEY (id_canal)                  -- DEC-014
        REFERENCES steam_do_bedo.Canal(id_canal)
);

-- ---------------------------------------------------------------------
-- Inscricao ("se inscreve" no ER)
-- O quê: membro vigente de um canal, num nível. Sem histórico (DELETE
--   quando a inscrição acaba).
-- DEC-019: a coluna data_inscricao (DEC-007) foi removida. Era coluna
--   comum fora de chave, o que a regra do professor não permite, e o
--   minimundo já diz que só os membros vigentes ficam no sistema.
-- DEC-022: o membro é referenciado por id_membro (id_usuario).
-- ---------------------------------------------------------------------
CREATE TABLE steam_do_bedo.Inscricao (
    id_canal BIGINT,                                          -- DEC-014 / DEC-023
    id_membro BIGINT,                                         -- DEC-022
    nivel VARCHAR(100) NOT NULL,

    CONSTRAINT inscricao_pkey PRIMARY KEY (id_canal, id_membro),                -- DEC-014 / DEC-022
    CONSTRAINT inscricao_id_membro_fkey FOREIGN KEY (id_membro)                 -- DEC-022
        REFERENCES steam_do_bedo.Usuario(id_usuario),
    CONSTRAINT inscricao_nivel_fkey FOREIGN KEY (id_canal, nivel)               -- DEC-014
        REFERENCES steam_do_bedo.NivelCanal(id_canal, nivel)
);

-- ---------------------------------------------------------------------
-- Video
-- O quê: vídeo (live, VOD ou short) postado num canal.
-- DEC-015: PK artificial; identidade de negócio (id_canal, titulo, dataH)
--   em UNIQUE, com titulo e dataH NOT NULL.
-- DEC-021: id_video UUID v7 (antes BIGINT identity). O cenário com vídeo
--   curto (DEC-020) leva à geração distribuída do id (cada coletor ou
--   partição gera sem consultar uma sequence central). Custo medido:
--   +37% de espaço em Video e +28% no índice da PK de Comentario.
-- DEC-016 / DEC-025: duração positiva, contadores não negativos e o pico
--   simultâneo não maior que o total (aplicado agora).
-- Cuidado: o UNIQUE (id_canal, ...) também atende "vídeos de um canal",
--   por ter id_canal como coluna líder (DEC-015, DEC-018).
-- ---------------------------------------------------------------------
CREATE TABLE steam_do_bedo.Video (
    id_video UUID NOT NULL DEFAULT steam_do_bedo.uuid_v7(),   -- DEC-021
    id_canal BIGINT NOT NULL,                                 -- DEC-014 / DEC-023
    titulo VARCHAR(255) NOT NULL,                             -- DEC-015
    dataH TIMESTAMPTZ NOT NULL,                               -- DEC-015

    tema VARCHAR(255),
    duracao INTERVAL,
    visu_simul BIGINT,
    visu_total BIGINT,

    CONSTRAINT video_pkey PRIMARY KEY (id_video),                               -- DEC-015 / DEC-021
    CONSTRAINT video_canal_titulo_datah_key UNIQUE (id_canal, titulo, dataH),   -- DEC-015
    CONSTRAINT video_duracao_check CHECK (duracao > INTERVAL '0'),              -- DEC-016
    CONSTRAINT video_visu_simul_check CHECK (visu_simul >= 0),                  -- DEC-016
    CONSTRAINT video_visu_total_check CHECK (visu_total >= 0),                  -- DEC-016
    CONSTRAINT video_visu_simul_total_check CHECK (visu_simul <= visu_total),   -- DEC-025
    CONSTRAINT video_id_canal_fkey FOREIGN KEY (id_canal)                       -- DEC-015
        REFERENCES steam_do_bedo.Canal(id_canal)
);

-- ---------------------------------------------------------------------
-- Participa
-- O quê: streamers convidados que participam de um vídeo além do dono.
--   Só streamers (usuários com passaporte) participam: trigger T9.
-- ---------------------------------------------------------------------
CREATE TABLE steam_do_bedo.Participa (
    id_video UUID,                                            -- DEC-021
    id_streamer BIGINT,                                       -- DEC-022

    CONSTRAINT participa_pkey PRIMARY KEY (id_video, id_streamer),              -- DEC-015 / DEC-022
    CONSTRAINT participa_id_video_fkey FOREIGN KEY (id_video)                   -- DEC-015
        REFERENCES steam_do_bedo.Video(id_video),
    CONSTRAINT participa_id_streamer_fkey FOREIGN KEY (id_streamer)             -- DEC-022
        REFERENCES steam_do_bedo.Usuario(id_usuario)
);

-- ---------------------------------------------------------------------
-- Comentario
-- O quê: comentário online (feito durante a live) ou offline.
-- DEC-017: PK (id_video, seq); o usuário sai da PK e fica NOT NULL com FK.
-- DEC-024: seq INTEGER (o cenário prevê no máximo ~10^7 comentários num
--   vídeo, abaixo de 2,1 × 10^9). Se o INSERT não informar seq, o trigger
--   T3 gera max(seq) + 1 do vídeo.
-- Cuidado: seq é NOT NULL por ser PK, mas o NOT NULL só é verificado
--   depois dos triggers BEFORE, então um INSERT sem seq funciona quando
--   o T3 existe. Sem o triggers.sql, seq é obrigatório (caso do seed).
-- ---------------------------------------------------------------------
CREATE TABLE steam_do_bedo.Comentario (
    id_video UUID,                                            -- DEC-021
    seq INTEGER,                                              -- DEC-024
    id_usuario BIGINT NOT NULL,                               -- DEC-017 / DEC-022

    texto TEXT,
    dataH TIMESTAMPTZ NOT NULL DEFAULT now(),
    coment_on BOOLEAN NOT NULL,

    CONSTRAINT comentario_pkey PRIMARY KEY (id_video, seq),                     -- DEC-017
    CONSTRAINT comentario_seq_check CHECK (seq > 0),                            -- DEC-016
    CONSTRAINT comentario_id_video_fkey FOREIGN KEY (id_video)                  -- DEC-017
        REFERENCES steam_do_bedo.Video(id_video),
    CONSTRAINT comentario_id_usuario_fkey FOREIGN KEY (id_usuario)              -- DEC-022
        REFERENCES steam_do_bedo.Usuario(id_usuario)
);

-- ---------------------------------------------------------------------
-- Doacao
-- O quê: doação trazida por um comentário.
-- DEC-017: PK (id_video, seq_comentario, seq_pg); o usuário não é
--   repetido (é determinado pelo comentário).
-- DEC-024: seq_pg passa de BIGINT a INTEGER (poucas doações por
--   comentário). Com uuid (16) + 2 INTEGER a chave fecha em 24 bytes sem
--   preenchimento de alinhamento. Gerado pelo trigger T4 se vier nulo.
-- DEC-026: valor gravado em USD. O INSERT informa o valor na moeda do
--   país de residência de quem comentou e o trigger T11 converte. O seed
--   já grava em USD (os triggers não existem na carga).
-- ---------------------------------------------------------------------
CREATE TABLE steam_do_bedo.Doacao (
    id_video UUID,                                            -- DEC-021
    seq_comentario INTEGER,                                   -- DEC-017 / DEC-024
    seq_pg INTEGER,                                           -- DEC-024

    valor NUMERIC(14, 2) NOT NULL,                            -- DEC-026: USD
    status VARCHAR(10) NOT NULL,

    CONSTRAINT doacao_pkey PRIMARY KEY (id_video, seq_comentario, seq_pg),      -- DEC-017
    CONSTRAINT doacao_status_check CHECK (status IN ('recusado', 'recebido', 'lido')), -- DEC-025: nomeado
    CONSTRAINT doacao_valor_check CHECK (valor > 0),                            -- DEC-016
    CONSTRAINT doacao_seq_pg_check CHECK (seq_pg > 0),                          -- DEC-016
    CONSTRAINT doacao_seq_comentario_check CHECK (seq_comentario > 0),          -- DEC-016
    CONSTRAINT doacao_comentario_fkey FOREIGN KEY (id_video, seq_comentario)    -- DEC-017
        REFERENCES steam_do_bedo.Comentario(id_video, seq)
);

-- ---------------------------------------------------------------------
-- Especializações de Doacao (disjuntas e totais: triggers T6)
-- DEC-017: chave (id_video, seq_comentario, seq_doacao), FK para Doacao.
-- DEC-024: seq_doacao INTEGER, igual a Doacao.seq_pg.
-- ---------------------------------------------------------------------

-- DEC-025: TxID é o hash da transação na blockchain; não se repete.
-- Custo: um índice em BitCoin, a menor das especializações no seed.
CREATE TABLE steam_do_bedo.BitCoin (
    id_video UUID,                                            -- DEC-021
    seq_comentario INTEGER,                                   -- DEC-017
    seq_doacao INTEGER,                                       -- DEC-024

    TxID VARCHAR(64) NOT NULL,

    CONSTRAINT bitcoin_pkey PRIMARY KEY (id_video, seq_comentario, seq_doacao), -- DEC-017
    CONSTRAINT bitcoin_txid_key UNIQUE (TxID),                                  -- DEC-025
    CONSTRAINT bitcoin_doacao_fkey FOREIGN KEY (id_video, seq_comentario, seq_doacao)  -- DEC-017
        REFERENCES steam_do_bedo.Doacao(id_video, seq_comentario, seq_pg)
);

-- DEC-025: IdPayPal identifica um pagamento; não se repete.
CREATE TABLE steam_do_bedo.PayPal (
    id_video UUID,                                            -- DEC-021
    seq_comentario INTEGER,                                   -- DEC-017
    seq_doacao INTEGER,                                       -- DEC-024

    IdPayPal VARCHAR(255) NOT NULL,

    CONSTRAINT paypal_pkey PRIMARY KEY (id_video, seq_comentario, seq_doacao),  -- DEC-017
    CONSTRAINT paypal_idpaypal_key UNIQUE (IdPayPal),                           -- DEC-025
    CONSTRAINT paypal_doacao_fkey FOREIGN KEY (id_video, seq_comentario, seq_doacao)   -- DEC-017
        REFERENCES steam_do_bedo.Doacao(id_video, seq_comentario, seq_pg)
);

-- Cuidado: o minimundo pede também a data e hora do pagamento com cartão,
-- mas o modelo relacional do enunciado não tem essa coluna e a regra do
-- professor não permite criá-la (DEC-019). A data/hora é a do comentário.
-- O número do cartão é fictício no seed; em produção seria guardado
-- mascarado ou tokenizado (PCI DSS), o que está fora do escopo.
CREATE TABLE steam_do_bedo.CartaoCredito (
    id_video UUID,                                            -- DEC-021
    seq_comentario INTEGER,                                   -- DEC-017
    seq_doacao INTEGER,                                       -- DEC-024

    nro VARCHAR(19) NOT NULL,
    bandeira VARCHAR(50) NOT NULL,

    CONSTRAINT cartaocredito_pkey PRIMARY KEY (id_video, seq_comentario, seq_doacao),  -- DEC-017
    CONSTRAINT cartaocredito_doacao_fkey FOREIGN KEY (id_video, seq_comentario, seq_doacao)  -- DEC-017
        REFERENCES steam_do_bedo.Doacao(id_video, seq_comentario, seq_pg)
);

-- seq_plataforma: "número sequencial que depende do usuário, do comentário
-- e da plataforma". Gerado pelo trigger T5 como sequência por (usuário,
-- plataforma) quando vier nulo (DEC-027). INTEGER (DEC-024).
CREATE TABLE steam_do_bedo.MecanismoPlat (
    id_video UUID,                                            -- DEC-021
    seq_comentario INTEGER,                                   -- DEC-017
    seq_doacao INTEGER,                                       -- DEC-024

    seq_plataforma INTEGER NOT NULL,                          -- DEC-024

    CONSTRAINT mecanismoplat_pkey PRIMARY KEY (id_video, seq_comentario, seq_doacao),  -- DEC-017
    CONSTRAINT mecanismoplat_seq_plataforma_check CHECK (seq_plataforma > 0),   -- DEC-016
    CONSTRAINT mecanismoplat_doacao_fkey FOREIGN KEY (id_video, seq_comentario, seq_doacao)  -- DEC-017
        REFERENCES steam_do_bedo.Doacao(id_video, seq_comentario, seq_pg)
);

-- ---------------------------------------------------------------------
-- Índices de apoio: ficam em indices.sql, executado depois da carga
-- (DEC-030 e DEC-034, que substitui a DEC-018). Aqui só existem os
-- índices criados automaticamente pelas PRIMARY KEY e UNIQUE.
-- ---------------------------------------------------------------------
