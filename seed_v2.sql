-- =====================================================================
-- Projeto de Banco de Dados 2026/2 - Stream do Bedo
-- Script de carga v2 (seed_v2) - PostgreSQL 17
--
-- Este seed substitui o seed.sql; nunca execute os dois.
--
-- Ordem de execução exata (sempre sobre um schema recém-criado):
--   psql -U admin -d steam-do-bedo-db -f ddl.sql
--   psql -U admin -d steam-do-bedo-db -f seed_v2.sql
--
-- Premissas:
--   * O banco tem apenas o schema criado pelo ddl.sql e TODAS as tabelas
--     estão vazias. Nada de outro seed existe nem é lido.
--   * Logo no início o script confere se as 20 tabelas estão vazias e
--     aborta com RAISE EXCEPTION se encontrar qualquer linha. Assim, rodar
--     este arquivo de novo sem refazer o ddl.sql falha de forma controlada,
--     sem inserir nada.
--   * Não há DROP, CREATE TABLE, TRUNCATE, ALTER nem DELETE. Os únicos
--     UPDATE calculam atributos derivados (Plataforma.qtd_users e
--     Canal.qtd_visualizacoes) das linhas que este próprio script inseriu.
--   * Para recomeçar: rodar o ddl.sql de novo (ele recria o schema) e
--     depois este arquivo.
--
-- Como os dados são gerados:
--   * Cada tabela é populada só por literais (VALUES), por generate_series
--     ou por JOIN com tabelas que ESTE script já populou (garante as FKs).
--   * Chaves de identidade (Empresa.nro, Plataforma.nro, Canal.id_canal,
--     Video.id_video) nunca são assumidas por número fixo: são obtidas por
--     JOIN sobre o que foi inserido (pelo nome, ou pela ordem de inserção).
--   * setseed() fixa a sequência do random(): toda execução sobre o schema
--     recém-criado produz os mesmos dados.
--   * Tudo roda numa única transação. Qualquer erro (inclusive a checagem
--     de tabelas vazias e a checagem final de volume) desfaz a carga inteira.
--
-- Volume gerado (item mandatório 1: entre 1.000 e 10.000 tuplas por tabela):
--   Conversao 1000 | Pais 1000 | Empresa 1000 | EmpresaPais 1196
--   Plataforma 1000 | Usuario 4000 | PlataformaUsuario 7772
--   StreamerPais 1207 | Canal 1239 | NivelCanal 6195 | Inscricao 2034
--   Patrocinio 1340 | Video 5583 | Participa 5230 | Comentario 9500
--   Doacao 4750 | MecanismoPlat 1700 | CartaoCredito 1030
--   PayPal 1010 | BitCoin 1010
--
-- Realismo das proporções (onde o item 1 permite):
--   * Plataformas reais com tamanhos diferentes (YouTube e Twitch concentram
--     a maior parte dos usuários); usuários com 1 a 3 contas.
--   * Popularidade por canal: poucos canais concentram as visualizações,
--     os membros e os patrocínios.
--   * ~36% dos usuários são membros, quase todos de 1 canal só.
--   * ~40% dos canais têm patrocínio, concentrado em poucas marcas.
--   * Doações: o mecanismo da plataforma é a forma mais usada, com valores
--     baixos. A taxa de 50% de comentários com doação continua acima da
--     real, porque é imposta pelo piso de 1.000 linhas por especialização.
-- =====================================================================

-- Para no primeiro erro: sem isto o psql seguiria executando os comandos
-- seguintes depois da falha da checagem de tabelas vazias.
\set ON_ERROR_STOP on

SET search_path TO steam_do_bedo;

BEGIN;

-- ---------------------------------------------------------------------
-- Falha cedo: o schema precisa existir e todas as tabelas precisam estar
-- vazias. Qualquer linha indica banco já populado (por outro seed ou por
-- uma execução anterior deste arquivo).
-- ---------------------------------------------------------------------
DO $$
DECLARE
    tabelas CONSTANT text[] := ARRAY[
        'conversao', 'pais', 'empresa', 'empresapais', 'plataforma', 'usuario',
        'plataformausuario', 'streamerpais', 'canal', 'nivelcanal', 'inscricao',
        'patrocinio', 'video', 'participa', 'comentario', 'doacao',
        'bitcoin', 'paypal', 'cartaocredito', 'mecanismoplat'];
    t         text;
    qtd       bigint;
    ocupadas  text[] := '{}';
BEGIN
    IF to_regnamespace('steam_do_bedo') IS NULL THEN
        RAISE EXCEPTION 'seed_v2: schema steam_do_bedo não existe. Rode o ddl.sql antes deste seed.';
    END IF;

    FOREACH t IN ARRAY tabelas LOOP
        IF to_regclass('steam_do_bedo.' || t) IS NULL THEN
            RAISE EXCEPTION 'seed_v2: tabela steam_do_bedo.% não existe. Rode o ddl.sql antes deste seed.', t;
        END IF;
        EXECUTE format('SELECT count(*) FROM steam_do_bedo.%I', t) INTO qtd;
        RAISE NOTICE 'seed_v2: % = % linha(s) antes da carga', t, qtd;
        IF qtd > 0 THEN
            ocupadas := ocupadas || format('%s (%s)', t, qtd);
        END IF;
    END LOOP;

    IF cardinality(ocupadas) > 0 THEN
        RAISE EXCEPTION 'seed_v2 abortado: o banco não está vazio. Tabelas com linhas: %',
                        array_to_string(ocupadas, ', ')
            USING HINT = 'Este seed só roda sobre um schema recém-criado. Rode o ddl.sql de novo e depois o seed_v2.sql. Nada foi inserido.';
    END IF;
END
$$;

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

-- Cada país fictício usa uma moeda fictícia diferente (inseridas acima)
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
-- Empresas reais: país conhecido. Fictícias: ~45% Brasil, ~40% outro país
-- real, ~15% país fictício. A empresa é localizada pelo nome (JOIN), nunca
-- por um nro fixo.
-- ---------------------------------------------------------------------
WITH paises AS (
    SELECT ddi,
           length(ddi) <= 3                                               AS real,
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
-- Fundadora e responsável das reais são obtidas pelo nome da empresa.
-- O sufixo numérico do nome das fictícias garante pares
-- (nome, empresa_fund) distintos (DEC-006).
-- qtd_users (derivado) é calculado ao final do script.
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
-- País de residência: ~45% Brasil, ~40% outro país real, ~15% país fictício.
-- email deriva do nick (único). telefone termina com o número do usuário
-- (4 dígitos), o que garante a restrição UNIQUE de telefone (DEC-011).
-- ---------------------------------------------------------------------
WITH paises AS (
    SELECT ddi,
           length(ddi) <= 3                                               AS real,
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
       ddi || lpad(floor(random() * 100000)::int::text, 5, '0') || lpad(i::text, 4, '0'),
       (ARRAY['Rua das Flores', 'Avenida Brasil', 'Rua São João', 'Avenida Paulista',
              'Rua da Praia', 'Rua Sete de Setembro', 'Avenida Atlântica',
              'Rua XV de Novembro', 'Rua do Sol', 'Avenida Central'])[1 + floor(random() * 10)::int]
           || ', ' || (1 + floor(random() * 2000)::int)
           || ' - CP ' || lpad(floor(random() * 100000000)::bigint::text, 8, '0'),
       ddi
FROM residencia
ORDER BY i;

-- ---------------------------------------------------------------------
-- PlataformaUsuario (~7.600): cada usuário tem de 1 a 3 contas.
--   * Conta principal: uma das 10 plataformas reais, sorteada com peso pela
--     participação de mercado. YouTube e Twitch concentram mais da metade
--     dos usuários e o Mixer (encerrado em 2020) fica com ~1%.
--   * ~40% sorteiam uma segunda plataforma real com os mesmos pesos. Se cair
--     na mesma da principal, o usuário fica sem a segunda (UNION descarta).
--   * ~60% têm conta numa plataforma fictícia. random()^2 concentra os
--     usuários nas primeiras fictícias; a cauda fica com poucos ou nenhum.
--   As 10 primeiras plataformas na ordem de inserção (nro) são as reais, na
--   mesma ordem da lista de pesos, que é decrescente: entre as contas reais
--   de um usuário, a de menor nro é a da maior plataforma.
--   nro_usuario é sequencial dentro de cada plataforma.
-- ---------------------------------------------------------------------
WITH plataformas AS (
    SELECT nro, row_number() OVER (ORDER BY nro) AS r
    FROM steam_do_bedo.Plataforma
),
-- Participação aproximada (%) de cada plataforma real; soma 100
pesos AS (
    SELECT r,
           (sum(peso) OVER (ORDER BY r) - peso) / 100.0 AS ini,
           sum(peso) OVER (ORDER BY r) / 100.0          AS fim
    FROM (VALUES (1, 34), (2, 24), (3, 10), (4, 9), (5, 8),
                 (6, 5),  (7, 4),  (8, 3),  (9, 2), (10, 1)) AS w(r, peso)
),
sorteio AS (
    SELECT nick,
           random()        AS u_principal,
           random() < 0.40 AS tem_segunda,
           random()        AS u_segunda,
           random() < 0.60 AS tem_ficticia,
           random()        AS u_ficticia
    FROM steam_do_bedo.Usuario
),
contas AS (
    SELECT s.nick, w.r
    FROM sorteio s
    JOIN pesos w ON s.u_principal >= w.ini AND s.u_principal < w.fim
    UNION
    SELECT s.nick, w.r
    FROM sorteio s
    JOIN pesos w ON s.u_segunda >= w.ini AND s.u_segunda < w.fim
    WHERE s.tem_segunda
    UNION
    SELECT nick, 11 + floor(990 * u_ficticia ^ 2)::int
    FROM sorteio
    WHERE tem_ficticia
)
INSERT INTO steam_do_bedo.PlataformaUsuario (nro_plataforma, nick_usuario, nro_usuario)
SELECT p.nro, c.nick, row_number() OVER (PARTITION BY p.nro ORDER BY c.nick)
FROM contas c
JOIN plataformas p ON p.r = c.r;

-- ---------------------------------------------------------------------
-- StreamerPais: 1000 usuários sorteados são streamers; passaporte do país
-- de residência + segundo passaporte (Brasil ou Portugal) para ~20%
-- ---------------------------------------------------------------------
-- Obs.: um random() no SELECT idêntico ao do ORDER BY é tratado pelo
-- PostgreSQL como o MESMO valor; por isso os demais sorteios ficam numa
-- CTE separada da ordenação (mesmo cuidado em Doacao).
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
-- Canal (~1200): todo streamer tem um canal principal na maior plataforma
-- em que tem conta (a de menor nro, sempre real) e, em cada uma das outras
-- contas, 25% de chance de um segundo canal.
-- id_canal é gerado pela identidade (DEC-014); daqui em diante é obtido
-- por JOIN com Canal, nunca por número fixo.
-- qtd_visualizacoes (derivado) é calculado ao final do script.
-- ---------------------------------------------------------------------
WITH plataformas AS (
    SELECT nro, row_number() OVER (ORDER BY nro) <= 10 AS real
    FROM steam_do_bedo.Plataforma
),
contas AS (
    SELECT pu.nick_usuario AS nick, pu.nro_plataforma, p.real,
           row_number() OVER (PARTITION BY pu.nick_usuario
                              ORDER BY pu.nro_plataforma) = 1 AS principal,
           random() AS u_canal, random() AS u_tipo
    FROM steam_do_bedo.PlataformaUsuario pu
    JOIN plataformas p ON p.nro = pu.nro_plataforma
    WHERE pu.nick_usuario IN (SELECT nick_streamer FROM steam_do_bedo.StreamerPais)
    ORDER BY pu.nick_usuario, pu.nro_plataforma
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
WHERE principal OR u_canal < 0.25;

-- ---------------------------------------------------------------------
-- NivelCanal: 5 níveis por canal (~6250)
-- Cada canal usa um dos 5 temas de nomes e um multiplicador próprio sobre
-- a tabela base de valores mensais, de modo que o valor cresce com o nível.
-- ---------------------------------------------------------------------
WITH canais AS (
    SELECT id_canal, nome,
           1 + floor(random() * 5)::int AS tema,
           (0.5 + random())::numeric    AS multiplicador
    FROM steam_do_bedo.Canal
)
INSERT INTO steam_do_bedo.NivelCanal (id_canal, nivel, valor, gif)
SELECT c.id_canal,
       (ARRAY[
           ['Bronze',  'Prata',    'Ouro',     'Platina',  'Diamante'],
           ['Recruta', 'Soldado',  'Sargento', 'Capitão',  'General'],
           ['Fã',      'Apoiador', 'Parceiro', 'VIP',      'Lenda'],
           ['Bit',     'Byte',     'Kilobyte', 'Megabyte', 'Gigabyte'],
           ['Novato',  'Aprendiz', 'Veterano', 'Mestre',   'Lendário']
       ])[c.tema][k],
       round((ARRAY[1.99, 4.99, 9.99, 24.99, 49.99])[k] * c.multiplicador, 2),
       'gifs/' || regexp_replace(lower(c.nome), '[^a-z0-9]+', '_', 'g')
               || '_' || c.id_canal || '_nivel' || k || '.gif'
FROM canais c
CROSS JOIN generate_series(1, 5) AS k;

-- ---------------------------------------------------------------------
-- Video: 3 a 6 vídeos por canal (~5500); 70% seguem o tema do canal.
-- Visualizações com distribuição bem assimétrica: cada canal tem uma
-- popularidade própria (poucos canais grandes, muitos pequenos; canais em
-- plataformas fictícias, de cortes, alcançam menos), e dentro do canal
-- poucos vídeos viralizam.
-- O sufixo "#k" no título garante UNIQUE (id_canal, titulo, dataH) (DEC-015).
-- ---------------------------------------------------------------------
WITH temas AS (
    SELECT ARRAY['Minecraft', 'Fortnite', 'League of Legends', 'Valorant', 'Counter-Strike 2',
                 'GTA V', 'Elden Ring', 'Free Fire', 'Roblox', 'Dota 2', 'Apex Legends',
                 'Call of Duty', 'EA Sports FC', 'Hollow Knight', 'Stardew Valley',
                 'The Sims 4', 'Rocket League', 'Pokémon', 'Just Chatting', 'Speedrun'] AS lista
),
plataformas AS (
    SELECT nro, row_number() OVER (ORDER BY nro) <= 10 AS real
    FROM steam_do_bedo.Plataforma
),
canais AS (
    SELECT c.id_canal, c.data,
           t.lista[1 + floor(random() * 20)::int] AS tema_canal,
           3 + floor(random() * 4)::int            AS qtd_videos,
           (0.01 + 0.99 * random() ^ 3)
               * CASE WHEN p.real THEN 1 ELSE 0.3 END AS popularidade
    FROM steam_do_bedo.Canal c
    JOIN plataformas p ON p.nro = c.nro_plataforma
    CROSS JOIN temas t
),
videos AS (
    SELECT c.id_canal, k,
           CASE WHEN random() < 0.7 THEN c.tema_canal
                ELSE t.lista[1 + floor(random() * 20)::int] END                AS tema,
           date_trunc('second', c.data + k * INTERVAL '20 days'
                                       + random() * INTERVAL '19 days')        AS dataH,
           (50 + floor(1500000 * c.popularidade * random() ^ 2))::bigint       AS visu_total
    FROM canais c
    CROSS JOIN temas t
    CROSS JOIN LATERAL generate_series(1, c.qtd_videos) AS k
)
INSERT INTO steam_do_bedo.Video (id_canal, titulo, dataH, tema, duracao, visu_simul, visu_total)
SELECT id_canal,
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
FROM videos
ORDER BY id_canal, k;

-- ---------------------------------------------------------------------
-- Inscricao (~2000): só membros vigentes, e a maioria dos usuários não é
-- membro de canal nenhum.
--   * ~37% dos usuários são membros: 70% deles de 1 canal, 20% de 2 e
--     10% de 3.
--   * O membro escolhe entre os canais das plataformas onde tem conta,
--     nunca o próprio, com chance proporcional às visualizações do canal
--     (amostragem ponderada sem reposição, chave -ln(u)/peso): os canais
--     grandes concentram os membros.
--   * Níveis mais baratos são mais frequentes.
-- data_inscricao (DEC-007) é informada explicitamente, entre a criação do
-- canal e 2026-10-31, para não depender de CURRENT_DATE.
-- ---------------------------------------------------------------------
WITH niveis AS (
    SELECT id_canal, nivel,
           row_number() OVER (PARTITION BY id_canal ORDER BY valor, nivel) AS ordem
    FROM steam_do_bedo.NivelCanal
),
canais AS (
    SELECT c.id_canal, c.nro_plataforma, c.nick_streamer, c.data::date AS data_canal,
           sum(v.visu_total)::float8 AS peso
    FROM steam_do_bedo.Canal c
    JOIN steam_do_bedo.Video v ON v.id_canal = c.id_canal
    GROUP BY c.id_canal
),
membros AS (
    SELECT nick,
           (ARRAY[1, 1, 1, 1, 1, 1, 1, 2, 2, 3])[1 + floor(random() * 10)::int] AS qtd_canais
    FROM steam_do_bedo.Usuario
    WHERE random() < 0.37
),
pares AS (
    SELECT m.nick, m.qtd_canais, ca.id_canal, ca.data_canal,
           -ln(1 - random()) / ca.peso AS chave,
           random() AS u_nivel,
           random() AS u_data
    FROM membros m
    JOIN steam_do_bedo.PlataformaUsuario pu ON pu.nick_usuario = m.nick
    JOIN canais ca ON ca.nro_plataforma = pu.nro_plataforma
                  AND ca.nick_streamer <> m.nick
),
candidatos AS (
    SELECT pares.*,
           row_number() OVER (PARTITION BY nick ORDER BY chave, id_canal) AS sorteio
    FROM pares
)
INSERT INTO steam_do_bedo.Inscricao (id_canal, nick_membro, nivel, data_inscricao)
SELECT ca.id_canal, ca.nick, n.nivel,
       ca.data_canal + floor(ca.u_data * (DATE '2026-10-31' - ca.data_canal))::int
FROM candidatos ca
JOIN niveis n ON n.id_canal = ca.id_canal
             AND n.ordem = 1 + floor(5 * ca.u_nivel ^ 2)::int
WHERE ca.sorteio <= ca.qtd_canais;

-- ---------------------------------------------------------------------
-- Participa: 0 a 2 streamers convidados por vídeo (~5000).
-- O dono do canal não é repetido aqui (já é derivável de Canal) e os
-- convidados precisam ter conta na plataforma do vídeo.
-- ---------------------------------------------------------------------
WITH videos AS (
    SELECT v.id_video, c.nro_plataforma,
           c.nick_streamer          AS dono,
           floor(random() * 3)::int AS qtd_convidados
    FROM steam_do_bedo.Video v
    JOIN steam_do_bedo.Canal c ON c.id_canal = v.id_canal
),
candidatos AS (
    SELECT v.id_video, v.qtd_convidados, pu.nick_usuario,
           row_number() OVER (PARTITION BY v.id_video ORDER BY random()) AS sorteio
    FROM videos v
    JOIN steam_do_bedo.PlataformaUsuario pu ON pu.nro_plataforma = v.nro_plataforma
                                            AND pu.nick_usuario <> v.dono
    WHERE pu.nick_usuario IN (SELECT nick_streamer FROM steam_do_bedo.StreamerPais)
)
INSERT INTO steam_do_bedo.Participa (id_video, nick_streamer)
SELECT id_video, nick_usuario
FROM candidatos
WHERE sorteio <= qtd_convidados;

-- ---------------------------------------------------------------------
-- Comentario: 9500, concentrados nos vídeos mais vistos.
-- O autor tem conta na plataforma do vídeo; ~65% são online (durante o
-- vídeo) e ~35% offline (até 60 dias depois). seq é sequencial por vídeo,
-- em ordem cronológica, e informado explicitamente (DEC-017).
-- ---------------------------------------------------------------------
WITH videos AS (
    SELECT v.id_video, v.dataH, v.duracao, c.nro_plataforma,
           row_number() OVER (ORDER BY v.visu_total DESC, v.id_video) - 1 AS idx
    FROM steam_do_bedo.Video v
    JOIN steam_do_bedo.Canal c ON c.id_canal = v.id_canal
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
    FROM generate_series(1, 9500) AS i
),
comentarios AS (
    SELECT v.id_video, ct.nick_usuario, s.i, s.online,
           date_trunc('second',
               CASE WHEN s.online THEN v.dataH + v.duracao * s.u_tempo
                    ELSE v.dataH + v.duracao + INTERVAL '60 days' * s.u_tempo END) AS dataH
    FROM sorteio s
    JOIN videos v  ON v.idx = s.idx_video
    JOIN contas ct ON ct.nro_plataforma = v.nro_plataforma
                  AND ct.r = 1 + floor(s.u_autor * ct.n)
)
INSERT INTO steam_do_bedo.Comentario (id_video, seq, nick_usuario, texto, dataH, coment_on)
SELECT id_video,
       row_number() OVER (PARTITION BY id_video ORDER BY dataH, i),
       nick_usuario,
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
-- Doacao: 4750 comentários sorteados trazem uma doação (50%).
-- A taxa real fica perto de 1% a 5%, mas o item 1 impõe o piso: as 4
-- especializações precisam de >= 1000 linhas cada, então Doacao >= 4000,
-- e Comentario não passa de 10000.
-- O sorteio favorece comentários online (doação feita durante a live).
-- A relação comentário-doação é 1:1, então seq_pg é sempre 1.
--
-- A forma de pagamento é decidida aqui pela posição numa ordem
-- determinística (online primeiro, depois md5 da chave) e recalculada igual
-- nas inserções das especializações:
--      1..1700 MecanismoPlat (~36%, Super Chat e afins, só comentários online)
--   1701..2730 CartaoCredito
--   2731..3740 PayPal
--   3741..4750 BitCoin
-- Valores em USD: o mecanismo da plataforma concentra doações pequenas
-- (mediana perto de US$ 7); BitCoin concentra as grandes.
-- Status: ~10% recusado, ~45% recebido, ~45% lido.
-- ---------------------------------------------------------------------
WITH sorteados AS (
    SELECT c.id_video, c.seq, c.coment_on
    FROM steam_do_bedo.Comentario c
    ORDER BY random() * CASE WHEN c.coment_on THEN 1 ELSE 3 END
    LIMIT 4750
),
doacoes AS (
    SELECT s.*,
           row_number() OVER (ORDER BY s.coment_on DESC,
                                       md5(s.id_video::text || '/' || s.seq::text),
                                       s.id_video, s.seq) AS pos
    FROM sorteados s
),
sorteio AS (
    SELECT d.*, random() AS u_valor, random() AS u_status
    FROM doacoes d
)
INSERT INTO steam_do_bedo.Doacao (id_video, seq_comentario, seq_pg, valor, status)
SELECT id_video, seq, 1,
       round((CASE WHEN pos <= 1700 THEN 1  + 99  * u_valor ^ 4   -- MecanismoPlat
                   WHEN pos <= 2730 THEN 2  + 298 * u_valor ^ 3   -- CartaoCredito
                   WHEN pos <= 3740 THEN 2  + 198 * u_valor ^ 3   -- PayPal
                   ELSE                  10 + 990 * u_valor ^ 3   -- BitCoin
              END)::numeric, 2),
       CASE WHEN u_status < 0.10 THEN 'recusado'
            WHEN u_status < 0.55 THEN 'recebido'
            ELSE 'lido' END
FROM sorteio;

-- ---------------------------------------------------------------------
-- Especializações de Doacao (disjuntas). Cada inserção recalcula a mesma
-- posição usada acima e pega a sua faixa.
-- ---------------------------------------------------------------------
WITH doacoes AS (
    SELECT d.*,
           row_number() OVER (ORDER BY c.coment_on DESC,
                                       md5(d.id_video::text || '/' || d.seq_comentario::text),
                                       d.id_video, d.seq_comentario) AS pos
    FROM steam_do_bedo.Doacao d
    JOIN steam_do_bedo.Comentario c ON c.id_video = d.id_video AND c.seq = d.seq_comentario
)
INSERT INTO steam_do_bedo.BitCoin (id_video, seq_comentario, seq_doacao, TxID)
SELECT id_video, seq_comentario, seq_pg,
       md5(random()::text) || md5(random()::text)  -- hash de 64 caracteres hexadecimais
FROM doacoes
WHERE pos > 3740;

WITH doacoes AS (
    SELECT d.*,
           row_number() OVER (ORDER BY c.coment_on DESC,
                                       md5(d.id_video::text || '/' || d.seq_comentario::text),
                                       d.id_video, d.seq_comentario) AS pos
    FROM steam_do_bedo.Doacao d
    JOIN steam_do_bedo.Comentario c ON c.id_video = d.id_video AND c.seq = d.seq_comentario
)
INSERT INTO steam_do_bedo.PayPal (id_video, seq_comentario, seq_doacao, IdPayPal)
SELECT id_video, seq_comentario, seq_pg,
       'PAYID-' || upper(substr(md5(random()::text), 1, 24))
FROM doacoes
WHERE pos BETWEEN 2731 AND 3740;

-- Números de cartão fictícios de 16 dígitos com o prefixo da bandeira
WITH doacoes AS (
    SELECT d.*,
           row_number() OVER (ORDER BY c.coment_on DESC,
                                       md5(d.id_video::text || '/' || d.seq_comentario::text),
                                       d.id_video, d.seq_comentario) AS pos,
           1 + floor(random() * 4)::int AS b
    FROM steam_do_bedo.Doacao d
    JOIN steam_do_bedo.Comentario c ON c.id_video = d.id_video AND c.seq = d.seq_comentario
),
cartoes AS (
    SELECT d.*,
           (ARRAY['Visa', 'Mastercard', 'Elo', 'Hipercard'])[b] AS bandeira,
           (ARRAY['4', '5', '6362', '6062'])[b]                 AS prefixo
    FROM doacoes d
    WHERE pos BETWEEN 1701 AND 2730
)
INSERT INTO steam_do_bedo.CartaoCredito (id_video, seq_comentario, seq_doacao, nro, bandeira)
SELECT id_video, seq_comentario, seq_pg,
       prefixo || lpad(floor(random() * 10 ^ (16 - length(prefixo)))::bigint::text,
                       16 - length(prefixo), '0'),
       bandeira
FROM cartoes;

-- seq_plataforma é sequencial por (usuário doador, plataforma), em ordem
-- cronológica do comentário. Usuário e plataforma vêm de Comentario e Canal.
WITH doacoes AS (
    SELECT d.*,
           row_number() OVER (ORDER BY c.coment_on DESC,
                                       md5(d.id_video::text || '/' || d.seq_comentario::text),
                                       d.id_video, d.seq_comentario) AS pos
    FROM steam_do_bedo.Doacao d
    JOIN steam_do_bedo.Comentario c ON c.id_video = d.id_video AND c.seq = d.seq_comentario
)
INSERT INTO steam_do_bedo.MecanismoPlat (id_video, seq_comentario, seq_doacao, seq_plataforma)
SELECT d.id_video, d.seq_comentario, d.seq_pg,
       row_number() OVER (PARTITION BY co.nick_usuario, ca.nro_plataforma
                          ORDER BY co.dataH, d.id_video, d.seq_comentario)
FROM doacoes d
JOIN steam_do_bedo.Comentario co ON co.id_video = d.id_video AND co.seq = d.seq_comentario
JOIN steam_do_bedo.Video v       ON v.id_video = d.id_video
JOIN steam_do_bedo.Canal ca      ON ca.id_canal = v.id_canal
WHERE d.pos <= 1700;

-- ---------------------------------------------------------------------
-- Patrocinio (~1300, somente vigentes): patrocínio vai para os canais grandes
-- e se concentra em poucas marcas.
--   * Canais ordenados por visualizações: os 10% maiores têm 5 a 7
--     patrocinadores, os 20% seguintes 1 a 3, os 30% seguintes 30% de
--     chance de 1, e os 40% menores nenhum.
--   * Empresas donas (fundadora ou responsável) das plataformas reais não
--     patrocinam canais. As marcas reais de jogos e periféricos têm peso
--     0,5 cada; as fictícias, peso 1/posição. Sorteio ponderado sem
--     reposição (chave -ln(u)/peso): poucas marcas aparecem em muitos canais.
--   * Valor em USD proporcional ao porte do canal.
-- ---------------------------------------------------------------------
WITH reais AS (
    SELECT empresa_fund AS nro FROM steam_do_bedo.Plataforma
    WHERE nro IN (SELECT nro FROM steam_do_bedo.Plataforma ORDER BY nro LIMIT 10)
    UNION
    SELECT empresa_resp FROM steam_do_bedo.Plataforma
    WHERE nro IN (SELECT nro FROM steam_do_bedo.Plataforma ORDER BY nro LIMIT 10)
),
empresas AS (
    SELECT nro,
           CASE WHEN marca_real THEN 0.5
                ELSE 1.0 / row_number() OVER (PARTITION BY marca_real ORDER BY nro) END AS peso
    FROM (
        SELECT e.nro,
               e.nome IN ('Amazon.com Inc.', 'Sony Group Corporation', 'Nintendo Co. Ltd.',
                          'Riot Games Inc.', 'Valve Corporation', 'Epic Games Inc.',
                          'Garena Online Pte. Ltd.', 'Ubisoft Entertainment SA', 'Razer Inc.',
                          'Logitech International SA', 'KaBuM! Comércio Eletrônico S.A.',
                          'LOUD Esports Ltda.') AS marca_real
        FROM steam_do_bedo.Empresa e
        WHERE e.nro NOT IN (SELECT nro FROM reais)
    ) AS x
),
canais AS (
    SELECT c.id_canal,
           percent_rank() OVER (ORDER BY sum(v.visu_total) DESC, c.id_canal) AS faixa
    FROM steam_do_bedo.Canal c
    JOIN steam_do_bedo.Video v ON v.id_canal = c.id_canal
    GROUP BY c.id_canal
),
cotas AS (
    SELECT id_canal, faixa,
           CASE WHEN faixa < 0.10 THEN 5 + floor(random() * 3)::int
                WHEN faixa < 0.30 THEN 1 + floor(random() * 3)::int
                WHEN faixa < 0.60 THEN (random() < 0.30)::int
                ELSE 0 END AS qtd_patrocinadores
    FROM canais
)
INSERT INTO steam_do_bedo.Patrocinio (nro_empresa, id_canal, valor)
SELECT e.nro, c.id_canal,
       round((CASE WHEN c.faixa < 0.10 THEN 5000 + 45000 * random() ^ 2
                   WHEN c.faixa < 0.30 THEN 1000 +  9000 * random() ^ 2
                   ELSE                      200 +  1800 * random() ^ 2
              END)::numeric, 2)
FROM cotas c
CROSS JOIN LATERAL (
    -- "0 * c.id_canal" amarra a ordenação ao canal: sem isso o PostgreSQL
    -- pode reaproveitar a ordem já calculada e repetir as mesmas empresas
    SELECT em.nro
    FROM empresas em
    ORDER BY -ln(1 - random()) / em.peso + 0 * c.id_canal, em.nro
    LIMIT c.qtd_patrocinadores
) AS e;

-- ---------------------------------------------------------------------
-- Atributos derivados (sobre as linhas que este script inseriu)
-- ---------------------------------------------------------------------
UPDATE steam_do_bedo.Plataforma p
SET qtd_users = (SELECT count(*)
                 FROM steam_do_bedo.PlataformaUsuario pu
                 WHERE pu.nro_plataforma = p.nro);

UPDATE steam_do_bedo.Canal c
SET qtd_visualizacoes = COALESCE((SELECT sum(v.visu_total)
                                  FROM steam_do_bedo.Video v
                                  WHERE v.id_canal = c.id_canal), 0);

-- ---------------------------------------------------------------------
-- Checagem final do item mandatório 1, ainda dentro da transação:
-- se alguma tabela ficar fora de 1.000..10.000, a carga inteira é desfeita.
-- ---------------------------------------------------------------------
DO $$
DECLARE
    tabelas CONSTANT text[] := ARRAY[
        'conversao', 'pais', 'empresa', 'empresapais', 'plataforma', 'usuario',
        'plataformausuario', 'streamerpais', 'canal', 'nivelcanal', 'inscricao',
        'patrocinio', 'video', 'participa', 'comentario', 'doacao',
        'bitcoin', 'paypal', 'cartaocredito', 'mecanismoplat'];
    t     text;
    qtd   bigint;
    fora  text[] := '{}';
BEGIN
    FOREACH t IN ARRAY tabelas LOOP
        EXECUTE format('SELECT count(*) FROM steam_do_bedo.%I', t) INTO qtd;
        IF qtd NOT BETWEEN 1000 AND 10000 THEN
            fora := fora || format('%s (%s)', t, qtd);
        END IF;
    END LOOP;

    IF cardinality(fora) > 0 THEN
        RAISE EXCEPTION 'seed_v2 abortado: tabelas fora do intervalo 1.000..10.000: %',
                        array_to_string(fora, ', ');
    END IF;
END
$$;

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
