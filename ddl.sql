\set ON_ERROR_STOP on

DROP SCHEMA IF EXISTS steam_do_bedo CASCADE;
CREATE SCHEMA steam_do_bedo;

SET search_path TO steam_do_bedo;

-- ---------------------------------------------------------------------
-- Empresa
-- O quê: fundadoras, responsáveis e patrocinadoras.
-- nro INTEGER (centenas de milhões de empresas, no máximo).
-- Nome único; não há UNIQUE (nome, nome_fantasia).
-- ---------------------------------------------------------------------
CREATE TABLE steam_do_bedo.Empresa (
    nro INTEGER GENERATED ALWAYS AS IDENTITY,
    nome VARCHAR(255) NOT NULL,
    nome_fantasia VARCHAR(255),

    CONSTRAINT empresa_pkey PRIMARY KEY (nro),
    CONSTRAINT empresa_nome_key UNIQUE (nome)
);

-- ---------------------------------------------------------------------
-- Plataforma
-- O quê: plataformas de streaming (vídeo longo e curto).
-- qtd_users é atributo derivado: número de contas em PlataformaUsuario
--   na plataforma. Mantido pelo trigger T2 (triggers.sql) e calculado
--   pelo próprio seed na carga.
-- nro INTEGER (dezenas de plataformas no mundo real).
-- Identidade de negócio = nome + empresa fundadora.
-- data_fund NOT NULL (o minimundo dá "uma data de fundação" a
--   toda plataforma, e o T7 compara a data do canal com ela).
-- ---------------------------------------------------------------------
CREATE TABLE steam_do_bedo.Plataforma (
    nro INTEGER GENERATED ALWAYS AS IDENTITY,
    nome VARCHAR(255) NOT NULL,
    qtd_users BIGINT NOT NULL DEFAULT 0,
    empresa_fund INTEGER NOT NULL,
    empresa_resp INTEGER NOT NULL,
    data_fund DATE NOT NULL,

    CONSTRAINT plataforma_pkey PRIMARY KEY (nro),
    CONSTRAINT plataforma_nome_fund_key UNIQUE (nome, empresa_fund),
    CONSTRAINT plataforma_qtd_users_check CHECK (qtd_users >= 0),
    CONSTRAINT plataforma_empresa_fund_fkey FOREIGN KEY (empresa_fund)
        REFERENCES steam_do_bedo.Empresa(nro),
    CONSTRAINT plataforma_empresa_resp_fkey FOREIGN KEY (empresa_resp)
        REFERENCES steam_do_bedo.Empresa(nro)
);

-- ---------------------------------------------------------------------
-- Conversao
-- O quê: uma linha por moeda (código ISO 4217) com o fator moeda -> USD.
-- Moeda é a PK (código curto e estável); nome é único.
-- Fator positivo.
-- ---------------------------------------------------------------------
CREATE TABLE steam_do_bedo.Conversao (
    moeda VARCHAR(3),
    nome VARCHAR(255) NOT NULL,
    fator_conver NUMERIC(18, 8) NOT NULL,

    CONSTRAINT conversao_pkey PRIMARY KEY (moeda),
    CONSTRAINT conversao_nome_key UNIQUE (nome),
    CONSTRAINT conversao_fator_conver_check CHECK (fator_conver > 0)
);

-- ---------------------------------------------------------------------
-- Pais
-- O quê: país identificado pelo DDI, com a moeda corrente.
-- Cuidado: o DDI do mundo real não é único (EUA e Canadá usam +1, Rússia
--   e Cazaquistão usam +7). O enunciado manda identificar o país pelo DDI,
--   então o seed usa o prefixo mais longo que distingue o país (por
--   exemplo 1876 para a Jamaica e 77 para o Cazaquistão).
-- ---------------------------------------------------------------------
CREATE TABLE steam_do_bedo.Pais (
    ddi VARCHAR(4),
    nome VARCHAR(255) NOT NULL,
    moeda VARCHAR(3) NOT NULL,

    CONSTRAINT pais_pkey PRIMARY KEY (ddi),
    CONSTRAINT pais_nome_key UNIQUE (nome),
    CONSTRAINT pais_moeda_fkey FOREIGN KEY (moeda)
        REFERENCES steam_do_bedo.Conversao(moeda)
);

-- ---------------------------------------------------------------------
-- Usuario
-- O quê: todo usuário; streamers são os usuários com passaporte em
--   StreamerPais (T9) e membros são os que têm Inscricao.
-- PK artificial id_usuario BIGINT; o nick continua único e
--   obrigatório (UNIQUE NOT NULL). Motivos: o nick pode mudar (as
--   plataformas permitem renomear) e era propagado para 6 tabelas,
--   inclusive Comentario; join por inteiro é mais barato que por texto
--   com collation; BIGINT porque a internet já tem 6 bilhões de pessoas,
--   acima dos 2,1 bilhões do INTEGER.
-- email e telefone únicos, cada um sozinho (telefone nulável).
-- pais_residencia NOT NULL. O minimundo dá "um país de
--   residência" a todo usuário, e a conversão da doação (T11)
--   depende dele. Assim todo usuário tem moeda, e ninguém precisa ser
--   tratado como USD por falta de país.
-- ---------------------------------------------------------------------
CREATE TABLE steam_do_bedo.Usuario (
    id_usuario BIGINT GENERATED ALWAYS AS IDENTITY,
    nick VARCHAR(255) NOT NULL,                               -- sai da PK, segue obrigatório
    email VARCHAR(255) NOT NULL,
    data_nasc DATE NOT NULL,
    telefone VARCHAR(13),
    end_postal VARCHAR(255),
    pais_residencia VARCHAR(4) NOT NULL,

    CONSTRAINT usuario_pkey PRIMARY KEY (id_usuario),
    CONSTRAINT usuario_nick_key UNIQUE (nick),
    CONSTRAINT usuario_email_key UNIQUE (email),
    CONSTRAINT usuario_telefone_key UNIQUE (telefone),
    CONSTRAINT usuario_pais_residencia_fkey FOREIGN KEY (pais_residencia)
        REFERENCES steam_do_bedo.Pais(ddi)
);

-- ---------------------------------------------------------------------
-- PlataformaUsuario ("tem conta" no ER)
-- O quê: conta de um usuário numa plataforma, com o número de usuário
--   daquela plataforma.
-- Referencia Usuario por id_usuario.
-- UNIQUE (nro_plataforma, nro_usuario). O número de usuário
--   "pode ser diferente em cada plataforma", mas dentro de uma
--   plataforma identifica a conta: duas contas com o mesmo número na
--   mesma plataforma seriam o mesmo fato duplicado.
-- Cuidado: o UNIQUE custa um índice numa tabela de ~10^6 linhas no seed;
--   aceito porque é regra de negócio e a tabela tem escrita rara.
-- ---------------------------------------------------------------------
CREATE TABLE steam_do_bedo.PlataformaUsuario (
    nro_plataforma INTEGER,
    id_usuario BIGINT,
    nro_usuario BIGINT NOT NULL,

    CONSTRAINT plataformausuario_pkey PRIMARY KEY (nro_plataforma, id_usuario),
    CONSTRAINT plataformausuario_nro_usuario_key UNIQUE (nro_plataforma, nro_usuario),
    CONSTRAINT plataformausuario_nro_plataforma_fkey FOREIGN KEY (nro_plataforma)
        REFERENCES steam_do_bedo.Plataforma(nro),
    CONSTRAINT plataformausuario_id_usuario_fkey FOREIGN KEY (id_usuario)
        REFERENCES steam_do_bedo.Usuario(id_usuario)
);

-- ---------------------------------------------------------------------
-- StreamerPais ("tem nacionalidade" no ER)
-- O quê: passaporte de um streamer em um país. Ter ao menos uma linha
--   aqui é o que caracteriza o usuário como streamer (T9).
-- Referencia Usuario por id_usuario (coluna id_streamer).
-- UNIQUE (ddi_pais, nro_passaporte): o número do passaporte é
--   único dentro do país emissor.
-- ---------------------------------------------------------------------
CREATE TABLE steam_do_bedo.StreamerPais (
    id_streamer BIGINT,
    ddi_pais VARCHAR(4),
    nro_passaporte VARCHAR(20) NOT NULL,

    CONSTRAINT streamerpais_pkey PRIMARY KEY (id_streamer, ddi_pais),
    CONSTRAINT streamerpais_passaporte_key UNIQUE (ddi_pais, nro_passaporte),
    CONSTRAINT streamerpais_id_streamer_fkey FOREIGN KEY (id_streamer)
        REFERENCES steam_do_bedo.Usuario(id_usuario),
    CONSTRAINT streamerpais_ddi_pais_fkey FOREIGN KEY (ddi_pais)
        REFERENCES steam_do_bedo.Pais(ddi)
);

-- ---------------------------------------------------------------------
-- EmpresaPais ("tem sede" no ER)
-- O quê: identificador nacional (CNPJ, EIN...) da empresa em cada país.
-- id_nacional NOT NULL e UNIQUE (ddi_pais, id_nacional). É a
--   identidade real da empresa e não se repete no país.
-- ---------------------------------------------------------------------
CREATE TABLE steam_do_bedo.EmpresaPais (
    nro_empresa INTEGER,
    ddi_pais VARCHAR(4),
    id_nacional VARCHAR(255) NOT NULL,

    CONSTRAINT empresapais_pkey PRIMARY KEY (nro_empresa, ddi_pais),
    CONSTRAINT empresapais_id_nacional_key UNIQUE (ddi_pais, id_nacional),
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
-- PK artificial id_canal; identidade de negócio (nome,
--   nro_plataforma) em UNIQUE.
-- id_canal passa de INTEGER para BIGINT. Com vídeo curto no
--   cenário, todo criador de shorts tem canal, e a soma de
--   canais em dezenas de plataformas pode passar de 2,1 bilhões.
-- O dono é referenciado por id_streamer (id_usuario).
-- Data NOT NULL (o T7 compara datas) e CHECK do tipo nomeado.
-- ---------------------------------------------------------------------
CREATE TABLE steam_do_bedo.Canal (
    id_canal BIGINT GENERATED ALWAYS AS IDENTITY,
    nome VARCHAR(255) NOT NULL,
    nro_plataforma INTEGER NOT NULL,

    tipo VARCHAR(30) NOT NULL,
    data TIMESTAMPTZ NOT NULL DEFAULT now(),
    descricao VARCHAR(700),
    qtd_visualizacoes BIGINT NOT NULL DEFAULT 0,

    id_streamer BIGINT NOT NULL,

    CONSTRAINT canal_pkey PRIMARY KEY (id_canal),
    CONSTRAINT canal_nome_plataforma_key UNIQUE (nome, nro_plataforma),
    CONSTRAINT canal_tipo_check CHECK (tipo IN ('privado', 'publico', 'misto')),
    CONSTRAINT canal_qtd_visualizacoes_check CHECK (qtd_visualizacoes >= 0),
    CONSTRAINT canal_id_streamer_fkey FOREIGN KEY (id_streamer)
        REFERENCES steam_do_bedo.Usuario(id_usuario),
    CONSTRAINT canal_nro_plataforma_fkey FOREIGN KEY (nro_plataforma)
        REFERENCES steam_do_bedo.Plataforma(nro)
);

-- ---------------------------------------------------------------------
-- Patrocinio
-- O quê: patrocínio vigente de uma empresa a um canal. O minimundo diz
--   que não há histórico: patrocínio encerrado é apagado (DELETE).
-- Valor sempre em USD (contrato externo; professor, 13:26).
-- ---------------------------------------------------------------------
CREATE TABLE steam_do_bedo.Patrocinio (
    nro_empresa INTEGER,
    id_canal BIGINT,
    valor NUMERIC(14, 2) NOT NULL,                            -- USD

    CONSTRAINT patrocinio_pkey PRIMARY KEY (nro_empresa, id_canal),
    CONSTRAINT patrocinio_valor_check CHECK (valor > 0),
    CONSTRAINT patrocinio_nro_empresa_fkey FOREIGN KEY (nro_empresa)
        REFERENCES steam_do_bedo.Empresa(nro),
    CONSTRAINT patrocinio_id_canal_fkey FOREIGN KEY (id_canal)
        REFERENCES steam_do_bedo.Canal(id_canal)
);

-- ---------------------------------------------------------------------
-- NivelCanal
-- O quê: os níveis de membro de um canal (nome, valor mensal, gif).
--   "Existem cinco níveis": o limite de 5 por canal é do trigger T8.
-- Valor na moeda do país de residência do membro, convertido
--   para USD na consulta (view V2).
-- gif NOT NULL ("para cada nível existe um arquivo .gif").
-- ---------------------------------------------------------------------
CREATE TABLE steam_do_bedo.NivelCanal (
    id_canal BIGINT,
    nivel VARCHAR(100),
    valor NUMERIC(14, 2) NOT NULL,
    gif VARCHAR(255) NOT NULL,

    CONSTRAINT nivelcanal_pkey PRIMARY KEY (id_canal, nivel),
    CONSTRAINT nivelcanal_valor_check CHECK (valor > 0),
    CONSTRAINT nivelcanal_id_canal_fkey FOREIGN KEY (id_canal)
        REFERENCES steam_do_bedo.Canal(id_canal)
);

-- ---------------------------------------------------------------------
-- Inscricao ("se inscreve" no ER)
-- O quê: membro vigente de um canal, num nível. Sem histórico (DELETE
--   quando a inscrição acaba).
-- a coluna data_inscricao foi removida. Era coluna
--   comum fora de chave, o que a regra do professor não permite, e o
--   minimundo já diz que só os membros vigentes ficam no sistema.
-- O membro é referenciado por id_membro (id_usuario).
-- ---------------------------------------------------------------------
CREATE TABLE steam_do_bedo.Inscricao (
    id_canal BIGINT,
    id_membro BIGINT,
    nivel VARCHAR(100) NOT NULL,

    CONSTRAINT inscricao_pkey PRIMARY KEY (id_canal, id_membro),
    CONSTRAINT inscricao_id_membro_fkey FOREIGN KEY (id_membro)
        REFERENCES steam_do_bedo.Usuario(id_usuario),
    CONSTRAINT inscricao_nivel_fkey FOREIGN KEY (id_canal, nivel)
        REFERENCES steam_do_bedo.NivelCanal(id_canal, nivel)
);

-- ---------------------------------------------------------------------
-- Video
-- O quê: vídeo (live, VOD ou short) postado num canal.
-- PK artificial; identidade de negócio (id_canal, titulo, dataH)
--   em UNIQUE, com titulo e dataH NOT NULL.
-- id_video UUID (antes BIGINT identity), gerado pela função
--   nativa gen_random_uuid() (versão 4, aleatória). O cenário com vídeo
--   curto leva à geração distribuída do id: cada coletor ou
--   partição gera o seu sem consultar uma sequence central e sem colisão.
--   Custo medido: +37% de espaço em Video e +28% no índice da PK de
--   Comentario em relação ao BIGINT.
-- Cuidado: por ser aleatório, cada vídeo novo entra num ponto qualquer do
--   B-tree da PK (e das PKs de Comentario e Doacao, que começam por
--   id_video), e não no fim, como uma sequence. Isso gera mais divisões
--   de página na inserção. Aceito em troca de usar só a função nativa.
-- Duração positiva, contadores não negativos e o pico
--   simultâneo não maior que o total (aplicado agora).
-- Cuidado: o UNIQUE (id_canal, ...) também atende "vídeos de um canal",
--   por ter id_canal como coluna líder.
-- ---------------------------------------------------------------------
CREATE TABLE steam_do_bedo.Video (
    id_video UUID NOT NULL DEFAULT gen_random_uuid(),         -- UUID v4 nativo
    id_canal BIGINT NOT NULL,
    titulo VARCHAR(255) NOT NULL,
    dataH TIMESTAMPTZ NOT NULL,

    tema VARCHAR(255),
    duracao INTERVAL,
    visu_simul BIGINT,
    visu_total BIGINT,

    CONSTRAINT video_pkey PRIMARY KEY (id_video),
    CONSTRAINT video_canal_titulo_datah_key UNIQUE (id_canal, titulo, dataH),
    CONSTRAINT video_duracao_check CHECK (duracao > INTERVAL '0'),
    CONSTRAINT video_visu_simul_check CHECK (visu_simul >= 0),
    CONSTRAINT video_visu_total_check CHECK (visu_total >= 0),
    CONSTRAINT video_visu_simul_total_check CHECK (visu_simul <= visu_total),
    CONSTRAINT video_id_canal_fkey FOREIGN KEY (id_canal)
        REFERENCES steam_do_bedo.Canal(id_canal)
);

-- ---------------------------------------------------------------------
-- Participa
-- O quê: streamers convidados que participam de um vídeo além do dono.
--   Só streamers (usuários com passaporte) participam: trigger T9.
-- ---------------------------------------------------------------------
CREATE TABLE steam_do_bedo.Participa (
    id_video UUID,
    id_streamer BIGINT,

    CONSTRAINT participa_pkey PRIMARY KEY (id_video, id_streamer),
    CONSTRAINT participa_id_video_fkey FOREIGN KEY (id_video)
        REFERENCES steam_do_bedo.Video(id_video),
    CONSTRAINT participa_id_streamer_fkey FOREIGN KEY (id_streamer)
        REFERENCES steam_do_bedo.Usuario(id_usuario)
);

-- ---------------------------------------------------------------------
-- Comentario
-- O quê: comentário online (feito durante a live) ou offline.
-- PK (id_video, seq); o usuário sai da PK e fica NOT NULL com FK.
-- seq INTEGER (o cenário prevê no máximo ~10^7 comentários num
--   vídeo, abaixo de 2,1 × 10^9). Se o INSERT não informar seq, o trigger
--   T3 gera max(seq) + 1 do vídeo.
-- Cuidado: seq é NOT NULL por ser PK, mas o NOT NULL só é verificado
--   depois dos triggers BEFORE, então um INSERT sem seq funciona quando
--   o T3 existe. Sem o triggers.sql, seq é obrigatório (caso do seed).
-- ---------------------------------------------------------------------
CREATE TABLE steam_do_bedo.Comentario (
    id_video UUID,
    seq INTEGER,
    id_usuario BIGINT NOT NULL,

    texto TEXT,
    dataH TIMESTAMPTZ NOT NULL DEFAULT now(),
    coment_on BOOLEAN NOT NULL,

    CONSTRAINT comentario_pkey PRIMARY KEY (id_video, seq),
    CONSTRAINT comentario_seq_check CHECK (seq > 0),
    CONSTRAINT comentario_id_video_fkey FOREIGN KEY (id_video)
        REFERENCES steam_do_bedo.Video(id_video),
    CONSTRAINT comentario_id_usuario_fkey FOREIGN KEY (id_usuario)
        REFERENCES steam_do_bedo.Usuario(id_usuario)
);

-- ---------------------------------------------------------------------
-- Doacao
-- O quê: doação trazida por um comentário.
-- PK (id_video, seq_comentario, seq_pg); o usuário não é
--   repetido (é determinado pelo comentário).
-- seq_pg passa de BIGINT a INTEGER (poucas doações por
--   comentário). Com uuid (16) + 2 INTEGER a chave fecha em 24 bytes sem
--   preenchimento de alinhamento. Gerado pelo trigger T4 se vier nulo.
-- Valor gravado em USD. O INSERT informa o valor na moeda do
--   país de residência de quem comentou e o trigger T11 converte. O seed
--   já grava em USD (os triggers não existem na carga).
-- ---------------------------------------------------------------------
CREATE TABLE steam_do_bedo.Doacao (
    id_video UUID,
    seq_comentario INTEGER,
    seq_pg INTEGER,

    valor NUMERIC(14, 2) NOT NULL,                            -- USD
    status VARCHAR(10) NOT NULL,

    CONSTRAINT doacao_pkey PRIMARY KEY (id_video, seq_comentario, seq_pg),
    CONSTRAINT doacao_status_check CHECK (status IN ('recusado', 'recebido', 'lido')),
    CONSTRAINT doacao_valor_check CHECK (valor > 0),
    CONSTRAINT doacao_seq_pg_check CHECK (seq_pg > 0),
    CONSTRAINT doacao_seq_comentario_check CHECK (seq_comentario > 0),
    CONSTRAINT doacao_comentario_fkey FOREIGN KEY (id_video, seq_comentario)
        REFERENCES steam_do_bedo.Comentario(id_video, seq)
);

-- ---------------------------------------------------------------------
-- Especializações de Doacao (disjuntas e totais: triggers T6)
-- Chave (id_video, seq_comentario, seq_doacao), FK para Doacao.
-- seq_doacao INTEGER, igual a Doacao.seq_pg.
-- ---------------------------------------------------------------------

-- TxID é o hash da transação na blockchain; não se repete.
-- Custo: um índice em BitCoin, a menor das especializações no seed.
CREATE TABLE steam_do_bedo.BitCoin (
    id_video UUID,
    seq_comentario INTEGER,
    seq_doacao INTEGER,

    TxID VARCHAR(64) NOT NULL,

    CONSTRAINT bitcoin_pkey PRIMARY KEY (id_video, seq_comentario, seq_doacao),
    CONSTRAINT bitcoin_txid_key UNIQUE (TxID),
    CONSTRAINT bitcoin_doacao_fkey FOREIGN KEY (id_video, seq_comentario, seq_doacao)
        REFERENCES steam_do_bedo.Doacao(id_video, seq_comentario, seq_pg)
);

-- IdPayPal identifica um pagamento; não se repete.
CREATE TABLE steam_do_bedo.PayPal (
    id_video UUID,
    seq_comentario INTEGER,
    seq_doacao INTEGER,

    IdPayPal VARCHAR(255) NOT NULL,

    CONSTRAINT paypal_pkey PRIMARY KEY (id_video, seq_comentario, seq_doacao),
    CONSTRAINT paypal_idpaypal_key UNIQUE (IdPayPal),
    CONSTRAINT paypal_doacao_fkey FOREIGN KEY (id_video, seq_comentario, seq_doacao)
        REFERENCES steam_do_bedo.Doacao(id_video, seq_comentario, seq_pg)
);

-- Cuidado: o minimundo pede também a data e hora do pagamento com cartão,
-- mas o modelo relacional do enunciado não tem essa coluna e a regra do
-- professor não permite criá-la. A data/hora é a do comentário.
-- O número do cartão é fictício no seed; em produção seria guardado
-- mascarado ou tokenizado (PCI DSS), o que está fora do escopo.
CREATE TABLE steam_do_bedo.CartaoCredito (
    id_video UUID,
    seq_comentario INTEGER,
    seq_doacao INTEGER,

    nro VARCHAR(19) NOT NULL,
    bandeira VARCHAR(50) NOT NULL,

    CONSTRAINT cartaocredito_pkey PRIMARY KEY (id_video, seq_comentario, seq_doacao),
    CONSTRAINT cartaocredito_doacao_fkey FOREIGN KEY (id_video, seq_comentario, seq_doacao)
        REFERENCES steam_do_bedo.Doacao(id_video, seq_comentario, seq_pg)
);

-- seq_plataforma: "número sequencial que depende do usuário, do comentário
-- e da plataforma". Gerado pelo trigger T5 como sequência por (usuário,
-- plataforma) quando vier nulo. INTEGER.
CREATE TABLE steam_do_bedo.MecanismoPlat (
    id_video UUID,
    seq_comentario INTEGER,
    seq_doacao INTEGER,

    seq_plataforma INTEGER NOT NULL,

    CONSTRAINT mecanismoplat_pkey PRIMARY KEY (id_video, seq_comentario, seq_doacao),
    CONSTRAINT mecanismoplat_seq_plataforma_check CHECK (seq_plataforma > 0),
    CONSTRAINT mecanismoplat_doacao_fkey FOREIGN KEY (id_video, seq_comentario, seq_doacao)
        REFERENCES steam_do_bedo.Doacao(id_video, seq_comentario, seq_pg)
);

-- ---------------------------------------------------------------------
-- Índices de apoio: ficam na parte 2 do functions.sql, executado depois da carga
-- (os índices são criados depois da carga). Aqui só existem os
-- índices criados automaticamente pelas PRIMARY KEY e UNIQUE.
-- ---------------------------------------------------------------------
