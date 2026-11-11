-- =====================================================================
-- Projeto de Banco de Dados 2026/2 - Stream do Bedo
-- Script DDL (PostgreSQL 17)
--
-- Ordem de execução: ddl.sql -> seed.sql -> procedures.sql -> queries.sql
-- O script é reexecutável: o DROP SCHEMA ... CASCADE recria tudo do zero.
--
-- Pontos alterados por decisões de projeto trazem o comentário -- DEC-NNN
-- (ver DECISIONS.md). Constraints novas ou reescritas são nomeadas.
-- =====================================================================

DROP SCHEMA IF EXISTS steam_do_bedo CASCADE;
CREATE SCHEMA steam_do_bedo;

SET search_path TO steam_do_bedo;

CREATE TABLE steam_do_bedo.Empresa (
    nro INTEGER GENERATED ALWAYS AS IDENTITY,                 -- DEC-008: INTEGER
    nome VARCHAR(255) NOT NULL UNIQUE,
    nome_fantasia VARCHAR(255),

    PRIMARY KEY (nro)
);

-- qtd_users é atributo derivado e requer atualização periódica
CREATE TABLE steam_do_bedo.Plataforma (
    nro INTEGER GENERATED ALWAYS AS IDENTITY,                 -- DEC-005: INTEGER
    nome VARCHAR(255) NOT NULL,
    qtd_users BIGINT NOT NULL DEFAULT 0,
    empresa_fund INTEGER NOT NULL,                            -- DEC-008: INTEGER
    empresa_resp INTEGER NOT NULL,                            -- DEC-008: INTEGER
    data_fund DATE,

    PRIMARY KEY (nro),
    -- DEC-006: identidade de negócio = nome + empresa fundadora
    CONSTRAINT plataforma_nome_fund_key UNIQUE (nome, empresa_fund),
    -- DEC-016: contador derivado, pode ser zero
    CONSTRAINT plataforma_qtd_users_check CHECK (qtd_users >= 0),
    FOREIGN KEY (empresa_fund) REFERENCES steam_do_bedo.Empresa(nro),
    FOREIGN KEY (empresa_resp) REFERENCES steam_do_bedo.Empresa(nro)
);

-- fator_conver é o fator de conversão da moeda para dólar (USD)
CREATE TABLE steam_do_bedo.Conversao (
    moeda VARCHAR(3),
    nome VARCHAR(255) NOT NULL,
    fator_conver NUMERIC(18, 8) NOT NULL,

    PRIMARY KEY (moeda),
    -- DEC-010: nome da moeda é único (moeda continua como PK)
    CONSTRAINT conversao_nome_key UNIQUE (nome),
    -- DEC-016: fator zero ou negativo anula ou inverte a conversão
    CONSTRAINT conversao_fator_conver_check CHECK (fator_conver > 0)
);

CREATE TABLE steam_do_bedo.Pais (
    ddi VARCHAR(4),
    nome VARCHAR(255) NOT NULL,
    moeda VARCHAR(3) NOT NULL,

    PRIMARY KEY (ddi),
    FOREIGN KEY (moeda) REFERENCES steam_do_bedo.Conversao(moeda)
);

CREATE TABLE steam_do_bedo.Usuario (
    nick VARCHAR(255),
    email VARCHAR(255) NOT NULL,
    data_nasc DATE NOT NULL,
    telefone VARCHAR(13),
    end_postal VARCHAR(255),
    pais_residencia VARCHAR(4),

    PRIMARY KEY (nick),
    -- DEC-011: email e telefone únicos, cada um sozinho
    CONSTRAINT usuario_email_key UNIQUE (email),
    CONSTRAINT usuario_telefone_key UNIQUE (telefone),
    FOREIGN KEY (pais_residencia) REFERENCES steam_do_bedo.Pais(ddi)
);

CREATE TABLE steam_do_bedo.PlataformaUsuario (
    nro_plataforma INTEGER,                                   -- DEC-005: INTEGER
    nick_usuario VARCHAR(255),
    nro_usuario BIGINT NOT NULL,

    PRIMARY KEY (nro_plataforma, nick_usuario),
    FOREIGN KEY (nro_plataforma) REFERENCES steam_do_bedo.Plataforma(nro),
    FOREIGN KEY (nick_usuario) REFERENCES steam_do_bedo.Usuario(nick)
);

CREATE TABLE steam_do_bedo.StreamerPais (
    nick_streamer VARCHAR(255),
    ddi_pais VARCHAR(4),
    nro_passaporte VARCHAR(20) NOT NULL,

    PRIMARY KEY (nick_streamer, ddi_pais),
    FOREIGN KEY (nick_streamer) REFERENCES steam_do_bedo.Usuario(nick),
    FOREIGN KEY (ddi_pais) REFERENCES steam_do_bedo.Pais(ddi)
);

CREATE TABLE steam_do_bedo.EmpresaPais (
    nro_empresa INTEGER,                                      -- DEC-008: INTEGER
    ddi_pais VARCHAR(4),
    id_nacional VARCHAR(255),

    PRIMARY KEY (nro_empresa, ddi_pais),
    FOREIGN KEY (nro_empresa) REFERENCES steam_do_bedo.Empresa(nro),
    FOREIGN KEY (ddi_pais) REFERENCES steam_do_bedo.Pais(ddi)
);

-- qtd_visualizacoes é atributo derivado e requer atualização
-- DEC-014: PK artificial id_canal; identidade de negócio (nome, nro_plataforma) em UNIQUE
CREATE TABLE steam_do_bedo.Canal (
    id_canal INTEGER GENERATED ALWAYS AS IDENTITY,            -- DEC-014
    nome VARCHAR(255) NOT NULL,                               -- DEC-014: deixa a PK, segue obrigatório
    nro_plataforma INTEGER NOT NULL,                          -- DEC-005: INTEGER; DEC-014: NOT NULL

    tipo VARCHAR(30) NOT NULL,
    data TIMESTAMPTZ DEFAULT now(),
    descricao VARCHAR(700),
    qtd_visualizacoes BIGINT NOT NULL DEFAULT 0,

    nick_streamer VARCHAR(255) NOT NULL,

    CONSTRAINT canal_pkey PRIMARY KEY (id_canal),                               -- DEC-014
    CONSTRAINT canal_nome_plataforma_key UNIQUE (nome, nro_plataforma),         -- DEC-014
    CHECK (tipo IN ('privado', 'publico', 'misto')),
    -- DEC-016: contador derivado, pode ser zero
    CONSTRAINT canal_qtd_visualizacoes_check CHECK (qtd_visualizacoes >= 0),
    CONSTRAINT canal_nick_streamer_fkey FOREIGN KEY (nick_streamer)
        REFERENCES steam_do_bedo.Usuario(nick),
    CONSTRAINT canal_nro_plataforma_fkey FOREIGN KEY (nro_plataforma)
        REFERENCES steam_do_bedo.Plataforma(nro)
);

-- Valor do patrocínio em dólares americanos (USD)
-- DEC-014: referencia Canal por id_canal (sem nome_canal / nro_plataforma)
CREATE TABLE steam_do_bedo.Patrocinio (
    nro_empresa INTEGER,                                      -- DEC-008: INTEGER
    id_canal INTEGER,                                         -- DEC-014
    valor NUMERIC(14, 2) NOT NULL,

    CONSTRAINT patrocinio_pkey PRIMARY KEY (nro_empresa, id_canal),             -- DEC-014
    -- DEC-016: patrocínio vigente tem valor positivo
    CONSTRAINT patrocinio_valor_check CHECK (valor > 0),
    CONSTRAINT patrocinio_nro_empresa_fkey FOREIGN KEY (nro_empresa)
        REFERENCES steam_do_bedo.Empresa(nro),
    CONSTRAINT patrocinio_id_canal_fkey FOREIGN KEY (id_canal)                  -- DEC-014
        REFERENCES steam_do_bedo.Canal(id_canal)
);

-- DEC-014: referencia Canal por id_canal
CREATE TABLE steam_do_bedo.NivelCanal (
    id_canal INTEGER,                                         -- DEC-014
    nivel VARCHAR(100),
    valor NUMERIC(14, 2) NOT NULL,
    gif VARCHAR(255),

    CONSTRAINT nivelcanal_pkey PRIMARY KEY (id_canal, nivel),                   -- DEC-014
    -- DEC-016: nível pago
    CONSTRAINT nivelcanal_valor_check CHECK (valor > 0),
    CONSTRAINT nivelcanal_id_canal_fkey FOREIGN KEY (id_canal)                  -- DEC-014
        REFERENCES steam_do_bedo.Canal(id_canal)
);

-- DEC-014: referencia Canal por id_canal
CREATE TABLE steam_do_bedo.Inscricao (
    id_canal INTEGER,                                         -- DEC-014
    nick_membro VARCHAR(255),
    nivel VARCHAR(100) NOT NULL,
    data_inscricao DATE NOT NULL DEFAULT CURRENT_DATE,        -- DEC-007

    CONSTRAINT inscricao_pkey PRIMARY KEY (id_canal, nick_membro),              -- DEC-014
    CONSTRAINT inscricao_nick_membro_fkey FOREIGN KEY (nick_membro)
        REFERENCES steam_do_bedo.Usuario(nick),
    CONSTRAINT inscricao_nivel_fkey FOREIGN KEY (id_canal, nivel)               -- DEC-014
        REFERENCES steam_do_bedo.NivelCanal(id_canal, nivel)
);

-- DEC-015: PK artificial id_video; identidade de negócio (id_canal, titulo, dataH) em UNIQUE
CREATE TABLE steam_do_bedo.Video (
    id_video BIGINT GENERATED ALWAYS AS IDENTITY,             -- DEC-015
    id_canal INTEGER NOT NULL,                                -- DEC-014 / DEC-015
    titulo VARCHAR(255) NOT NULL,                             -- DEC-015: NOT NULL fora da PK
    dataH TIMESTAMPTZ NOT NULL,                               -- DEC-015: NOT NULL fora da PK

    tema VARCHAR(255),
    duracao INTERVAL,
    visu_simul BIGINT,
    visu_total BIGINT,

    CONSTRAINT video_pkey PRIMARY KEY (id_video),                               -- DEC-015
    CONSTRAINT video_canal_titulo_datah_key UNIQUE (id_canal, titulo, dataH),   -- DEC-015
    -- DEC-016: duração positiva e contadores não negativos (nulos continuam aceitos)
    CONSTRAINT video_duracao_check CHECK (duracao > INTERVAL '0'),
    CONSTRAINT video_visu_simul_check CHECK (visu_simul >= 0),
    CONSTRAINT video_visu_total_check CHECK (visu_total >= 0),
    CONSTRAINT video_id_canal_fkey FOREIGN KEY (id_canal)                       -- DEC-015
        REFERENCES steam_do_bedo.Canal(id_canal)
);

-- DEC-015: referencia Video por id_video
CREATE TABLE steam_do_bedo.Participa (
    id_video BIGINT,                                          -- DEC-015
    nick_streamer VARCHAR(255),

    CONSTRAINT participa_pkey PRIMARY KEY (id_video, nick_streamer),            -- DEC-015
    CONSTRAINT participa_id_video_fkey FOREIGN KEY (id_video)                   -- DEC-015
        REFERENCES steam_do_bedo.Video(id_video),
    CONSTRAINT participa_nick_streamer_fkey FOREIGN KEY (nick_streamer)
        REFERENCES steam_do_bedo.Usuario(nick)
);

-- coment_on: TRUE para comentário online, FALSE para offline
-- DEC-017: PK (id_video, seq); nick_usuario sai da PK e fica NOT NULL com FK.
-- A geração de seq por vídeo ainda não está decidida: o seed informa seq.
CREATE TABLE steam_do_bedo.Comentario (
    id_video BIGINT,                                          -- DEC-015 / DEC-017
    seq INTEGER,                                              -- DEC-017: INTEGER
    nick_usuario VARCHAR(255) NOT NULL,                       -- DEC-017: fora da PK

    texto TEXT,
    dataH TIMESTAMPTZ NOT NULL DEFAULT now(),
    coment_on BOOLEAN NOT NULL,

    CONSTRAINT comentario_pkey PRIMARY KEY (id_video, seq),                     -- DEC-017
    -- DEC-016: número sequencial a partir de 1
    CONSTRAINT comentario_seq_check CHECK (seq > 0),
    CONSTRAINT comentario_id_video_fkey FOREIGN KEY (id_video)                  -- DEC-017
        REFERENCES steam_do_bedo.Video(id_video),
    CONSTRAINT comentario_nick_usuario_fkey FOREIGN KEY (nick_usuario)          -- DEC-017
        REFERENCES steam_do_bedo.Usuario(nick)
);

-- DEC-017: PK (id_video, seq_comentario, seq_pg); nick_usuario não é repetido
-- (é determinado pelo comentário)
CREATE TABLE steam_do_bedo.Doacao (
    id_video BIGINT,                                          -- DEC-017
    seq_comentario INTEGER,                                   -- DEC-017: mesmo tipo de Comentario.seq
    seq_pg BIGINT,

    valor NUMERIC(14, 2) NOT NULL,
    status VARCHAR(10) NOT NULL,

    CONSTRAINT doacao_pkey PRIMARY KEY (id_video, seq_comentario, seq_pg),      -- DEC-017
    CHECK (status IN ('recusado', 'recebido', 'lido')),
    -- DEC-016: valores positivos e números sequenciais a partir de 1
    CONSTRAINT doacao_valor_check CHECK (valor > 0),
    CONSTRAINT doacao_seq_pg_check CHECK (seq_pg > 0),
    CONSTRAINT doacao_seq_comentario_check CHECK (seq_comentario > 0),
    CONSTRAINT doacao_comentario_fkey FOREIGN KEY (id_video, seq_comentario)    -- DEC-017
        REFERENCES steam_do_bedo.Comentario(id_video, seq)
);

-- DEC-017: as 4 especializações de Doacao têm chave (id_video, seq_comentario, seq_doacao)
CREATE TABLE steam_do_bedo.BitCoin (
    id_video BIGINT,                                          -- DEC-017
    seq_comentario INTEGER,                                   -- DEC-017
    seq_doacao BIGINT,

    TxID VARCHAR(64) NOT NULL,

    CONSTRAINT bitcoin_pkey PRIMARY KEY (id_video, seq_comentario, seq_doacao), -- DEC-017
    CONSTRAINT bitcoin_doacao_fkey FOREIGN KEY (id_video, seq_comentario, seq_doacao)  -- DEC-017
        REFERENCES steam_do_bedo.Doacao(id_video, seq_comentario, seq_pg)
);

CREATE TABLE steam_do_bedo.PayPal (
    id_video BIGINT,                                          -- DEC-017
    seq_comentario INTEGER,                                   -- DEC-017
    seq_doacao BIGINT,

    IdPayPal VARCHAR(255) NOT NULL,

    CONSTRAINT paypal_pkey PRIMARY KEY (id_video, seq_comentario, seq_doacao),  -- DEC-017
    CONSTRAINT paypal_doacao_fkey FOREIGN KEY (id_video, seq_comentario, seq_doacao)   -- DEC-017
        REFERENCES steam_do_bedo.Doacao(id_video, seq_comentario, seq_pg)
);

CREATE TABLE steam_do_bedo.CartaoCredito (
    id_video BIGINT,                                          -- DEC-017
    seq_comentario INTEGER,                                   -- DEC-017
    seq_doacao BIGINT,

    nro VARCHAR(19) NOT NULL,
    bandeira VARCHAR(50) NOT NULL,

    CONSTRAINT cartaocredito_pkey PRIMARY KEY (id_video, seq_comentario, seq_doacao),  -- DEC-017
    CONSTRAINT cartaocredito_doacao_fkey FOREIGN KEY (id_video, seq_comentario, seq_doacao)  -- DEC-017
        REFERENCES steam_do_bedo.Doacao(id_video, seq_comentario, seq_pg)
);

CREATE TABLE steam_do_bedo.MecanismoPlat (
    id_video BIGINT,                                          -- DEC-017
    seq_comentario INTEGER,                                   -- DEC-017
    seq_doacao BIGINT,

    seq_plataforma BIGINT NOT NULL,

    CONSTRAINT mecanismoplat_pkey PRIMARY KEY (id_video, seq_comentario, seq_doacao),  -- DEC-017
    -- DEC-016: número sequencial a partir de 1
    CONSTRAINT mecanismoplat_seq_plataforma_check CHECK (seq_plataforma > 0),
    CONSTRAINT mecanismoplat_doacao_fkey FOREIGN KEY (id_video, seq_comentario, seq_doacao)  -- DEC-017
        REFERENCES steam_do_bedo.Doacao(id_video, seq_comentario, seq_pg)
);
