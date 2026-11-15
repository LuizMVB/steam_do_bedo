-- =====================================================================
-- Projeto de Banco de Dados 2026/2 - Stream do Bedo
-- Script de carga (seed) - PostgreSQL 17
--
-- Item mandatório 1: inserir entre 1.000 e 10.000 tuplas por tabela.
--
-- Os dados são artificiais: cada tabela é populada por um INSERT ... SELECT
-- sobre generate_series e/ou sobre as tabelas já populadas (via JOIN), o que
-- garante que toda chave estrangeira aponta para uma tupla existente.
-- O setseed() no início fixa a sequência do random(), então toda execução
-- sobre o schema recém-criado pelo ddl.sql produz os mesmos dados.
--
-- Execução (sempre após o ddl.sql):
--   psql -U admin -d steam-do-bedo-db -f ddl.sql
--   psql -U admin -d steam-do-bedo-db -f seed.sql
--
-- Volume gerado (aproximado):
--   Conversao 1000 | Pais 1000 | Empresa 1000 | EmpresaPais ~1200
--   Plataforma 1000 | Usuario 4000 | PlataformaUsuario 8000
--   StreamerPais ~1200 | Canal ~1250 | NivelCanal ~6250 | Inscricao ~8500
--   Patrocinio ~1750 | Video ~5600 | Participa ~5000 | Comentario 9000
--   Doacao 5000 | BitCoin, PayPal, CartaoCredito, MecanismoPlat 1250 cada
-- =====================================================================

SET search_path TO steam_do_bedo;

BEGIN;

-- Semente fixa: random() passa a gerar sempre a mesma sequência
SELECT setseed(0.42);

-- Workers paralelos têm gerador aleatório próprio; sem paralelismo a
-- sequência do random() continua reprodutível
SET LOCAL max_parallel_workers_per_gather = 0;

-- ---------------------------------------------------------------------
-- Conversao: 36 moedas reais + 964 fictícias = 1000
-- Fatores de conversão para USD aproximados
-- ---------------------------------------------------------------------
INSERT INTO steam_do_bedo.Conversao (moeda, nome, fator_conver) VALUES
    ('USD', 'Dólar americano',        1.00000000),
    ('BRL', 'Real brasileiro',        0.18000000),
    ('GBP', 'Libra esterlina',        1.27000000),
    ('EUR', 'Euro',                   1.08000000),
    ('JPY', 'Iene japonês',           0.00670000),
    ('KRW', 'Won sul-coreano',        0.00074000),
    ('CNY', 'Yuan chinês',            0.14000000),
    ('INR', 'Rupia indiana',          0.01200000),
    ('MXN', 'Peso mexicano',          0.05500000),
    ('ARS', 'Peso argentino',         0.00110000),
    ('CLP', 'Peso chileno',           0.00105000),
    ('COP', 'Peso colombiano',        0.00025000),
    ('PEN', 'Sol peruano',            0.27000000),
    ('UYU', 'Peso uruguaio',          0.02500000),
    ('PYG', 'Guarani paraguaio',      0.00013000),
    ('AUD', 'Dólar australiano',      0.66000000),
    ('NZD', 'Dólar neozelandês',      0.60000000),
    ('ZAR', 'Rand sul-africano',      0.05400000),
    ('CHF', 'Franco suíço',           1.12000000),
    ('SEK', 'Coroa sueca',            0.09500000),
    ('NOK', 'Coroa norueguesa',       0.09300000),
    ('DKK', 'Coroa dinamarquesa',     0.14500000),
    ('PLN', 'Zloty polonês',          0.25000000),
    ('TRY', 'Lira turca',             0.02900000),
    ('RUB', 'Rublo russo',            0.01100000),
    ('SGD', 'Dólar de Singapura',     0.74000000),
    ('HKD', 'Dólar de Hong Kong',     0.12800000),
    ('IDR', 'Rupia indonésia',        0.00006200),
    ('PHP', 'Peso filipino',          0.01750000),
    ('THB', 'Baht tailandês',         0.02800000),
    ('AED', 'Dirham dos Emirados',    0.27230000),
    ('SAR', 'Rial saudita',           0.26670000),
    ('EGP', 'Libra egípcia',          0.02050000),
    ('NGN', 'Naira nigeriana',        0.00065000),
    ('ILS', 'Novo shekel israelense', 0.27000000),
    ('UAH', 'Grívnia ucraniana',      0.02400000);

-- Códigos fictícios XAA..XZZ e depois WAA..WKZ (nenhuma moeda real acima começa com X ou W)
INSERT INTO steam_do_bedo.Conversao (moeda, nome, fator_conver)
SELECT cod, 'Moeda Fictícia ' || cod, round((0.0005 + 2.5 * random())::numeric, 8)
FROM generate_series(1, 964) AS i
CROSS JOIN LATERAL (
    SELECT CASE WHEN i <= 676 THEN 'X' ELSE 'W' END
           || chr(65 + ((i - 1) % 676) / 26)
           || chr(65 + (i - 1) % 26) AS cod
) AS m;

-- ---------------------------------------------------------------------
-- Pais: 40 países reais + 960 fictícios (DDI 1001..1960) = 1000
-- ---------------------------------------------------------------------
INSERT INTO steam_do_bedo.Pais (ddi, nome, moeda) VALUES
    ('1',   'Estados Unidos',  'USD'),
    ('55',  'Brasil',          'BRL'),
    ('44',  'Reino Unido',     'GBP'),
    ('351', 'Portugal',        'EUR'),
    ('49',  'Alemanha',        'EUR'),
    ('33',  'França',          'EUR'),
    ('34',  'Espanha',         'EUR'),
    ('39',  'Itália',          'EUR'),
    ('81',  'Japão',           'JPY'),
    ('82',  'Coreia do Sul',   'KRW'),
    ('86',  'China',           'CNY'),
    ('91',  'Índia',           'INR'),
    ('52',  'México',          'MXN'),
    ('54',  'Argentina',       'ARS'),
    ('56',  'Chile',           'CLP'),
    ('57',  'Colômbia',        'COP'),
    ('51',  'Peru',            'PEN'),
    ('598', 'Uruguai',         'UYU'),
    ('595', 'Paraguai',        'PYG'),
    ('61',  'Austrália',       'AUD'),
    ('64',  'Nova Zelândia',   'NZD'),
    ('27',  'África do Sul',   'ZAR'),
    ('41',  'Suíça',           'CHF'),
    ('46',  'Suécia',          'SEK'),
    ('47',  'Noruega',         'NOK'),
    ('45',  'Dinamarca',       'DKK'),
    ('48',  'Polônia',         'PLN'),
    ('90',  'Turquia',         'TRY'),
    ('7',   'Rússia',          'RUB'),
    ('65',  'Singapura',       'SGD'),
    ('852', 'Hong Kong',       'HKD'),
    ('62',  'Indonésia',       'IDR'),
    ('63',  'Filipinas',       'PHP'),
    ('66',  'Tailândia',       'THB'),
    ('971', 'Emirados Árabes', 'AED'),
    ('966', 'Arábia Saudita',  'SAR'),
    ('20',  'Egito',           'EGP'),
    ('234', 'Nigéria',         'NGN'),
    ('972', 'Israel',          'ILS'),
    ('380', 'Ucrânia',         'UAH');

-- Cada país fictício usa uma moeda fictícia diferente
INSERT INTO steam_do_bedo.Pais (ddi, nome, moeda)
SELECT (1000 + rn)::text, 'País Fictício ' || lpad(rn::text, 3, '0'), moeda
FROM (
    SELECT moeda, row_number() OVER (ORDER BY moeda) AS rn
    FROM steam_do_bedo.Conversao
    WHERE nome LIKE 'Moeda Fictícia%'
) AS m
WHERE rn <= 960;

-- ---------------------------------------------------------------------
-- Empresa: 24 reais + 976 fictícias = 1000
-- ---------------------------------------------------------------------
INSERT INTO steam_do_bedo.Empresa (nome, nome_fantasia) VALUES
    ('Google LLC',                      'Google'),
    ('YouTube LLC',                     'YouTube'),
    ('Amazon.com Inc.',                 'Amazon'),
    ('Twitch Interactive Inc.',         'Twitch'),
    ('Justin.tv Inc.',                  'Justin.tv'),
    ('Meta Platforms Inc.',             'Meta'),
    ('ByteDance Ltd.',                  'ByteDance'),
    ('Tencent Holdings Ltd.',           'Tencent'),
    ('Kick Streaming Pty Ltd.',         'Kick'),
    ('Huya Inc.',                       'Huya'),
    ('Bilibili Inc.',                   'Bilibili'),
    ('Rumble Inc.',                     'Rumble'),
    ('Microsoft Corporation',           'Microsoft'),
    ('Sony Group Corporation',          'Sony'),
    ('Nintendo Co. Ltd.',               'Nintendo'),
    ('Riot Games Inc.',                 'Riot Games'),
    ('Valve Corporation',               'Valve'),
    ('Epic Games Inc.',                 'Epic Games'),
    ('Garena Online Pte. Ltd.',         'Garena'),
    ('Ubisoft Entertainment SA',        'Ubisoft'),
    ('Razer Inc.',                      'Razer'),
    ('Logitech International SA',       'Logitech'),
    ('KaBuM! Comércio Eletrônico S.A.', 'KaBuM!'),
    ('LOUD Esports Ltda.',              'LOUD');

-- O número no nome garante a restrição UNIQUE de Empresa.nome
WITH fantasias AS (
    SELECT i,
           (ARRAY['Nexus', 'Orion', 'Vertex', 'Aurora', 'Quantum', 'Atlas', 'Helix',
                  'Pulse', 'Zenith', 'Nimbus', 'Apex', 'Lumen', 'Vortex', 'Prisma',
                  'Fênix', 'Delta', 'Sigma', 'Astra', 'Boreal', 'Cobalto'])[1 + floor(random() * 20)::int]
           || ' ' ||
           (ARRAY['Games', 'Tecnologia', 'Energéticos', 'Periféricos', 'Telecom', 'Bebidas',
                  'Hardware', 'Educação', 'Moda', 'Alimentos', 'Seguros', 'Software',
                  'Eletrônicos'])[1 + floor(random() * 13)::int] AS fantasia
    FROM generate_series(1, 976) AS i
)
INSERT INTO steam_do_bedo.Empresa (nome, nome_fantasia)
SELECT fantasia || ' ' || lpad(i::text, 4, '0') || ' '
       || (ARRAY['Ltda.', 'S.A.', 'Inc.', 'LLC', 'GmbH', 'Ltd.'])[1 + floor(random() * 6)::int],
       fantasia
FROM fantasias
ORDER BY i;

-- ---------------------------------------------------------------------
-- EmpresaPais: país de origem de cada empresa + segunda sede para ~20%
-- Empresas fictícias: ~45% Brasil, ~40% outro país real, ~15% país fictício
-- ---------------------------------------------------------------------
WITH paises AS (
    SELECT ddi,
           length(ddi) <= 3                                           AS real,
           row_number() OVER (PARTITION BY length(ddi) <= 3 ORDER BY ddi) AS r,
           count(*)     OVER (PARTITION BY length(ddi) <= 3)              AS n
    FROM steam_do_bedo.Pais
),
sorteio AS (
    SELECT e.nro, r.ddi AS ddi_real, random() AS u_pais, random() AS u_idx, random() < 0.2 AS segunda_sede
    FROM steam_do_bedo.Empresa e
    LEFT JOIN (VALUES
        ('Google LLC', '1'), ('YouTube LLC', '1'), ('Amazon.com Inc.', '1'),
        ('Twitch Interactive Inc.', '1'), ('Justin.tv Inc.', '1'), ('Meta Platforms Inc.', '1'),
        ('ByteDance Ltd.', '86'), ('Tencent Holdings Ltd.', '86'), ('Kick Streaming Pty Ltd.', '61'),
        ('Huya Inc.', '86'), ('Bilibili Inc.', '86'), ('Rumble Inc.', '1'),
        ('Microsoft Corporation', '1'), ('Sony Group Corporation', '81'), ('Nintendo Co. Ltd.', '81'),
        ('Riot Games Inc.', '1'), ('Valve Corporation', '1'), ('Epic Games Inc.', '1'),
        ('Garena Online Pte. Ltd.', '65'), ('Ubisoft Entertainment SA', '33'), ('Razer Inc.', '65'),
        ('Logitech International SA', '41'), ('KaBuM! Comércio Eletrônico S.A.', '55'),
        ('LOUD Esports Ltda.', '55')
    ) AS r(nome, ddi) ON r.nome = e.nome
),
origem AS (
    SELECT s.nro, s.segunda_sede,
           CASE WHEN s.ddi_real IS NOT NULL THEN s.ddi_real
                WHEN s.u_pais < 0.45        THEN '55'
                WHEN s.u_pais < 0.85        THEN pr.ddi
                ELSE pf.ddi END AS ddi
    FROM sorteio s
    JOIN paises pr ON pr.real     AND pr.r = 1 + floor(s.u_idx * pr.n)
    JOIN paises pf ON NOT pf.real AND pf.r = 1 + floor(s.u_idx * pf.n)
),
sedes AS (
    SELECT nro, ddi FROM origem
    UNION ALL
    SELECT nro, CASE WHEN ddi = '1' THEN '55' ELSE '1' END FROM origem WHERE segunda_sede
)
INSERT INTO steam_do_bedo.EmpresaPais (nro_empresa, ddi_pais, id_nacional)
SELECT nro, ddi,
       CASE ddi
           -- CNPJ: 00.000.000/0001-00
           WHEN '55' THEN regexp_replace(lpad(floor(random() * 100000000)::bigint::text, 8, '0'),
                                         '(\d{2})(\d{3})(\d{3})', '\1.\2.\3')
                          || '/0001-' || lpad(floor(random() * 100)::int::text, 2, '0')
           -- EIN: 00-0000000
           WHEN '1'  THEN regexp_replace(lpad(floor(random() * 1000000000)::bigint::text, 9, '0'),
                                         '(\d{2})(\d{7})', '\1-\2')
           ELSE 'NID' || ddi || '-' || upper(substr(md5(random()::text), 1, 10))
       END
FROM sedes;

-- ---------------------------------------------------------------------
-- Plataforma: 10 reais + 990 fictícias = 1000
-- qtd_users (derivado) é calculado ao final do script
-- ---------------------------------------------------------------------
INSERT INTO steam_do_bedo.Plataforma (nome, empresa_fund, empresa_resp, data_fund)
SELECT p.nome, ef.nro, er.nro, p.data_fund
FROM (VALUES
    (1,  'YouTube',         'YouTube LLC',             'Google LLC',              DATE '2005-02-14'),
    (2,  'Twitch',          'Justin.tv Inc.',          'Twitch Interactive Inc.', DATE '2011-06-06'),
    (3,  'Kick',            'Kick Streaming Pty Ltd.', 'Kick Streaming Pty Ltd.', DATE '2022-12-06'),
    (4,  'Facebook Gaming', 'Meta Platforms Inc.',     'Meta Platforms Inc.',     DATE '2018-06-01'),
    (5,  'TikTok Live',     'ByteDance Ltd.',          'ByteDance Ltd.',          DATE '2019-01-01'),
    (6,  'Trovo',           'Tencent Holdings Ltd.',   'Tencent Holdings Ltd.',   DATE '2020-02-01'),
    (7,  'Huya',            'Huya Inc.',               'Huya Inc.',               DATE '2014-11-01'),
    (8,  'Bilibili Live',   'Bilibili Inc.',           'Bilibili Inc.',           DATE '2009-06-26'),
    (9,  'Rumble',          'Rumble Inc.',             'Rumble Inc.',             DATE '2013-10-01'),
    (10, 'Mixer',           'Microsoft Corporation',   'Microsoft Corporation',   DATE '2016-01-05')
) AS p(ordem, nome, fundadora, responsavel, data_fund)
JOIN steam_do_bedo.Empresa ef ON ef.nome = p.fundadora
JOIN steam_do_bedo.Empresa er ON er.nome = p.responsavel
ORDER BY p.ordem;

-- Fundadora sorteada; em 60% dos casos ela também é a responsável
WITH empresas AS (
    SELECT nro, row_number() OVER (ORDER BY nro) AS r, count(*) OVER () AS n
    FROM steam_do_bedo.Empresa
),
sorteio AS (
    SELECT i, random() AS u_fund, random() AS u_resp, random() < 0.6 AS mesma_empresa
    FROM generate_series(11, 1000) AS i
)
INSERT INTO steam_do_bedo.Plataforma (nome, empresa_fund, empresa_resp, data_fund)
SELECT (ARRAY['Stream', 'Live', 'Play', 'Cast', 'Game',
              'Pixel', 'Hyper', 'Ultra', 'Mega', 'Neo'])[1 + floor(random() * 10)::int]
       || (ARRAY['Wave', 'Hub', 'Zone', 'Box', 'Arena',
                 'Spot', 'Flow', 'Nest', 'Verse', 'Land'])[1 + floor(random() * 10)::int]
       || ' ' || lpad(s.i::text, 4, '0'),
       ef.nro,
       CASE WHEN s.mesma_empresa THEN ef.nro ELSE er.nro END,
       DATE '2005-01-01' + floor(random() * 7000)::int
FROM sorteio s
JOIN empresas ef ON ef.r = 1 + floor(s.u_fund * ef.n)
JOIN empresas er ON er.r = 1 + floor(s.u_resp * er.n)
ORDER BY s.i;

-- ---------------------------------------------------------------------
-- Usuario: 4000
-- País de residência: ~45% Brasil, ~40% outro país real, ~15% país fictício
-- ---------------------------------------------------------------------
WITH paises AS (
    SELECT ddi,
           length(ddi) <= 3                                           AS real,
           row_number() OVER (PARTITION BY length(ddi) <= 3 ORDER BY ddi) AS r,
           count(*)     OVER (PARTITION BY length(ddi) <= 3)              AS n
    FROM steam_do_bedo.Pais
),
sorteio AS (
    SELECT i,
           (ARRAY['shadow', 'pixel', 'ninja', 'storm', 'lunar', 'turbo', 'cyber',
                  'frost', 'blaze', 'viper', 'nova', 'echo', 'titan', 'ghost',
                  'omega', 'rapid', 'neon', 'zero', 'alpha', 'kraken'])[1 + i % 20]
           || '_' || lpad(i::text, 4, '0') AS nick,
           random() AS u_pais,
           random() AS u_idx
    FROM generate_series(1, 4000) AS i
),
residencia AS (
    SELECT s.i, s.nick,
           CASE WHEN s.u_pais < 0.45 THEN '55'
                WHEN s.u_pais < 0.85 THEN pr.ddi
                ELSE pf.ddi END AS ddi
    FROM sorteio s
    JOIN paises pr ON pr.real     AND pr.r = 1 + floor(s.u_idx * pr.n)
    JOIN paises pf ON NOT pf.real AND pf.r = 1 + floor(s.u_idx * pf.n)
)
INSERT INTO steam_do_bedo.Usuario (nick, email, data_nasc, telefone, end_postal, pais_residencia)
SELECT nick,
       nick || '@' || (ARRAY['gmail.com', 'outlook.com', 'yahoo.com', 'proton.me',
                             'uol.com.br', 'icloud.com', 'id.uff.br'])[1 + floor(random() * 7)::int],
       DATE '1970-01-01' + floor(random() * 14600)::int,
       ddi || lpad(floor(random() * 1000000000)::bigint::text, 9, '0'),
       (ARRAY['Rua das Flores', 'Avenida Brasil', 'Rua São João', 'Avenida Paulista',
              'Rua da Praia', 'Rua Sete de Setembro', 'Avenida Atlântica',
              'Rua XV de Novembro', 'Rua do Sol', 'Avenida Central'])[1 + floor(random() * 10)::int]
           || ', ' || (1 + floor(random() * 2000)::int)
           || ' - CP ' || lpad(floor(random() * 100000000)::bigint::text, 8, '0'),
       ddi
FROM residencia
ORDER BY i;

-- ---------------------------------------------------------------------
-- PlataformaUsuario: cada usuário tem conta em 2 plataformas = 8000
--   uma das 10 reais (distribuição uniforme) e uma das 990 fictícias
--   nro_usuario é sequencial dentro de cada plataforma
-- ---------------------------------------------------------------------
WITH usuarios AS (
    SELECT nick, row_number() OVER (ORDER BY nick) - 1 AS n
    FROM steam_do_bedo.Usuario
),
plataformas AS (
    SELECT nro, row_number() OVER (ORDER BY nro) AS r
    FROM steam_do_bedo.Plataforma
)
INSERT INTO steam_do_bedo.PlataformaUsuario (nro_plataforma, nick_usuario, nro_usuario)
SELECT p.nro, u.nick, row_number() OVER (PARTITION BY p.nro ORDER BY u.nick)
FROM usuarios u
JOIN plataformas p ON p.r = 1 + u.n % 10
                   OR p.r = 11 + u.n % 990;

-- ---------------------------------------------------------------------
-- StreamerPais: 1000 usuários sorteados são streamers; passaporte do país
-- de residência + segundo passaporte (Brasil ou Portugal) para ~20%
-- ---------------------------------------------------------------------
-- Obs.: um random() no SELECT idêntico ao do ORDER BY é tratado pelo
-- PostgreSQL como o MESMO valor; por isso os demais sorteios ficam numa
-- CTE separada da ordenação (mesmo cuidado em Inscricao e Doacao).
WITH sorteados AS (
    SELECT nick, pais_residencia
    FROM steam_do_bedo.Usuario
    ORDER BY random()
    LIMIT 1000
),
streamers AS (
    SELECT nick, pais_residencia, random() < 0.2 AS dupla_cidadania
    FROM sorteados
),
passaportes AS (
    SELECT nick, pais_residencia AS ddi FROM streamers
    UNION ALL
    SELECT nick, CASE WHEN pais_residencia = '55' THEN '351' ELSE '55' END
    FROM streamers
    WHERE dupla_cidadania
)
INSERT INTO steam_do_bedo.StreamerPais (nick_streamer, ddi_pais, nro_passaporte)
SELECT nick, ddi,
       chr(65 + floor(random() * 26)::int)
       || chr(65 + floor(random() * 26)::int)
       || lpad(floor(random() * 10000000)::int::text, 7, '0')
FROM passaportes;

-- ---------------------------------------------------------------------
-- Canal: todo streamer tem um canal na sua plataforma real e ~25% têm
-- um segundo canal na sua plataforma fictícia (~1250).
-- qtd_visualizacoes (derivado) é calculado ao final do script
-- ---------------------------------------------------------------------
WITH plataformas AS (
    SELECT nro, row_number() OVER (ORDER BY nro) <= 10 AS real
    FROM steam_do_bedo.Plataforma
),
contas AS (
    SELECT pu.nick_usuario AS nick, pu.nro_plataforma, p.real,
           random() AS u_canal, random() AS u_tipo
    FROM steam_do_bedo.PlataformaUsuario pu
    JOIN plataformas p ON p.nro = pu.nro_plataforma
    WHERE pu.nick_usuario IN (SELECT nick_streamer FROM steam_do_bedo.StreamerPais)
)
INSERT INTO steam_do_bedo.Canal (nome, nro_plataforma, tipo, data, descricao, nick_streamer)
SELECT nick || CASE WHEN real
                    THEN (ARRAY[' TV', ' Gaming', ' Live', ' Plays', ' Oficial'])[1 + floor(random() * 5)::int]
                    ELSE (ARRAY[' Clips', ' Cortes', ' Highlights', ' VODs'])[1 + floor(random() * 4)::int]
               END,
       nro_plataforma,
       CASE WHEN u_tipo < 0.60 THEN 'publico'
            WHEN u_tipo < 0.85 THEN 'misto'
            ELSE 'privado' END,
       date_trunc('second', TIMESTAMPTZ '2015-01-01 00:00:00+00' + random() * INTERVAL '9 years'),
       CASE WHEN real
            THEN 'Canal oficial de ' || nick || ' com lives e gameplays.'
            ELSE 'Cortes e melhores momentos das lives de ' || nick || '.' END,
       nick
FROM contas
WHERE real OR u_canal < 0.25;

-- ---------------------------------------------------------------------
-- NivelCanal: 5 níveis por canal (~6250)
-- Cada canal usa um dos 5 temas de nomes e um multiplicador próprio sobre
-- a tabela base de valores (USD/mês), de modo que o valor cresce com o nível
-- ---------------------------------------------------------------------
WITH canais AS (
    SELECT nome, nro_plataforma,
           1 + floor(random() * 5)::int AS tema,
           (0.5 + random())::numeric    AS multiplicador
    FROM steam_do_bedo.Canal
)
INSERT INTO steam_do_bedo.NivelCanal (nome_canal, nro_plataforma, nivel, valor, gif)
SELECT c.nome,
       c.nro_plataforma,
       (ARRAY[
           ['Bronze',  'Prata',    'Ouro',     'Platina',  'Diamante'],
           ['Recruta', 'Soldado',  'Sargento', 'Capitão',  'General'],
           ['Fã',      'Apoiador', 'Parceiro', 'VIP',      'Lenda'],
           ['Bit',     'Byte',     'Kilobyte', 'Megabyte', 'Gigabyte'],
           ['Novato',  'Aprendiz', 'Veterano', 'Mestre',   'Lendário']
       ])[c.tema][k],
       round((ARRAY[1.99, 4.99, 9.99, 24.99, 49.99])[k] * c.multiplicador, 2),
       'gifs/' || regexp_replace(lower(c.nome), '[^a-z0-9]+', '_', 'g') || '_nivel' || k || '.gif'
FROM canais c
CROSS JOIN generate_series(1, 5) AS k;

-- ---------------------------------------------------------------------
-- Inscricao (~8500): cada usuário é membro de 2 canais sorteados da sua
-- plataforma real e, com 50% de chance, de 1 canal da sua plataforma
-- fictícia. Só se inscreve onde tem conta e nunca no próprio canal.
-- Níveis mais baratos são mais frequentes.
-- ---------------------------------------------------------------------
WITH plataformas AS (
    SELECT nro, row_number() OVER (ORDER BY nro) <= 10 AS real
    FROM steam_do_bedo.Plataforma
),
niveis AS (
    SELECT nome_canal, nro_plataforma, nivel,
           row_number() OVER (PARTITION BY nome_canal, nro_plataforma ORDER BY valor) AS ordem
    FROM steam_do_bedo.NivelCanal
),
pares AS (
    SELECT pu.nick_usuario, c.nome, c.nro_plataforma, p.real,
           random() AS u_ordem,
           random() AS u_inscreve,
           random() AS u_nivel
    FROM steam_do_bedo.PlataformaUsuario pu
    JOIN plataformas p ON p.nro = pu.nro_plataforma
    JOIN steam_do_bedo.Canal c ON c.nro_plataforma = pu.nro_plataforma
                               AND c.nick_streamer <> pu.nick_usuario
),
candidatos AS (
    SELECT pares.*,
           row_number() OVER (PARTITION BY nick_usuario, nro_plataforma ORDER BY u_ordem) AS sorteio
    FROM pares
)
INSERT INTO steam_do_bedo.Inscricao (nome_canal, nro_plataforma, nick_membro, nivel)
SELECT ca.nome, ca.nro_plataforma, ca.nick_usuario, n.nivel
FROM candidatos ca
JOIN niveis n ON n.nome_canal = ca.nome
             AND n.nro_plataforma = ca.nro_plataforma
             AND n.ordem = 1 + floor(5 * ca.u_nivel ^ 2)::int
WHERE (ca.real AND ca.sorteio <= 2)
   OR (NOT ca.real AND ca.sorteio = 1 AND ca.u_inscreve < 0.5);

-- ---------------------------------------------------------------------
-- Video: 3 a 6 vídeos por canal (~5600); 70% seguem o tema do canal.
-- Visualizações com distribuição bem assimétrica (poucos vídeos virais).
-- ---------------------------------------------------------------------
WITH temas AS (
    SELECT ARRAY['Minecraft', 'Fortnite', 'League of Legends', 'Valorant', 'Counter-Strike 2',
                 'GTA V', 'Elden Ring', 'Free Fire', 'Roblox', 'Dota 2', 'Apex Legends',
                 'Call of Duty', 'EA Sports FC', 'Hollow Knight', 'Stardew Valley',
                 'The Sims 4', 'Rocket League', 'Pokémon', 'Just Chatting', 'Speedrun'] AS lista
),
canais AS (
    SELECT c.nome, c.nro_plataforma, c.data,
           t.lista[1 + floor(random() * 20)::int] AS tema_canal,
           3 + floor(random() * 4)::int            AS qtd_videos
    FROM steam_do_bedo.Canal c
    CROSS JOIN temas t
),
videos AS (
    SELECT c.nome, c.nro_plataforma, k,
           CASE WHEN random() < 0.7 THEN c.tema_canal
                ELSE t.lista[1 + floor(random() * 20)::int] END                AS tema,
           date_trunc('second', c.data + k * INTERVAL '20 days'
                                       + random() * INTERVAL '19 days')        AS dataH,
           (50 + floor(1500000 * random() ^ 4))::bigint                        AS visu_total
    FROM canais c
    CROSS JOIN temas t
    CROSS JOIN LATERAL generate_series(1, c.qtd_videos) AS k
)
INSERT INTO steam_do_bedo.Video (nome_canal, nro_plataforma, titulo, dataH, tema, duracao, visu_simul, visu_total)
SELECT nome,
       nro_plataforma,
       tema || ' - '
           || (ARRAY['Gameplay ao vivo', 'Rumo ao topo do ranking', 'Desafio sem morrer',
                     'Jogando com inscritos', 'Primeira vez jogando', 'Tentando zerar em uma live',
                     'Testando a nova atualização', 'Campeonato da comunidade', 'Melhores momentos',
                     'Tutorial para iniciantes', 'Maratona de 12 horas', 'Reagindo aos clipes',
                     'Build definitiva', 'Modo hardcore', 'Live de sexta'])[1 + floor(random() * 15)::int]
           || ' #' || k,
       dataH,
       tema,
       (10 + floor(random() * 350)::int) * INTERVAL '1 minute',
       greatest(1, floor(visu_total * (0.02 + 0.25 * random())))::bigint,
       visu_total
FROM videos;

-- ---------------------------------------------------------------------
-- Participa: 0 a 2 streamers convidados por vídeo (~5000).
-- O dono do canal não é repetido aqui (já é derivável de Canal) e os
-- convidados precisam ter conta na plataforma do vídeo.
-- ---------------------------------------------------------------------
WITH videos AS (
    SELECT v.nome_canal, v.nro_plataforma, v.titulo, v.dataH,
           c.nick_streamer          AS dono,
           floor(random() * 3)::int AS qtd_convidados
    FROM steam_do_bedo.Video v
    JOIN steam_do_bedo.Canal c ON c.nome = v.nome_canal AND c.nro_plataforma = v.nro_plataforma
),
candidatos AS (
    SELECT v.nome_canal, v.nro_plataforma, v.titulo, v.dataH, v.qtd_convidados,
           pu.nick_usuario,
           row_number() OVER (PARTITION BY v.nome_canal, v.nro_plataforma, v.titulo, v.dataH
                              ORDER BY random()) AS sorteio
    FROM videos v
    JOIN steam_do_bedo.PlataformaUsuario pu ON pu.nro_plataforma = v.nro_plataforma
                                            AND pu.nick_usuario <> v.dono
    WHERE pu.nick_usuario IN (SELECT nick_streamer FROM steam_do_bedo.StreamerPais)
)
INSERT INTO steam_do_bedo.Participa (nome_canal, nro_plataforma, titulo_video, dataH_video, nick_streamer)
SELECT nome_canal, nro_plataforma, titulo, dataH, nick_usuario
FROM candidatos
WHERE sorteio <= qtd_convidados;

-- ---------------------------------------------------------------------
-- Comentario: 9000, concentrados nos vídeos mais vistos.
-- O autor tem conta na plataforma do vídeo; ~65% são online (durante o
-- vídeo) e ~35% offline (até 60 dias depois). seq é sequencial por vídeo,
-- em ordem cronológica.
-- ---------------------------------------------------------------------
WITH videos AS (
    SELECT v.*, row_number() OVER (ORDER BY v.visu_total DESC, v.nome_canal, v.titulo) - 1 AS idx
    FROM steam_do_bedo.Video v
),
contas AS (
    SELECT nro_plataforma, nick_usuario,
           row_number() OVER (PARTITION BY nro_plataforma ORDER BY nick_usuario) AS r,
           count(*)     OVER (PARTITION BY nro_plataforma)                       AS n
    FROM steam_do_bedo.PlataformaUsuario
),
sorteio AS (
    -- random()^2 favorece os primeiros índices, isto é, os vídeos mais vistos
    SELECT i,
           floor(random() ^ 2 * (SELECT count(*) FROM steam_do_bedo.Video))::bigint AS idx_video,
           random()        AS u_autor,
           random() < 0.65 AS online,
           random()        AS u_tempo
    FROM generate_series(1, 9000) AS i
),
comentarios AS (
    SELECT v.nome_canal, v.nro_plataforma, v.titulo, v.dataH AS dataH_video,
           ct.nick_usuario, s.i, s.online,
           date_trunc('second',
               CASE WHEN s.online THEN v.dataH + v.duracao * s.u_tempo
                    ELSE v.dataH + v.duracao + INTERVAL '60 days' * s.u_tempo END) AS dataH
    FROM sorteio s
    JOIN videos v  ON v.idx = s.idx_video
    JOIN contas ct ON ct.nro_plataforma = v.nro_plataforma
                  AND ct.r = 1 + floor(s.u_autor * ct.n)
)
INSERT INTO steam_do_bedo.Comentario (nome_canal, nro_plataforma, titulo_video, dataH_video,
                                       nick_usuario, seq, texto, dataH, coment_on)
SELECT nome_canal, nro_plataforma, titulo, dataH_video, nick_usuario,
       row_number() OVER (PARTITION BY nome_canal, nro_plataforma, titulo, dataH_video
                          ORDER BY dataH, i),
       (ARRAY['Que jogada incrível!', 'Primeiro!', 'Manda salve pro Rio!', 'Essa build é muito boa',
              'Kkkkkk morri de rir', 'Qual a configuração do seu PC?', 'Joga com os inscritos!',
              'Live top demais', 'Faltou pouco!', 'Esse boss é muito difícil', 'Vim pelo clipe',
              'Ótimo conteúdo, parabéns', 'Quando sai o próximo vídeo?', 'GG WP',
              'Explica essa estratégia de novo?', 'Assistindo do Japão', 'Que susto kkkk',
              'Melhor streamer do Brasil', 'Volta a jogar aquele jogo antigo',
              'Esse momento foi histórico'])[1 + floor(random() * 20)::int],
       dataH,
       online
FROM comentarios;

-- ---------------------------------------------------------------------
-- Doacao: 5000 comentários sorteados trazem uma doação.
-- A relação comentário-doação é 1:1, então seq_pg é sempre 1.
-- Status: ~10% recusado, ~45% recebido, ~45% lido
-- ---------------------------------------------------------------------
WITH sorteados AS (
    SELECT c.*
    FROM steam_do_bedo.Comentario c
    ORDER BY random()
    LIMIT 5000
),
doacoes AS (
    SELECT s.*, random() AS u_status
    FROM sorteados s
)
INSERT INTO steam_do_bedo.Doacao (nome_canal, nro_plataforma, titulo_video, dataH_video,
                                   nick_usuario, seq_comentario, seq_pg, valor, status)
SELECT nome_canal, nro_plataforma, titulo_video, dataH_video, nick_usuario, seq, 1,
       round((1 + 499 * random() ^ 3)::numeric, 2),
       CASE WHEN u_status < 0.10 THEN 'recusado'
            WHEN u_status < 0.55 THEN 'recebido'
            ELSE 'lido' END
FROM doacoes;

-- ---------------------------------------------------------------------
-- Especializações de Doacao (disjuntas), 1250 em cada.
-- As doações são numeradas pela chave e o resto da divisão por 4 define
-- a forma de pagamento: 0 BitCoin, 1 PayPal, 2 Cartão, 3 Mecanismo da plataforma
-- ---------------------------------------------------------------------
WITH doacoes AS (
    SELECT d.*,
           row_number() OVER (ORDER BY nome_canal, nro_plataforma, titulo_video,
                                       dataH_video, nick_usuario, seq_comentario) % 4 AS forma
    FROM steam_do_bedo.Doacao d
)
INSERT INTO steam_do_bedo.BitCoin (nome_canal, nro_plataforma, titulo_video, dataH_video,
                                    nick_usuario, seq_comentario, seq_doacao, TxID)
SELECT nome_canal, nro_plataforma, titulo_video, dataH_video, nick_usuario, seq_comentario, seq_pg,
       md5(random()::text) || md5(random()::text)  -- hash de 64 caracteres hexadecimais
FROM doacoes
WHERE forma = 0;

WITH doacoes AS (
    SELECT d.*,
           row_number() OVER (ORDER BY nome_canal, nro_plataforma, titulo_video,
                                       dataH_video, nick_usuario, seq_comentario) % 4 AS forma
    FROM steam_do_bedo.Doacao d
)
INSERT INTO steam_do_bedo.PayPal (nome_canal, nro_plataforma, titulo_video, dataH_video,
                                   nick_usuario, seq_comentario, seq_doacao, IdPayPal)
SELECT nome_canal, nro_plataforma, titulo_video, dataH_video, nick_usuario, seq_comentario, seq_pg,
       'PAYID-' || upper(substr(md5(random()::text), 1, 24))
FROM doacoes
WHERE forma = 1;

-- Números de cartão fictícios de 16 dígitos com o prefixo da bandeira
WITH doacoes AS (
    SELECT d.*,
           row_number() OVER (ORDER BY nome_canal, nro_plataforma, titulo_video,
                                       dataH_video, nick_usuario, seq_comentario) % 4 AS forma,
           1 + floor(random() * 4)::int AS b
    FROM steam_do_bedo.Doacao d
),
cartoes AS (
    SELECT d.*,
           (ARRAY['Visa', 'Mastercard', 'Elo', 'Hipercard'])[b] AS bandeira,
           (ARRAY['4', '5', '6362', '6062'])[b]                 AS prefixo
    FROM doacoes d
    WHERE forma = 2
)
INSERT INTO steam_do_bedo.CartaoCredito (nome_canal, nro_plataforma, titulo_video, dataH_video,
                                          nick_usuario, seq_comentario, seq_doacao, nro, bandeira)
SELECT nome_canal, nro_plataforma, titulo_video, dataH_video, nick_usuario, seq_comentario, seq_pg,
       prefixo || lpad(floor(random() * 10 ^ (16 - length(prefixo)))::bigint::text,
                       16 - length(prefixo), '0'),
       bandeira
FROM cartoes;

-- seq_plataforma é sequencial por (usuário, plataforma), em ordem cronológica
WITH doacoes AS (
    SELECT d.*,
           row_number() OVER (ORDER BY nome_canal, nro_plataforma, titulo_video,
                                       dataH_video, nick_usuario, seq_comentario) % 4 AS forma
    FROM steam_do_bedo.Doacao d
)
INSERT INTO steam_do_bedo.MecanismoPlat (nome_canal, nro_plataforma, titulo_video, dataH_video,
                                          nick_usuario, seq_comentario, seq_doacao, seq_plataforma)
SELECT nome_canal, nro_plataforma, titulo_video, dataH_video, nick_usuario, seq_comentario, seq_pg,
       row_number() OVER (PARTITION BY nick_usuario, nro_plataforma
                          ORDER BY dataH_video, nome_canal, titulo_video, seq_comentario)
FROM doacoes
WHERE forma = 3;

-- ---------------------------------------------------------------------
-- Patrocinio (somente vigentes): 0 a 3 empresas distintas por canal (~1750)
-- Valor em USD
-- ---------------------------------------------------------------------
WITH canais AS (
    SELECT nome, nro_plataforma,
           (ARRAY[0, 1, 1, 2, 3])[1 + floor(random() * 5)::int] AS qtd_patrocinadores
    FROM steam_do_bedo.Canal
)
INSERT INTO steam_do_bedo.Patrocinio (nro_empresa, nome_canal, nro_plataforma, valor)
SELECT e.nro, c.nome, c.nro_plataforma, round((200 + 49800 * random() ^ 3)::numeric, 2)
FROM canais c
CROSS JOIN LATERAL (
    SELECT nro
    FROM steam_do_bedo.Empresa
    ORDER BY random()
    LIMIT c.qtd_patrocinadores
) AS e;

-- ---------------------------------------------------------------------
-- Atributos derivados
-- ---------------------------------------------------------------------
UPDATE steam_do_bedo.Plataforma p
SET qtd_users = (SELECT count(*)
                 FROM steam_do_bedo.PlataformaUsuario pu
                 WHERE pu.nro_plataforma = p.nro);

UPDATE steam_do_bedo.Canal c
SET qtd_visualizacoes = COALESCE((SELECT sum(v.visu_total)
                                  FROM steam_do_bedo.Video v
                                  WHERE v.nome_canal = c.nome
                                    AND v.nro_plataforma = c.nro_plataforma), 0);

COMMIT;

-- ---------------------------------------------------------------------
-- Conferência do item mandatório 1: tuplas por tabela
-- ---------------------------------------------------------------------
SELECT tabela, tuplas, tuplas BETWEEN 1000 AND 10000 AS dentro_do_intervalo
FROM (
    SELECT 'Conversao' AS tabela, count(*) AS tuplas FROM steam_do_bedo.Conversao
    UNION ALL SELECT 'Pais',              count(*) FROM steam_do_bedo.Pais
    UNION ALL SELECT 'Empresa',           count(*) FROM steam_do_bedo.Empresa
    UNION ALL SELECT 'EmpresaPais',       count(*) FROM steam_do_bedo.EmpresaPais
    UNION ALL SELECT 'Plataforma',        count(*) FROM steam_do_bedo.Plataforma
    UNION ALL SELECT 'Usuario',           count(*) FROM steam_do_bedo.Usuario
    UNION ALL SELECT 'PlataformaUsuario', count(*) FROM steam_do_bedo.PlataformaUsuario
    UNION ALL SELECT 'StreamerPais',      count(*) FROM steam_do_bedo.StreamerPais
    UNION ALL SELECT 'Canal',             count(*) FROM steam_do_bedo.Canal
    UNION ALL SELECT 'NivelCanal',        count(*) FROM steam_do_bedo.NivelCanal
    UNION ALL SELECT 'Inscricao',         count(*) FROM steam_do_bedo.Inscricao
    UNION ALL SELECT 'Patrocinio',        count(*) FROM steam_do_bedo.Patrocinio
    UNION ALL SELECT 'Video',             count(*) FROM steam_do_bedo.Video
    UNION ALL SELECT 'Participa',         count(*) FROM steam_do_bedo.Participa
    UNION ALL SELECT 'Comentario',        count(*) FROM steam_do_bedo.Comentario
    UNION ALL SELECT 'Doacao',            count(*) FROM steam_do_bedo.Doacao
    UNION ALL SELECT 'BitCoin',           count(*) FROM steam_do_bedo.BitCoin
    UNION ALL SELECT 'PayPal',            count(*) FROM steam_do_bedo.PayPal
    UNION ALL SELECT 'CartaoCredito',     count(*) FROM steam_do_bedo.CartaoCredito
    UNION ALL SELECT 'MecanismoPlat',     count(*) FROM steam_do_bedo.MecanismoPlat
) AS contagem;
