-- =====================================================================
-- Projeto de Banco de Dados 2026/2 - Stream do Bedo
-- Arquivo 2/6: carga de dados (seed v3) - PostgreSQL 17
--
-- O que faz: popula as 20 tabelas do zero, com dados artificiais em
-- distribuições desbalanceadas e correlacionadas, coerentes com o cenário
-- de volumetria da DEC-020 (streaming de jogos com vídeo longo E curto).
-- É a terceira versão da carga (seed v3); as anteriores estão na tag v1.1.0.
--
-- Ordem de execução (DEC-030):
--   psql -v ON_ERROR_STOP=1 -d <banco> -f ddl.sql
--   psql -v ON_ERROR_STOP=1 -d <banco> -f seed.sql            (escala 1)
--   psql -v ON_ERROR_STOP=1 -d <banco> -v escala=0.1 -f seed.sql  (teste rápido)
--   depois: views.sql, functions.sql, triggers.sql, tests.sql
--
-- DECs implementadas: 019 a 027 (o seed obedece às mesmas regras dos
-- triggers, que só são criados depois da carga) e 031 (volumes).
--
-- Escala (variável psql "escala", padrão 1). Volumes aproximados:
--   tabela              escala 1     de onde vem
--   Conversao           154          moedas ISO 4217 reais (fixo)
--   Pais                199          países reais (fixo)
--   Empresa             3.000        ~70 reais + fictícias (fixo)
--   Plataforma          28           plataformas reais (fixo)
--   Usuario             500 mil      500.000 × escala
--   PlataformaUsuario   ~880 mil     1 a 5 contas por usuário
--   StreamerPais        ~26 mil      5% dos usuários são streamers
--   Canal               ~40 mil      1 canal por conta de streamer (60% das extras)
--   NivelCanal          ~110 mil     5 níveis em ~55% dos canais
--   Inscricao           ~600 mil     600.000 × escala, concentrada nos canais populares
--   Patrocinio          ~12 mil      concentrado nos canais populares
--   Video               ~1,3 mi      cauda longa por canal; curtos são muitos
--   Participa           ~150 mil     convidados em ~20% dos vídeos longos
--   Comentario          5 mi         5.000.000 × escala, cauda longa por vídeo
--   Doacao              ~2%          dos comentários (5% online, 1% offline)
--   BitCoin/PayPal/CartaoCredito/MecanismoPlat: partição disjunta de Doacao
-- O professor autorizou tabelas de referência abaixo de 1.000 linhas e
-- pediu o máximo de dados possível nas grandes (DEC-031, consulta 04:09).
--
-- Garantias:
--   * Parte de banco virgem: aborta se alguma tabela tiver linhas.
--   * ON_ERROR_STOP e uma transação só: qualquer erro desfaz tudo.
--   * Reprodutível: setseed(0.42), sem paralelismo e fuso UTC. A exceção
--     são os UUIDs dos vídeos, gerados pela função nativa gen_random_uuid(),
--     que não obedece ao setseed. Por isso nenhum sorteio depende da ordem
--     dos UUIDs: os vídeos são percorridos em ordem de (canal, número do
--     vídeo) e os comentários em ordem de (data, canal, número do vídeo),
--     que são as mesmas a cada carga. Os volumes, nomes, valores e
--     distribuições se repetem; mudam só os UUIDs e o que deriva deles
--     (TxID, IdPayPal e número do cartão). Conferido com duas cargas
--     seguidas: dados idênticos, exceto os UUIDs.
--   * Inserção por conjunto (generate_series, JOIN, LATERAL); nenhum laço
--     linha a linha.
--   * Chaves de identidade (Empresa.nro, Plataforma.nro, Usuario.id_usuario,
--     Canal.id_canal) nunca são números fixos: são obtidas por JOIN pela
--     chave natural (nome, nick, (nome, nro_plataforma)).
--   * Atributos derivados (Plataforma.qtd_users, Canal.qtd_visualizacoes)
--     calculados no próprio INSERT, a partir de tabelas temporárias de
--     preparação; não há UPDATE final (que deixaria tuplas mortas).
--   * Obedece às regras dos triggers (DEC-027): seq contínuo por vídeo e
--     por comentário, seq_plataforma contínuo por (usuário, plataforma),
--     no máximo 5 níveis por canal, especialização disjunta e total, datas
--     em ordem (inclusive o Mixer, encerrado em 2020-07-22), dono do canal
--     streamer e com conta na plataforma, doação em USD (T11).
--   * Ao fim, uma conferência de sanidade aborta a transação se qualquer
--     regra acima falhar.
--
-- Cuidado: usa tabelas e functions temporárias (pg_temp), que somem no
-- COMMIT. Cada tabela temporária recebe ANALYZE logo depois de criada: o
-- autovacuum nunca analisa tabela temporária, e sem estatística o
-- planejador escolhe nested loop com varredura completa nos JOINs de
-- sorteio (a carga travava em Inscricao). Não cria nem altera nada no schema steam_do_bedo além das linhas.
-- O VACUUM ANALYZE do fim roda fora da transação (exigência do comando).
-- =====================================================================

\set ON_ERROR_STOP on
\if :{?escala}
\else
\set escala 1
\endif

SET search_path TO steam_do_bedo;

\echo seed: escala = :escala
\timing on

BEGIN;

-- Fuso fixo: as datas geradas não dependem da configuração do servidor.
SET LOCAL timezone = 'UTC';
-- Workers paralelos têm gerador aleatório próprio: sem paralelismo, a
-- sequência do random() é a mesma a cada execução.
SET LOCAL max_parallel_workers_per_gather = 0;
-- Ordenações e hashes grandes (5 mi de comentários) cabem em memória.
SET LOCAL work_mem = '128MB';
-- JIT só acrescentaria segundos de compilação a consultas de carga.
SET LOCAL jit = off;
-- Sem Memoize: o planejador guardaria em cache o resultado de uma
-- subconsulta LATERAL com random() pela chave de entrada (por exemplo, o
-- número da conta ou o seq do comentário) e repetiria o mesmo sorteio para
-- todas as linhas com a mesma chave. Achado na validação: só 0,39% dos
-- comentários ficavam com doação, e todos os vídeos tinham o mesmo
-- convidado. Cada sorteio deste arquivo depende de random() por linha.
SET LOCAL enable_memoize = off;

-- ---------------------------------------------------------------------
-- Falha cedo: o schema precisa existir, as 20 tabelas precisam estar
-- vazias e a escala precisa ser um número entre 0,001 e 4.
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
        RAISE EXCEPTION 'seed: schema steam_do_bedo não existe. Rode o ddl.sql antes deste seed.';
    END IF;
    FOREACH t IN ARRAY tabelas LOOP
        IF to_regclass('steam_do_bedo.' || t) IS NULL THEN
            RAISE EXCEPTION 'seed: tabela steam_do_bedo.% não existe. Rode o ddl.sql antes deste seed.', t;
        END IF;
        EXECUTE format('SELECT count(*) FROM steam_do_bedo.%I', t) INTO qtd;
        IF qtd > 0 THEN
            ocupadas := ocupadas || format('%s (%s)', t, qtd);
        END IF;
    END LOOP;
    IF cardinality(ocupadas) > 0 THEN
        RAISE EXCEPTION 'seed abortado: o banco não está vazio. Tabelas com linhas: %',
                        array_to_string(ocupadas, ', ')
            USING HINT = 'Rode o ddl.sql de novo e depois o seed.sql. Nada foi inserido.';
    END IF;
END
$$;

-- Parâmetros da carga. "fim" é o instante mais recente gerado: a carga
-- não depende do dia em que é executada.
CREATE TEMP TABLE seed_param ON COMMIT DROP AS
SELECT :'escala'::numeric                      AS escala,
       TIMESTAMPTZ '2026-10-31 23:59:00+00'    AS fim,
       round(500000  * :'escala'::numeric)::int AS n_usuarios,
       round(5000000 * :'escala'::numeric)::int AS n_comentarios,
       round(600000  * :'escala'::numeric)::int AS n_inscricoes;

DO $$
BEGIN
    IF (SELECT escala FROM seed_param) NOT BETWEEN 0.001 AND 4 THEN
        RAISE EXCEPTION 'seed: escala % fora do intervalo [0,001; 4]', (SELECT escala FROM seed_param);
    END IF;
END
$$;

SELECT setseed(0.42);

-- ---------------------------------------------------------------------
-- Funções auxiliares temporárias (somem no fim da sessão)
-- ---------------------------------------------------------------------

-- Normal padrão (Box-Muller). 1 - random() evita ln(0).
CREATE FUNCTION pg_temp.normal() RETURNS double precision
LANGUAGE sql VOLATILE AS
$$ SELECT sqrt(-2 * ln(1 - random())) * cos(2 * pi() * random()) $$;

-- Sorteio enviesado para o começo de 1..n: com a > 1, os primeiros
-- valores saem muito mais (lei de potência). Usado para "poucos usuários
-- comentam muito" e "poucas marcas patrocinam muito".
CREATE FUNCTION pg_temp.potencia(n bigint, a double precision) RETURNS bigint
LANGUAGE sql VOLATILE AS
$$ SELECT 1 + floor(n * power(random(), a))::bigint $$;

-- ---------------------------------------------------------------------
-- Conversao: 154 moedas ISO 4217 reais, fator aproximado para USD
-- (cotações de 2025, arredondadas). Tamanho real, sem moedas fictícias
-- (DEC-031). Inclui moedas sem país na tabela Pais (territórios), que
-- continuam válidas no catálogo de moedas.
-- ---------------------------------------------------------------------
INSERT INTO steam_do_bedo.Conversao (moeda, nome, fator_conver) VALUES
    -- África
    ('DZD','Dinar argelino',0.0075),('AOA','Kwanza angolano',0.0011),
    ('XOF','Franco CFA da África Ocidental',0.0017),('BWP','Pula de Botsuana',0.073),
    ('BIF','Franco do Burundi',0.00034),('CVE','Escudo cabo-verdiano',0.0098),
    ('XAF','Franco CFA da África Central',0.0017),('KMF','Franco comorense',0.0022),
    ('CDF','Franco congolês',0.00035),('DJF','Franco do Djibuti',0.0056),
    ('EGP','Libra egípcia',0.020),('ERN','Nakfa da Eritreia',0.0667),
    ('SZL','Lilangeni suázi',0.055),('ETB','Birr etíope',0.0072),
    ('GMD','Dalasi gambiano',0.014),('GHS','Cedi ganês',0.08),
    ('GNF','Franco guineano',0.000115),('KES','Xelim queniano',0.0077),
    ('LSL','Loti do Lesoto',0.055),('LRD','Dólar liberiano',0.005),
    ('LYD','Dinar líbio',0.18),('MGA','Ariary malgaxe',0.00022),
    ('MWK','Kwacha malauiano',0.00058),('MRU','Ouguiya mauritana',0.025),
    ('MUR','Rupia mauriciana',0.022),('MAD','Dirham marroquino',0.10),
    ('MZN','Metical moçambicano',0.0156),('NAD','Dólar namibiano',0.055),
    ('NGN','Naira nigeriana',0.00065),('RWF','Franco ruandês',0.0007),
    ('STN','Dobra de São Tomé e Príncipe',0.044),('SCR','Rupia seichelense',0.07),
    ('SLE','Leone de Serra Leoa',0.044),('SOS','Xelim somali',0.00175),
    ('ZAR','Rand sul-africano',0.055),('SSP','Libra sul-sudanesa',0.00022),
    ('SDG','Libra sudanesa',0.00166),('TZS','Xelim tanzaniano',0.00038),
    ('TND','Dinar tunisiano',0.33),('UGX','Xelim ugandense',0.00027),
    ('ZMW','Kwacha zambiano',0.037),('ZWG','Ouro do Zimbábue',0.037),
    -- Américas
    ('XCD','Dólar do Caribe Oriental',0.37),('ARS','Peso argentino',0.00085),
    ('BSD','Dólar bahamense',1.0),('BBD','Dólar barbadiano',0.5),
    ('BZD','Dólar belizenho',0.5),('BOB','Boliviano',0.145),
    ('BRL','Real brasileiro',0.18),('CAD','Dólar canadense',0.72),
    ('CLP','Peso chileno',0.00105),('COP','Peso colombiano',0.00025),
    ('CRC','Colón costarriquenho',0.002),('CUP','Peso cubano',0.0417),
    ('DOP','Peso dominicano',0.016),('GTQ','Quetzal guatemalteco',0.13),
    ('GYD','Dólar guianense',0.0048),('HTG','Gourde haitiano',0.0076),
    ('HNL','Lempira hondurenha',0.039),('JMD','Dólar jamaicano',0.0063),
    ('MXN','Peso mexicano',0.053),('NIO','Córdoba nicaraguense',0.027),
    ('PAB','Balboa panamenho',1.0),('PYG','Guarani paraguaio',0.000125),
    ('PEN','Sol peruano',0.27),('SRD','Dólar surinamês',0.027),
    ('TTD','Dólar de Trinidad e Tobago',0.147),('USD','Dólar americano',1.0),
    ('UYU','Peso uruguaio',0.025),('VES','Bolívar venezuelano',0.01),
    -- Ásia
    ('AFN','Afegane',0.014),('AMD','Dram armênio',0.0026),
    ('AZN','Manat azeri',0.588),('BHD','Dinar bareinita',2.65),
    ('BDT','Taka bengali',0.0082),('BTN','Ngultrum butanês',0.0117),
    ('BND','Dólar bruneano',0.75),('KHR','Riel cambojano',0.00025),
    ('CNY','Yuan chinês',0.139),('GEL','Lari georgiano',0.37),
    ('INR','Rupia indiana',0.0117),('IDR','Rupia indonésia',0.000061),
    ('IRR','Rial iraniano',0.0000238),('IQD','Dinar iraquiano',0.00076),
    ('ILS','Novo shekel israelense',0.28),('JPY','Iene japonês',0.0066),
    ('JOD','Dinar jordaniano',1.41),('KZT','Tenge cazaque',0.0019),
    ('KWD','Dinar kuwaitiano',3.26),('KGS','Som quirguiz',0.0114),
    ('LAK','Kip laosiano',0.000046),('LBP','Libra libanesa',0.0000112),
    ('MYR','Ringgit malaio',0.23),('MVR','Rufiyaa maldiva',0.065),
    ('MNT','Tugrik mongol',0.00029),('MMK','Kyat birmanês',0.00048),
    ('NPR','Rupia nepalesa',0.0073),('KPW','Won norte-coreano',0.0011),
    ('OMR','Rial omanense',2.6),('PKR','Rupia paquistanesa',0.0035),
    ('PHP','Peso filipino',0.0175),('QAR','Rial catariano',0.275),
    ('SAR','Rial saudita',0.2666),('SGD','Dólar de Singapura',0.77),
    ('KRW','Won sul-coreano',0.00072),('LKR','Rupia cingalesa',0.0033),
    ('SYP','Libra síria',0.000077),('TWD','Novo dólar taiwanês',0.032),
    ('TJS','Somoni tadjique',0.1),('THB','Baht tailandês',0.03),
    ('TRY','Lira turca',0.025),('TMT','Manat turcomeno',0.2857),
    ('AED','Dirham dos Emirados',0.2723),('UZS','Som uzbeque',0.000079),
    ('VND','Dong vietnamita',0.000039),('YER','Rial iemenita',0.004),
    ('HKD','Dólar de Hong Kong',0.128),('MOP','Pataca de Macau',0.124),
    -- Europa
    ('ALL','Lek albanês',0.011),('BYN','Rublo bielorrusso',0.30),
    ('BAM','Marco conversível bósnio',0.56),('BGN','Lev búlgaro',0.56),
    ('EUR','Euro',1.10),('CZK','Coroa tcheca',0.044),
    ('DKK','Coroa dinamarquesa',0.147),('HUF','Florim húngaro',0.0028),
    ('ISK','Coroa islandesa',0.0074),('CHF','Franco suíço',1.17),
    ('MDL','Leu moldávio',0.057),('MKD','Dinar macedônio',0.0178),
    ('NOK','Coroa norueguesa',0.094),('PLN','Zloty polonês',0.26),
    ('RON','Leu romeno',0.22),('RUB','Rublo russo',0.012),
    ('RSD','Dinar sérvio',0.0094),('SEK','Coroa sueca',0.098),
    ('UAH','Grívnia ucraniana',0.024),('GBP','Libra esterlina',1.30),
    -- Oceania
    ('AUD','Dólar australiano',0.65),('FJD','Dólar fijiano',0.44),
    ('NZD','Dólar neozelandês',0.59),('PGK','Kina papuásia',0.25),
    ('WST','Tala samoano',0.36),('SBD','Dólar das Ilhas Salomão',0.12),
    ('TOP','Paʻanga tonganesa',0.42),('VUV','Vatu de Vanuatu',0.0083),
    -- Territórios (moeda existe, país não está em Pais)
    ('XPF','Franco CFP',0.0092),('ANG','Florim das Antilhas',0.56),
    ('AWG','Florim arubano',0.556),('KYD','Dólar das Ilhas Cayman',1.2),
    ('BMD','Dólar bermudense',1.0),('FKP','Libra das Malvinas',1.30),
    ('GIP','Libra de Gibraltar',1.30),('SHP','Libra de Santa Helena',1.30);

-- ---------------------------------------------------------------------
-- Pais: 199 países reais (193 da ONU + Vaticano, Palestina, Kosovo,
-- Taiwan, Hong Kong e Macau), com a moeda corrente.
-- DDI: o código não é único no mundo real (+1 é de EUA, Canadá e Caribe;
-- +7 é de Rússia e Cazaquistão). Como a PK é o DDI, o seed usa o prefixo
-- que distingue o país: os países do Caribe no +1 usam 1 + código de área
-- (Jamaica 1876), o Canadá usa 1613 (Ottawa), o Cazaquistão 77 e o
-- Vaticano 379 (código reservado a ele pela UIT). DEC-031.
-- "peso" (só na carga) é a participação relativa do país no público de
-- streaming, usada para sortear a residência dos usuários: concentrada
-- em poucos países (EUA, Índia, Brasil, Indonésia...), e 0,05 para os
-- países sem peso próprio. Valores do grupo, inspirados no número de
-- usuários de internet de cada país; não são estatística oficial.
-- ---------------------------------------------------------------------
CREATE TEMP TABLE tmp_pais (ddi varchar(4), nome varchar(255), moeda varchar(3), peso numeric) ON COMMIT DROP;
INSERT INTO tmp_pais (ddi, nome, moeda, peso) VALUES
    -- África
    ('213','Argélia','DZD',0.3),('244','Angola','AOA',0.15),('229','Benin','XOF',0.05),
    ('267','Botsuana','BWP',0.05),('226','Burkina Faso','XOF',0.05),('257','Burundi','BIF',0.05),
    ('238','Cabo Verde','CVE',0.05),('237','Camarões','XAF',0.1),('236','República Centro-Africana','XAF',0.05),
    ('235','Chade','XAF',0.05),('269','Comores','KMF',0.05),('242','República do Congo','XAF',0.05),
    ('243','República Democrática do Congo','CDF',0.1),('253','Djibuti','DJF',0.05),('20','Egito','EGP',1.0),
    ('240','Guiné Equatorial','XAF',0.05),('291','Eritreia','ERN',0.05),('268','Essuatíni','SZL',0.05),
    ('251','Etiópia','ETB',0.2),('241','Gabão','XAF',0.05),('220','Gâmbia','GMD',0.05),
    ('233','Gana','GHS',0.2),('224','Guiné','GNF',0.05),('245','Guiné-Bissau','XOF',0.05),
    ('225','Costa do Marfim','XOF',0.1),('254','Quênia','KES',0.3),('266','Lesoto','LSL',0.05),
    ('231','Libéria','LRD',0.05),('218','Líbia','LYD',0.05),('261','Madagascar','MGA',0.05),
    ('265','Malawi','MWK',0.05),('223','Mali','XOF',0.05),('222','Mauritânia','MRU',0.05),
    ('230','Maurício','MUR',0.05),('212','Marrocos','MAD',0.5),('258','Moçambique','MZN',0.1),
    ('264','Namíbia','NAD',0.05),('227','Níger','XOF',0.05),('234','Nigéria','NGN',1.0),
    ('250','Ruanda','RWF',0.05),('239','São Tomé e Príncipe','STN',0.05),('221','Senegal','XOF',0.1),
    ('248','Seicheles','SCR',0.05),('232','Serra Leoa','SLE',0.05),('252','Somália','SOS',0.05),
    ('27','África do Sul','ZAR',0.8),('211','Sudão do Sul','SSP',0.05),('249','Sudão','SDG',0.05),
    ('255','Tanzânia','TZS',0.15),('228','Togo','XOF',0.05),('216','Tunísia','TND',0.2),
    ('256','Uganda','UGX',0.1),('260','Zâmbia','ZMW',0.05),('263','Zimbábue','ZWG',0.05),
    -- Américas
    ('1268','Antígua e Barbuda','XCD',0.05),('54','Argentina','ARS',1.5),('1242','Bahamas','BSD',0.05),
    ('1246','Barbados','BBD',0.05),('501','Belize','BZD',0.05),('591','Bolívia','BOB',0.2),
    ('55','Brasil','BRL',9.0),('1613','Canadá','CAD',1.5),('56','Chile','CLP',0.7),
    ('57','Colômbia','COP',1.2),('506','Costa Rica','CRC',0.1),('53','Cuba','CUP',0.05),
    ('1767','Dominica','XCD',0.05),('1809','República Dominicana','DOP',0.2),('593','Equador','USD',0.3),
    ('503','El Salvador','USD',0.1),('1473','Granada','XCD',0.05),('502','Guatemala','GTQ',0.2),
    ('592','Guiana','GYD',0.05),('509','Haiti','HTG',0.05),('504','Honduras','HNL',0.1),
    ('1876','Jamaica','JMD',0.05),('52','México','MXN',4.0),('505','Nicarágua','NIO',0.05),
    ('507','Panamá','PAB',0.1),('595','Paraguai','PYG',0.15),('51','Peru','PEN',0.6),
    ('1869','São Cristóvão e Névis','XCD',0.05),('1758','Santa Lúcia','XCD',0.05),
    ('1784','São Vicente e Granadinas','XCD',0.05),('597','Suriname','SRD',0.05),
    ('1868','Trinidad e Tobago','TTD',0.05),('1','Estados Unidos','USD',12.0),('598','Uruguai','UYU',0.2),
    ('58','Venezuela','VES',0.4),
    -- Ásia
    ('93','Afeganistão','AFN',0.05),('374','Armênia','AMD',0.05),('994','Azerbaijão','AZN',0.1),
    ('973','Bahrein','BHD',0.05),('880','Bangladesh','BDT',0.8),('975','Butão','BTN',0.05),
    ('673','Brunei','BND',0.05),('855','Camboja','KHR',0.1),('86','China','CNY',4.0),
    ('357','Chipre','EUR',0.05),('995','Geórgia','GEL',0.05),('91','Índia','INR',10.0),
    ('62','Indonésia','IDR',5.0),('98','Irã','IRR',0.5),('964','Iraque','IQD',0.3),
    ('972','Israel','ILS',0.3),('81','Japão','JPY',3.0),('962','Jordânia','JOD',0.1),
    ('77','Cazaquistão','KZT',0.3),('965','Kuwait','KWD',0.1),('996','Quirguistão','KGS',0.05),
    ('856','Laos','LAK',0.05),('961','Líbano','LBP',0.05),('60','Malásia','MYR',0.8),
    ('960','Maldivas','MVR',0.05),('976','Mongólia','MNT',0.05),('95','Mianmar','MMK',0.1),
    ('977','Nepal','NPR',0.1),('850','Coreia do Norte','KPW',0.05),('968','Omã','OMR',0.05),
    ('92','Paquistão','PKR',1.0),('970','Palestina','ILS',0.05),('63','Filipinas','PHP',2.5),
    ('974','Catar','QAR',0.05),('966','Arábia Saudita','SAR',0.8),('65','Singapura','SGD',0.3),
    ('82','Coreia do Sul','KRW',2.5),('94','Sri Lanka','LKR',0.1),('963','Síria','SYP',0.05),
    ('886','Taiwan','TWD',0.6),('992','Tadjiquistão','TJS',0.05),('66','Tailândia','THB',1.5),
    ('670','Timor-Leste','USD',0.05),('90','Turquia','TRY',2.0),('993','Turcomenistão','TMT',0.05),
    ('971','Emirados Árabes Unidos','AED',0.3),('998','Uzbequistão','UZS',0.1),('84','Vietnã','VND',2.0),
    ('967','Iêmen','YER',0.05),('852','Hong Kong','HKD',0.3),('853','Macau','MOP',0.05),
    -- Europa
    ('355','Albânia','ALL',0.05),('376','Andorra','EUR',0.05),('43','Áustria','EUR',0.3),
    ('375','Bielorrússia','BYN',0.2),('32','Bélgica','EUR',0.4),('387','Bósnia e Herzegovina','BAM',0.05),
    ('359','Bulgária','EUR',0.2),('385','Croácia','EUR',0.1),('420','Tchéquia','CZK',0.3),
    ('45','Dinamarca','DKK',0.2),('372','Estônia','EUR',0.05),('358','Finlândia','EUR',0.2),
    ('33','França','EUR',2.5),('49','Alemanha','EUR',3.0),('30','Grécia','EUR',0.3),
    ('36','Hungria','HUF',0.3),('354','Islândia','ISK',0.05),('353','Irlanda','EUR',0.2),
    ('39','Itália','EUR',2.0),('383','Kosovo','EUR',0.05),('371','Letônia','EUR',0.05),
    ('423','Liechtenstein','CHF',0.05),('370','Lituânia','EUR',0.05),('352','Luxemburgo','EUR',0.05),
    ('356','Malta','EUR',0.05),('373','Moldávia','MDL',0.05),('377','Mônaco','EUR',0.05),
    ('382','Montenegro','EUR',0.05),('31','Países Baixos','EUR',0.7),('389','Macedônia do Norte','MKD',0.05),
    ('47','Noruega','NOK',0.2),('48','Polônia','PLN',1.2),('351','Portugal','EUR',0.5),
    ('40','Romênia','RON',0.4),('7','Rússia','RUB',3.0),('378','San Marino','EUR',0.05),
    ('381','Sérvia','RSD',0.1),('421','Eslováquia','EUR',0.1),('386','Eslovênia','EUR',0.05),
    ('34','Espanha','EUR',2.0),('46','Suécia','SEK',0.4),('41','Suíça','CHF',0.3),
    ('380','Ucrânia','UAH',0.7),('44','Reino Unido','GBP',3.0),('379','Vaticano','EUR',0.05),
    -- Oceania
    ('61','Austrália','AUD',1.0),('679','Fiji','FJD',0.05),('686','Kiribati','AUD',0.05),
    ('692','Ilhas Marshall','USD',0.05),('691','Micronésia','USD',0.05),('674','Nauru','AUD',0.05),
    ('64','Nova Zelândia','NZD',0.2),('680','Palau','USD',0.05),('675','Papua-Nova Guiné','PGK',0.05),
    ('685','Samoa','WST',0.05),('677','Ilhas Salomão','SBD',0.05),('676','Tonga','TOP',0.05),
    ('688','Tuvalu','AUD',0.05),('678','Vanuatu','VUV',0.05);

INSERT INTO steam_do_bedo.Pais (ddi, nome, moeda)
SELECT ddi, nome, moeda FROM tmp_pais ORDER BY ddi;

-- Distribuição acumulada dos países para o sorteio ponderado: um número
-- u em [0, 1) cai no país cujo intervalo [lo, hi) o contém. O índice em
-- hi permite achar o país com uma busca, sem varrer a lista.
CREATE TEMP TABLE tmp_pais_cdf ON COMMIT DROP AS
SELECT ddi,
       sum(peso) OVER (ORDER BY ddi) / sum(peso) OVER () AS hi
FROM tmp_pais;
CREATE INDEX ON tmp_pais_cdf (hi);
ANALYZE tmp_pais_cdf;

-- ---------------------------------------------------------------------
-- Empresa: ~70 empresas reais (donas de plataformas e marcas que
-- patrocinam streamers) + fictícias até 3.000.
-- "peso_patrocinio" (só na carga): força de cada marca no sorteio de
-- patrocínios. Donas de plataforma têm peso 0 (não patrocinam canais).
-- ---------------------------------------------------------------------
CREATE TEMP TABLE tmp_empresa_real (nome varchar(255), fantasia varchar(255), ddi varchar(4), peso_patrocinio numeric) ON COMMIT DROP;
INSERT INTO tmp_empresa_real VALUES
    -- Donas, fundadoras ou responsáveis de plataformas
    ('Google LLC','Google','1',0),('YouTube LLC','YouTube','1',0),('Amazon.com Inc.','Amazon','1',0),
    ('Twitch Interactive Inc.','Twitch','1',0),('Justin.tv Inc.','Justin.tv','1',0),
    ('Meta Platforms Inc.','Meta','1',0),('Instagram LLC','Instagram','1',0),
    ('ByteDance Ltd.','ByteDance','86',0),('TikTok Pte. Ltd.','TikTok','65',0),
    ('Beijing Douyin Information Service Co. Ltd.','Douyin','86',0),('Kuaishou Technology','Kuaishou','86',0),
    ('Tencent Holdings Ltd.','Tencent','86',0),('Kick Streaming Pty Ltd.','Kick','61',0),
    ('Huya Inc.','Huya','86',0),('JOYY Inc.','JOYY','86',0),('Douyu International Holdings Ltd.','Douyu','86',0),
    ('Bilibili Inc.','Bilibili','86',0),('Snap Inc.','Snapchat','1',0),('Nowcom Co. Ltd.','Nowcom','82',0),
    ('SOOP Co. Ltd.','SOOP','82',0),('Naver Corporation','Naver','82',0),('Rumble Inc.','Rumble','1',0),
    ('Lino Network Inc.','Lino','1',0),('BitTorrent Inc.','BitTorrent','1',0),
    ('Microsoft Corporation','Microsoft','1',0),('BIGO Technology Pte. Ltd.','BIGO','65',0),
    ('Triller Inc.','Triller','1',0),('Triller Group Inc.','Triller Group','1',0),
    ('Dailymotion SA','Dailymotion','33',0),('Vivendi SE','Vivendi','33',0),
    ('Connected Ventures LLC','Connected Ventures','1',0),('Vimeo Inc.','Vimeo','1',0),
    ('Valve Corporation','Valve','1',0),('Pocket Aces Pictures Pvt. Ltd.','Pocket Aces','91',0),
    ('Rooter Sports Technologies Pvt. Ltd.','Rooter','91',0),('DMM.com LLC','DMM','81',0),
    -- Marcas que patrocinam (peso maior = patrocina mais canais)
    ('Red Bull GmbH','Red Bull','43',10),('Monster Energy Company','Monster Energy','1',8),
    ('Razer Inc.','Razer','65',9),('Logitech International SA','Logitech G','41',8),
    ('Corsair Gaming Inc.','Corsair','1',7),('HP Inc.','HyperX','1',7),('Intel Corporation','Intel','1',6),
    ('Advanced Micro Devices Inc.','AMD','1',6),('NVIDIA Corporation','NVIDIA','1',6),
    ('Samsung Electronics Co. Ltd.','Samsung','82',5),('Secretlab SG Pte. Ltd.','Secretlab','65',6),
    ('Gamma Enterprises LLC','G FUEL','1',6),('Sony Group Corporation','PlayStation','81',5),
    ('Nintendo Co. Ltd.','Nintendo','81',3),('Riot Games Inc.','Riot Games','1',5),
    ('Epic Games Inc.','Epic Games','1',5),('Ubisoft Entertainment SA','Ubisoft','33',4),
    ('Electronic Arts Inc.','EA','1',4),('Activision Blizzard Inc.','Activision Blizzard','1',4),
    ('Take-Two Interactive Software Inc.','Take-Two','1',3),('Krafton Inc.','Krafton','82',3),
    ('miHoYo Co. Ltd.','HoYoverse','86',4),('Plarium Global Ltd.','Plarium','972',4),
    ('Nord Security','NordVPN','370',5),('Garena Online Pte. Ltd.','Garena','65',3),
    ('KaBuM! Comércio Eletrônico S.A.','KaBuM!','55',4),('LOUD Esports Ltda.','LOUD','55',2),
    ('The Coca-Cola Company','Coca-Cola','1',3),('PepsiCo Inc.','PepsiCo','1',3),
    ('Nike Inc.','Nike','1',2),('Adidas AG','Adidas','49',2),('Mastercard Inc.','Mastercard','1',3),
    ('Visa Inc.','Visa','1',2),('Spotify AB','Spotify','46',2),('Netflix Inc.','Netflix','1',2),
    ('Uber Technologies Inc.','Uber','1',2),('McDonald''s Corporation','McDonald''s','1',2),
    ('Domino''s Pizza Inc.','Domino''s','1',2),('MercadoLibre Inc.','Mercado Livre','54',3),
    ('Nu Pagamentos S.A.','Nubank','55',3),('Sea Limited','Shopee','65',3),
    ('Alibaba Group Holding Ltd.','AliExpress','86',2);

INSERT INTO steam_do_bedo.Empresa (nome, nome_fantasia)
SELECT nome, fantasia FROM tmp_empresa_real ORDER BY nome;

-- Fictícias: o número no nome garante o UNIQUE (nome) (DEC-009).
-- Patrocinam com peso 1, então somadas pesam como as marcas reais.
INSERT INTO steam_do_bedo.Empresa (nome, nome_fantasia)
SELECT f || ' ' || lpad(i::text, 4, '0') || ' '
       || (ARRAY['Ltda.','S.A.','Inc.','LLC','GmbH','Ltd.'])[1 + floor(random() * 6)::int],
       f
FROM generate_series(1, 3000 - (SELECT count(*) FROM tmp_empresa_real)) AS i
CROSS JOIN LATERAL (
    SELECT (ARRAY['Nexus','Orion','Vertex','Aurora','Quantum','Atlas','Helix','Pulse','Zenith',
                  'Nimbus','Apex','Lumen','Vortex','Prisma','Fênix','Delta','Sigma','Astra',
                  'Boreal','Cobalto'])[1 + floor(random() * 20)::int]
           || ' ' ||
           (ARRAY['Games','Tecnologia','Energéticos','Periféricos','Telecom','Bebidas','Hardware',
                  'Educação','Moda','Alimentos','Seguros','Software','Eletrônicos','Apostas Esportivas',
                  'Fintech'])[1 + floor(random() * 15)::int] AS f
    WHERE i > 0   -- referência a i: força um sorteio por linha
) AS x
ORDER BY i;

-- Marcas candidatas a patrocinar, em ordem de peso decrescente: o sorteio
-- por lei de potência (pg_temp.potencia) escolhe as primeiras muito mais.
CREATE TEMP TABLE tmp_patrocinador ON COMMIT DROP AS
SELECT row_number() OVER (ORDER BY coalesce(r.peso_patrocinio, 1) DESC, random()) AS rk, e.nro
FROM steam_do_bedo.Empresa e
LEFT JOIN tmp_empresa_real r ON r.nome = e.nome
WHERE coalesce(r.peso_patrocinio, 1) > 0;
CREATE UNIQUE INDEX ON tmp_patrocinador (rk);
ANALYZE tmp_patrocinador;

-- ---------------------------------------------------------------------
-- EmpresaPais: sede de cada empresa (país conhecido para as reais;
-- sorteado pelo peso dos países para as fictícias) e segunda sede para
-- ~15% (EUA, ou Brasil para quem já é dos EUA).
-- id_nacional: formato do país (CNPJ no Brasil, EIN nos EUA, genérico nos
-- demais), derivado do nro para ser único no país (DEC-025).
-- ---------------------------------------------------------------------
WITH origem AS (
    SELECT e.nro,
           coalesce(r.ddi, (SELECT c.ddi FROM tmp_pais_cdf c WHERE c.hi > x.u ORDER BY c.hi LIMIT 1)) AS ddi,
           x.segunda
    FROM steam_do_bedo.Empresa e
    LEFT JOIN tmp_empresa_real r ON r.nome = e.nome
    CROSS JOIN LATERAL (SELECT random() AS u, random() < 0.15 AS segunda WHERE e.nro > 0) x
),
sedes AS (
    SELECT nro, ddi FROM origem
    UNION ALL
    SELECT nro, CASE WHEN ddi = '1' THEN '55' ELSE '1' END FROM origem WHERE segunda
)
INSERT INTO steam_do_bedo.EmpresaPais (nro_empresa, ddi_pais, id_nacional)
SELECT nro, ddi,
       CASE ddi
           WHEN '55' THEN regexp_replace(lpad(nro::text, 8, '0'), '(\d{2})(\d{3})(\d{3})', '\1.\2.\3')
                          || '/0001-' || lpad((nro % 97)::text, 2, '0')
           WHEN '1'  THEN regexp_replace(lpad((nro * 7919)::text, 9, '0'), '(\d{2})(\d{7})', '\1-\2')
           ELSE 'NID' || ddi || '-' || lpad(nro::text, 8, '0')
       END
FROM sedes
ORDER BY nro, ddi;

-- ---------------------------------------------------------------------
-- Plataforma: 28 plataformas reais de streaming de jogos, de vídeo longo
-- (lives e VODs), curto (shorts) e mistas (DEC-020).
-- Colunas só da carga:
--   peso    participação no sorteio das contas dos usuários (mercado);
--   formato 'longo', 'curto' ou 'misto' (YouTube, Bilibili...): define
--           duração, número de vídeos por canal e comentários online;
--   fim     data de encerramento (Mixer: 2020-07-22); nenhum canal, vídeo
--           ou comentário é gerado depois dela.
-- Datas de fundação aproximadas. qtd_users é calculado no INSERT, a
-- partir das contas preparadas abaixo (DEC-027, sem UPDATE final).
-- ---------------------------------------------------------------------
CREATE TEMP TABLE tmp_plataforma (ord int, nome varchar(255), fundadora varchar(255), responsavel varchar(255),
                                  data_fund date, peso numeric, formato text, fim timestamptz) ON COMMIT DROP;
INSERT INTO tmp_plataforma VALUES
    ( 1,'YouTube','YouTube LLC','Google LLC',DATE '2005-02-14',30,'misto',NULL),
    ( 2,'Twitch','Justin.tv Inc.','Twitch Interactive Inc.',DATE '2011-06-06',8,'longo',NULL),
    ( 3,'TikTok','ByteDance Ltd.','TikTok Pte. Ltd.',DATE '2017-05-01',20,'curto',NULL),
    ( 4,'Instagram','Instagram LLC','Meta Platforms Inc.',DATE '2010-10-06',12,'curto',NULL),
    ( 5,'Facebook Gaming','Meta Platforms Inc.','Meta Platforms Inc.',DATE '2018-06-01',6,'longo',NULL),
    ( 6,'Kick','Kick Streaming Pty Ltd.','Kick Streaming Pty Ltd.',DATE '2022-12-06',3,'longo',NULL),
    ( 7,'Kwai','Kuaishou Technology','Kuaishou Technology',DATE '2019-01-01',3,'curto',NULL),
    ( 8,'Douyin','ByteDance Ltd.','Beijing Douyin Information Service Co. Ltd.',DATE '2016-09-20',2,'curto',NULL),
    ( 9,'Kuaishou','Kuaishou Technology','Kuaishou Technology',DATE '2011-03-01',2,'curto',NULL),
    (10,'Bilibili','Bilibili Inc.','Bilibili Inc.',DATE '2009-06-26',2,'misto',NULL),
    (11,'Huya','JOYY Inc.','Huya Inc.',DATE '2014-11-24',1,'longo',NULL),
    (12,'Douyu','Douyu International Holdings Ltd.','Douyu International Holdings Ltd.',DATE '2014-01-01',1,'longo',NULL),
    (13,'Snapchat','Snap Inc.','Snap Inc.',DATE '2011-09-16',2,'curto',NULL),
    (14,'Trovo','Tencent Holdings Ltd.','Tencent Holdings Ltd.',DATE '2020-02-01',0.5,'longo',NULL),
    (15,'SOOP','Nowcom Co. Ltd.','SOOP Co. Ltd.',DATE '2006-03-09',0.8,'longo',NULL),
    (16,'CHZZK','Naver Corporation','Naver Corporation',DATE '2023-12-19',0.5,'longo',NULL),
    (17,'Rumble','Rumble Inc.','Rumble Inc.',DATE '2013-10-01',0.5,'misto',NULL),
    (18,'DLive','Lino Network Inc.','BitTorrent Inc.',DATE '2017-12-01',0.2,'longo',NULL),
    (19,'Nimo TV','Huya Inc.','Huya Inc.',DATE '2018-05-01',0.3,'longo',NULL),
    (20,'Mixer','Microsoft Corporation','Microsoft Corporation',DATE '2016-01-05',0.3,'longo',TIMESTAMPTZ '2020-07-22 00:00+00'),
    (21,'Likee','BIGO Technology Pte. Ltd.','JOYY Inc.',DATE '2017-07-01',0.5,'curto',NULL),
    (22,'Triller','Triller Inc.','Triller Group Inc.',DATE '2015-07-01',0.2,'curto',NULL),
    (23,'Dailymotion','Dailymotion SA','Vivendi SE',DATE '2005-03-15',0.5,'misto',NULL),
    (24,'Vimeo','Connected Ventures LLC','Vimeo Inc.',DATE '2004-11-01',0.3,'longo',NULL),
    (25,'Steam Broadcasting','Valve Corporation','Valve Corporation',DATE '2016-12-05',0.5,'longo',NULL),
    (26,'Loco','Pocket Aces Pictures Pvt. Ltd.','Pocket Aces Pictures Pvt. Ltd.',DATE '2020-01-01',0.3,'longo',NULL),
    (27,'Rooter','Rooter Sports Technologies Pvt. Ltd.','Rooter Sports Technologies Pvt. Ltd.',DATE '2016-01-01',0.2,'longo',NULL),
    (28,'Mildom','DMM.com LLC','DMM.com LLC',DATE '2019-01-01',0.2,'longo',NULL);

CREATE TEMP TABLE tmp_plat_cdf ON COMMIT DROP AS
SELECT ord, sum(peso) OVER (ORDER BY ord) / sum(peso) OVER () AS hi FROM tmp_plataforma;
CREATE INDEX ON tmp_plat_cdf (hi);
ANALYZE tmp_plat_cdf;

-- ---------------------------------------------------------------------
-- Usuario: 500 mil × escala.
-- nick único (palavra + palavra + número do usuário); email deriva do
-- nick; telefone único (DDI do país + número do usuário com 9 dígitos,
-- até 13 caracteres), 15% sem telefone (é nulável, DEC-011).
-- País de residência sorteado pelo peso dos países (concentrado).
-- data_nasc entre 1965 e 2012 (13 anos ou mais em 2025), mais jovens
-- com mais frequência (público de jogos).
-- ---------------------------------------------------------------------
INSERT INTO steam_do_bedo.Usuario (nick, email, data_nasc, telefone, end_postal, pais_residencia)
SELECT s.nick,
       s.nick || '@' || (ARRAY['gmail.com','outlook.com','yahoo.com','proton.me','icloud.com',
                               'hotmail.com','qq.com','naver.com'])[1 + floor(random() * 8)::int],
       DATE '2012-12-31' - floor(power(random(), 1.6) * 17500)::int,
       CASE WHEN random() < 0.85 THEN p.ddi || lpad(s.i::text, 9, '0') END,
       'Rua ' || (ARRAY['das Flores','Central','do Sol','Principal','da Paz','Nova','do Comércio',
                        'dos Pinheiros'])[1 + floor(random() * 8)::int]
              || ', ' || (1 + floor(random() * 2000)::int) || ' - ' || p.nome,
       p.ddi
FROM (
    SELECT i,
           (ARRAY['shadow','pixel','ninja','storm','lunar','turbo','cyber','frost','blaze','viper',
                  'nova','echo','titan','ghost','omega','rapid','neon','zero','alpha','kraken',
                  'gato','lobo','fenix','dragao','sombra','raio','pirata','mago','noob','pro'])[1 + floor(random() * 30)::int]
           || (ARRAY['_','.','','x'])[1 + floor(random() * 4)::int]
           || (ARRAY['br','gg','tv','yt','hd','xd','op','99','ace','king','queen','dev','bot',
                     'main','smurf','lol'])[1 + floor(random() * 16)::int]
           || '_' || i AS nick,
           random() AS u
    FROM generate_series(1, (SELECT n_usuarios FROM seed_param)) AS i
) s
CROSS JOIN LATERAL (SELECT c.ddi FROM tmp_pais_cdf c WHERE c.hi > s.u ORDER BY c.hi LIMIT 1) pc
JOIN tmp_pais p ON p.ddi = pc.ddi
ORDER BY s.i;
ANALYZE steam_do_bedo.usuario;   -- estatística para os JOINs seguintes (ver cabeçalho)

-- ---------------------------------------------------------------------
-- Contas (PlataformaUsuario), preparadas antes de Plataforma para que
-- qtd_users seja calculado no INSERT da plataforma.
-- Número de contas por usuário: 1 (45%), 2 (30%), 3 (15%), 4 (7%) ou
-- 5 (3%); cada conta sorteia a plataforma pelo peso de mercado.
-- Sorteios repetidos da mesma plataforma viram uma conta só (DISTINCT),
-- o que também é realista: quem tem mais contas está nas maiores.
-- "atividade" (só na carga): posição aleatória do usuário na plataforma,
-- usada depois para que poucos usuários comentem e assinem muito.
-- ---------------------------------------------------------------------
CREATE TEMP TABLE tmp_conta ON COMMIT DROP AS
SELECT DISTINCT u.id_usuario, pc.ord
FROM steam_do_bedo.Usuario u
CROSS JOIN LATERAL (
    SELECT CASE WHEN r < 0.45 THEN 1 WHEN r < 0.75 THEN 2 WHEN r < 0.90 THEN 3
                WHEN r < 0.97 THEN 4 ELSE 5 END AS n
    FROM (SELECT random() AS r WHERE u.id_usuario > 0) z
) q
CROSS JOIN LATERAL generate_series(1, q.n) AS k
CROSS JOIN LATERAL (SELECT random() AS u WHERE k > 0) w
CROSS JOIN LATERAL (SELECT c.ord FROM tmp_plat_cdf c WHERE c.hi > w.u ORDER BY c.hi LIMIT 1) pc;
ANALYZE tmp_conta;

INSERT INTO steam_do_bedo.Plataforma (nome, qtd_users, empresa_fund, empresa_resp, data_fund)
SELECT p.nome,
       (SELECT count(*) FROM tmp_conta c WHERE c.ord = p.ord),   -- derivado calculado na carga
       ef.nro, er.nro, p.data_fund
FROM tmp_plataforma p
JOIN steam_do_bedo.Empresa ef ON ef.nome = p.fundadora
JOIN steam_do_bedo.Empresa er ON er.nome = p.responsavel
ORDER BY p.ord;

-- Mapa ordinal -> nro real (obtido pela chave natural, nunca fixo)
CREATE TEMP TABLE tmp_plat ON COMMIT DROP AS
SELECT t.ord, p.nro, t.formato, t.fim, coalesce(t.fim, s.fim) AS limite, p.data_fund
FROM tmp_plataforma t
JOIN steam_do_bedo.Empresa ef ON ef.nome = t.fundadora
JOIN steam_do_bedo.Plataforma p ON p.nome = t.nome AND p.empresa_fund = ef.nro
CROSS JOIN seed_param s;
ANALYZE tmp_plat;

-- nro_usuario: número da conta na plataforma, único por plataforma
-- (DEC-025), em ordem aleatória dentro da plataforma.
CREATE TEMP TABLE tmp_rank_conta ON COMMIT DROP AS
SELECT p.nro AS nro_plataforma, c.id_usuario,
       row_number() OVER (PARTITION BY c.ord ORDER BY random()) AS rk
FROM tmp_conta c
JOIN tmp_plat p ON p.ord = c.ord;
CREATE UNIQUE INDEX ON tmp_rank_conta (nro_plataforma, rk);
ANALYZE tmp_rank_conta;

CREATE TEMP TABLE tmp_qtd_conta ON COMMIT DROP AS
SELECT nro_plataforma, count(*) AS n FROM tmp_rank_conta GROUP BY nro_plataforma;
ANALYZE tmp_qtd_conta;

INSERT INTO steam_do_bedo.PlataformaUsuario (nro_plataforma, id_usuario, nro_usuario)
SELECT nro_plataforma, id_usuario, 10000000 + rk * 37 + (id_usuario % 37)
FROM tmp_rank_conta
ORDER BY nro_plataforma, id_usuario;

-- ---------------------------------------------------------------------
-- StreamerPais: 5% dos usuários são streamers (no seed v2 eram 25%).
-- Passaporte do país de residência em 92% dos casos; 4% têm um segundo
-- passaporte (EUA, ou Brasil para quem já é dos EUA).
-- Número do passaporte: 2 letras + número do usuário, único no país.
-- ---------------------------------------------------------------------
CREATE TEMP TABLE tmp_streamer ON COMMIT DROP AS
SELECT u.id_usuario, u.pais_residencia, x.u
FROM steam_do_bedo.Usuario u
CROSS JOIN LATERAL (SELECT random() AS u WHERE u.id_usuario > 0) x
WHERE x.u < 0.05;
ANALYZE tmp_streamer;

INSERT INTO steam_do_bedo.StreamerPais (id_streamer, ddi_pais, nro_passaporte)
SELECT id_streamer, ddi, upper(substr(md5(ddi || ':' || id_streamer), 1, 2)) || lpad(id_streamer::text, 9, '0')
FROM (
    SELECT s.id_usuario AS id_streamer,
           CASE WHEN x.r < 0.92 THEN s.pais_residencia ELSE pc.ddi END AS ddi
    FROM tmp_streamer s
    CROSS JOIN LATERAL (SELECT random() AS r, random() AS u WHERE s.id_usuario > 0) x
    CROSS JOIN LATERAL (SELECT c.ddi FROM tmp_pais_cdf c WHERE c.hi > x.u ORDER BY c.hi LIMIT 1) pc
    UNION
    SELECT s.id_usuario, CASE WHEN s.pais_residencia = '1' THEN '55' ELSE '1' END
    FROM tmp_streamer s
    WHERE s.u < 0.05 * 0.04
) p
ORDER BY id_streamer, ddi;

-- ---------------------------------------------------------------------
-- Canais (preparação). Regras dos triggers obedecidas aqui:
--   T9  o dono é streamer (sai de tmp_streamer);
--   T10 o dono tem conta na plataforma do canal (sai de tmp_conta);
--   T7  canal criado depois da fundação da plataforma e antes do seu fim.
-- Cada streamer tem canal na sua primeira conta e, com 60%, nas outras.
-- Nome: derivado do nick (único), então (nome, nro_plataforma) é único.
-- "pop": popularidade lognormal do canal (sigma 2,2: poucos canais
-- concentram quase todo o público). Ela comanda as visualizações, o
-- número de vídeos, os membros e os patrocínios (correlação pedida pelo
-- professor em 05:20).
-- ---------------------------------------------------------------------
CREATE TEMP TABLE tmp_canal ON COMMIT DROP AS
SELECT row_number() OVER (ORDER BY c.id_usuario, c.ord) AS k,
       c.id_usuario AS id_streamer, p.nro AS nro_plataforma, p.formato, p.limite,
       initcap(replace(u.nick, '_', ' ')) || ' ' ||
           (ARRAY['TV','Gaming','Live','Plays','Clips','Oficial','Streams','Games'])[1 + floor(random() * 8)::int] AS nome,
       (ARRAY['publico','publico','publico','publico','publico','publico','publico','publico','misto','misto','misto','privado'])
           [1 + floor(random() * 12)::int] AS tipo,
       -- data entre a fundação e 30 dias antes do limite, mais recente com mais frequência
       p.data_fund::timestamptz
         + (p.limite - interval '30 days' - p.data_fund::timestamptz) * power(random(), 0.6) AS data,
       exp(pg_temp.normal() * 2.2) AS pop,
       pg_temp.normal() AS z_ativ
FROM (
    SELECT c.*, row_number() OVER (PARTITION BY c.id_usuario ORDER BY random()) AS n_conta
    FROM tmp_conta c
    JOIN tmp_streamer s ON s.id_usuario = c.id_usuario
) c
JOIN tmp_plat p ON p.ord = c.ord
JOIN steam_do_bedo.Usuario u ON u.id_usuario = c.id_usuario
WHERE c.n_conta = 1 OR random() < 0.6;

-- Percentil de popularidade (0 = menos popular, 1 = mais popular)
ALTER TABLE tmp_canal ADD COLUMN pct double precision;
UPDATE tmp_canal t SET pct = r.pct
FROM (SELECT k, percent_rank() OVER (ORDER BY pop) AS pct FROM tmp_canal) r
WHERE r.k = t.k;
CREATE UNIQUE INDEX ON tmp_canal (k);
ANALYZE tmp_canal;

-- ---------------------------------------------------------------------
-- Vídeos (preparação).
-- Vídeos por canal: lognormal, correlacionada com a popularidade
-- (canais populares publicam mais). Mediana de 10 vídeos em canal de
-- vídeo longo e 25 em canal de vídeo curto; teto de 3.000 e 8.000.
-- Em plataforma mista, 40% dos vídeos são curtos.
-- Curto: 8 a 60 s; longo: lognormal com mediana de 90 min (lives).
-- visu_total: pop do canal × fator lognormal do vídeo (curtos têm mais
-- visualizações por vídeo). visu_simul só existe em live (vídeo longo em
-- plataforma de live): 1% a 10% do total.
-- dataH entre a criação do canal e o limite da plataforma (menos 1 dia).
-- ---------------------------------------------------------------------
CREATE TEMP TABLE tmp_video ON COMMIT DROP AS
SELECT v.k_canal, v.n_video, v.curto, v.dataH, v.duracao, v.tema,
       v.visu_total,
       CASE WHEN NOT v.curto AND v.formato = 'longo'
            THEN floor(v.visu_total * (0.01 + 0.09 * random()))::bigint END AS visu_simul
FROM (
    SELECT c.k AS k_canal, g.n AS n_video, c.formato,
           (c.formato = 'curto' OR (c.formato = 'misto' AND random() < 0.4)) AS curto,
           c.data + (c.limite - interval '1 day' - c.data) * random() AS dataH,
           (ARRAY['Minecraft','Fortnite','League of Legends','Valorant','Counter-Strike 2','GTA V',
                  'Free Fire','Roblox','Dota 2','Apex Legends','Call of Duty','EA FC','Genshin Impact',
                  'PUBG','Elden Ring','Rocket League','Overwatch 2','Just Chatting','Speedrun',
                  'Retrô'])[1 + floor(power(random(), 1.8) * 20)::int] AS tema,
           c.pop, g.n AS dummy
    FROM tmp_canal c
    CROSS JOIN LATERAL (
        SELECT least(CASE WHEN c.formato = 'curto' THEN 8000 ELSE 3000 END,
                     greatest(1, round(exp(ln(CASE WHEN c.formato = 'curto' THEN 25 ELSE 10 END)
                                           + 1.2 * (0.5 * ln(c.pop) / 2.2 + 0.87 * c.z_ativ)))))::int AS n
    ) q
    CROSS JOIN LATERAL generate_series(1, q.n) AS g(n)
) v0
CROSS JOIN LATERAL (
    SELECT v0.k_canal, v0.n_video, v0.formato, v0.curto, v0.dataH, v0.tema,
           CASE WHEN v0.curto THEN make_interval(secs => 8 + floor(random() * 53))
                ELSE make_interval(mins => least(720, greatest(6, round(exp(ln(90) + 0.7 * pg_temp.normal()))))::int)
           END AS duracao,
           greatest(0, floor(v0.pop * CASE WHEN v0.curto THEN 400 ELSE 120 END
                                    * exp(1.1 * pg_temp.normal())))::bigint AS visu_total
) v;
CREATE INDEX ON tmp_video (k_canal);
ANALYZE tmp_video;

-- Canal: qtd_visualizacoes = soma de visu_total dos seus vídeos, calculada
-- no INSERT (derivado; DEC-027).
INSERT INTO steam_do_bedo.Canal (nome, nro_plataforma, tipo, data, descricao, qtd_visualizacoes, id_streamer)
SELECT c.nome, c.nro_plataforma, c.tipo, c.data,
       'Canal de ' || c.nome || ': ' ||
           (ARRAY['lives diárias','gameplay sem cortes','dicas e tutoriais','cortes engraçados',
                  'competitivo','speedruns','jogos indie','bate-papo e jogos'])[1 + floor(random() * 8)::int],
       coalesce(sv.soma, 0),
       c.id_streamer
FROM tmp_canal c
LEFT JOIN (SELECT k_canal, sum(visu_total) AS soma FROM tmp_video GROUP BY k_canal) sv ON sv.k_canal = c.k
ORDER BY c.k;

-- Mapa k -> id_canal pela chave natural (nome, nro_plataforma)
ALTER TABLE tmp_canal ADD COLUMN id_canal bigint;
UPDATE tmp_canal t SET id_canal = c.id_canal
FROM steam_do_bedo.Canal c
WHERE c.nome = t.nome AND c.nro_plataforma = t.nro_plataforma;

-- Video: id_video gerado pela função nativa gen_random_uuid() (UUID v4,
-- DEC-021). Como a ordem dos UUIDs muda a cada carga, nenhum sorteio
-- seguinte percorre os vídeos em ordem de id_video: onde a ordem importa
-- (Comentario), ela é (dataH, canal, número do vídeo), fixa entre cargas.
-- A inserção segue a ordem de id_video, a da PK, para a árvore ser
-- montada em sequência mesmo com ids aleatórios.
-- Título com "#n" garante o UNIQUE (id_canal, titulo, dataH).
-- Cuidado: o PostgreSQL avalia funções voláteis da lista do SELECT, como
--   random(), DEPOIS do ORDER BY. Por isso o título é sorteado aqui, com
--   ORDER BY (canal, número do vídeo), e não no INSERT ordenado por
--   id_video: lá o sorteio seguiria a ordem dos UUIDs e mudaria a cada carga.
--   O ORDER BY também fixa a ordem física desta tabela temporária, que os
--   passos seguintes (Participa, Comentario) percorrem.
CREATE TEMP TABLE tmp_video_id ON COMMIT DROP AS
SELECT gen_random_uuid() AS id_video,
       c.id_canal, c.k AS k_canal, c.nro_plataforma, c.formato, c.limite, c.id_streamer, c.pop,
       v.n_video, v.curto, v.dataH, v.duracao, v.tema, v.visu_total, v.visu_simul,
       CASE WHEN v.curto THEN (ARRAY['Clipe','Jogada','Fail','Highlight','Momento'])[1 + floor(random() * 5)::int]
            ELSE (ARRAY['Live','Gameplay','Rankeada','Campeonato','Tutorial','Zerando'])[1 + floor(random() * 6)::int]
       END || ' de ' || v.tema || ' #' || v.n_video AS titulo
FROM tmp_video v
JOIN tmp_canal c ON c.k = v.k_canal
ORDER BY c.k, v.n_video;
ANALYZE tmp_video_id;

INSERT INTO steam_do_bedo.Video (id_video, id_canal, titulo, dataH, tema, duracao, visu_simul, visu_total)
SELECT id_video, id_canal, titulo, dataH, tema, duracao, visu_simul, visu_total
FROM tmp_video_id
ORDER BY id_video;
ANALYZE steam_do_bedo.video, steam_do_bedo.canal;

-- ---------------------------------------------------------------------
-- Participa: convidados em 20% dos vídeos longos, 1 a 3 cada.
-- Só streamers (T9), nunca o próprio dono. Convidados sorteados entre os
-- streamers com lei de potência (alguns aparecem em muitas lives).
-- ---------------------------------------------------------------------
CREATE TEMP TABLE tmp_streamer_rk ON COMMIT DROP AS
SELECT row_number() OVER (ORDER BY random()) AS rk, id_usuario FROM tmp_streamer;
CREATE UNIQUE INDEX ON tmp_streamer_rk (rk);
ANALYZE tmp_streamer_rk;

INSERT INTO steam_do_bedo.Participa (id_video, id_streamer)
SELECT DISTINCT v.id_video, s.id_usuario
FROM tmp_video_id v
-- a referência a v.n_video torna o sorteio da quantidade correlacionado
-- (sem ela, generate_series seria avaliado uma vez só para todos os vídeos)
CROSS JOIN LATERAL generate_series(1, CASE WHEN v.n_video > 0 THEN 1 + floor(power(random(), 2) * 3)::int END) AS g
CROSS JOIN LATERAL (SELECT pg_temp.potencia((SELECT count(*) FROM tmp_streamer_rk), 1.5) AS rk WHERE g > 0) x
JOIN tmp_streamer_rk s ON s.rk = x.rk
WHERE NOT v.curto
  AND v.n_video % 5 = 0          -- 1 em cada 5 vídeos longos (determinístico e barato)
  AND s.id_usuario <> v.id_streamer
ORDER BY v.id_video, s.id_usuario;

-- ---------------------------------------------------------------------
-- NivelCanal: 5 níveis (T8: nunca mais de 5) em ~55% dos canais; quanto
-- mais popular, mais chance de ter membros (30% + 50% × percentil).
-- Valor mensal na moeda do país do membro (DEC-001), em degraus típicos.
-- ---------------------------------------------------------------------
CREATE TEMP TABLE tmp_canal_membros ON COMMIT DROP AS
SELECT c.k, c.id_canal, c.nro_plataforma, c.id_streamer, c.pop,
       (ARRAY['metal','fa','tier','numero'])[1 + floor(random() * 4)::int] AS estilo,
       (ARRAY[1, 1, 1.5, 2, 3])[1 + floor(random() * 5)::int] AS mult
FROM tmp_canal c
WHERE random() < 0.30 + 0.50 * c.pct;
ANALYZE tmp_canal_membros;

INSERT INTO steam_do_bedo.NivelCanal (id_canal, nivel, valor, gif)
SELECT m.id_canal,
       CASE m.estilo
           WHEN 'metal'  THEN (ARRAY['Bronze','Prata','Ouro','Platina','Diamante'])[n]
           WHEN 'fa'     THEN (ARRAY['Fã','Apoiador','VIP','Elite','Lenda'])[n]
           WHEN 'tier'   THEN 'Tier ' || n
           ELSE 'Nível ' || n
       END,
       (ARRAY[4.99, 9.99, 24.99, 49.99, 99.99])[n] * m.mult,
       'https://cdn.stream-do-bedo.example/gif/' || m.id_canal || '/nivel' || n || '.gif'
FROM tmp_canal_membros m
CROSS JOIN generate_series(1, 5) AS n
ORDER BY m.id_canal, n;
ANALYZE steam_do_bedo.nivelcanal;

-- ---------------------------------------------------------------------
-- Inscricao: 600 mil × escala, distribuídas entre os canais com níveis
-- proporcionalmente a pop^0,7 (cauda longa). O membro sai das contas da
-- plataforma do canal, com lei de potência (usuários ativos assinam
-- mais), nunca o dono. Nível: 1 (60%), 2 (22%), 3 (10%), 4 (5%), 5 (3%).
-- Duplicatas (mesmo usuário sorteado duas vezes no canal) somem no
-- DISTINCT ON, então o total fica um pouco abaixo do alvo.
-- ---------------------------------------------------------------------
INSERT INTO steam_do_bedo.Inscricao (id_canal, id_membro, nivel)
SELECT DISTINCT ON (m.id_canal, rc.id_usuario)
       m.id_canal, rc.id_usuario, nv.nivel
FROM (
    SELECT m.*, floor((SELECT n_inscricoes FROM seed_param) * power(m.pop, 0.7)
                      / sum(power(m.pop, 0.7)) OVER () + random())::int AS n_membros
    FROM tmp_canal_membros m
) m
JOIN tmp_qtd_conta qc ON qc.nro_plataforma = m.nro_plataforma
CROSS JOIN LATERAL generate_series(1, m.n_membros) AS g
CROSS JOIN LATERAL (SELECT pg_temp.potencia(qc.n, 1.3) AS rk, random() AS u WHERE g > 0) x
-- busca da conta sorteada pela chave única de tmp_rank_conta: LATERAL força
-- um acesso pelo índice por linha, qualquer que seja a estimativa do
-- planejador (com JOIN comum, uma estimativa ruim já travou a carga)
CROSS JOIN LATERAL (SELECT r.id_usuario FROM tmp_rank_conta r
                    WHERE r.nro_plataforma = m.nro_plataforma AND r.rk = x.rk) rc
CROSS JOIN LATERAL (
    SELECT n.nivel FROM steam_do_bedo.NivelCanal n
    WHERE n.id_canal = m.id_canal
    ORDER BY n.valor
    OFFSET (CASE WHEN x.u < 0.60 THEN 0 WHEN x.u < 0.82 THEN 1 WHEN x.u < 0.92 THEN 2
                 WHEN x.u < 0.97 THEN 3 ELSE 4 END)
    LIMIT 1
) nv
WHERE rc.id_usuario <> m.id_streamer
ORDER BY m.id_canal, rc.id_usuario;

-- ---------------------------------------------------------------------
-- Patrocinio: chance de patrocínio 3% + 90% × percentil^4 (quase só os
-- canais do topo). Canais do topo têm vários patrocinadores. Marca
-- sorteada por lei de potência sobre o peso (as grandes patrocinam mais).
-- Valor em USD (DEC-026), proporcional à popularidade, arredondado a 100.
-- ---------------------------------------------------------------------
INSERT INTO steam_do_bedo.Patrocinio (nro_empresa, id_canal, valor)
SELECT DISTINCT ON (pt.nro, c.id_canal)
       pt.nro, c.id_canal,
       greatest(500, round(least(5000000, 300 * power(c.pop, 0.6) * exp(0.6 * pg_temp.normal())) / 100) * 100)
FROM tmp_canal c
CROSS JOIN LATERAL generate_series(1, 1 + floor(-ln(1 - random()) * 2.5 * c.pct)::int) AS g
CROSS JOIN LATERAL (SELECT pg_temp.potencia((SELECT count(*) FROM tmp_patrocinador), 2.5) AS rk WHERE g > 0) x
JOIN tmp_patrocinador pt ON pt.rk = x.rk
WHERE random() < 0.03 + 0.90 * power(c.pct, 4)
ORDER BY pt.nro, c.id_canal;

-- ---------------------------------------------------------------------
-- Comentario: 5 mi × escala, distribuídos entre os vídeos em proporção a
-- visu_total^0,85 com ruído (cauda longa: um vídeo viral tem dezenas de
-- milhares de comentários, a maioria tem poucos ou nenhum). Vídeo curto
-- recebe 30% do peso por visualização.
-- Online (feito durante a live): 85% em plataforma de live, 50% em vídeo
-- longo de plataforma mista e 0% em vídeo curto.
-- seq contínuo por vídeo (1..n) e em ordem cronológica: os online vêm
-- primeiro, espalhados pela duração da live; os offline depois, ao longo
-- de até 60 dias, sem passar do limite da plataforma (T3 e T7).
-- Autor: conta da plataforma do vídeo, por lei de potência (poucos
-- usuários comentam muito).
-- Dois passos, por causa do UUID aleatório (DEC-021):
--   1. tmp_comentario sorteia autor e texto percorrendo os vídeos numa
--      ordem fixa entre cargas (dataH, canal, número do vídeo). Se a
--      ordem fosse a dos UUIDs, os sorteios cairiam em comentários
--      diferentes a cada carga.
--   2. A tabela real recebe as linhas em ordem de (id_video, seq), a da
--      PK: a árvore é montada em sequência, sem inserções espalhadas.
-- ---------------------------------------------------------------------
CREATE TEMP TABLE tmp_video_coment ON COMMIT DROP AS
WITH pesos AS (
    SELECT v.id_video, v.k_canal, v.n_video, v.nro_plataforma, v.dataH, v.duracao, v.limite, v.curto, v.formato,
           power(v.visu_total + 1, 0.85) * exp(0.8 * pg_temp.normal())
               * CASE WHEN v.curto THEN 0.3 ELSE 1 END AS peso
    FROM tmp_video_id v
)
SELECT id_video, k_canal, n_video, nro_plataforma, dataH, duracao, limite, n_c,
       floor(n_c * CASE WHEN curto THEN 0 WHEN formato = 'longo' THEN 0.85 ELSE 0.5 END)::int AS n_on
FROM (
    SELECT p.*, floor((SELECT n_comentarios FROM seed_param) * p.peso / sum(p.peso) OVER () + random())::int AS n_c
    FROM pesos p
) x
WHERE n_c > 0;
ANALYZE tmp_video_coment;

CREATE TEMP TABLE tmp_comentario ON COMMIT DROP AS
SELECT v.id_video, g.seq, rc.id_usuario,
       (ARRAY['kkkkkk','GG','que jogada!','primeiro!','manda salve','F no chat','bora!!',
              'esse jogo é muito bom','alguém mais assistindo em 2026?','top demais','clutch',
              'pog','que lag é esse','ensina aí','melhor live','vai dar certo','nerfa isso',
              'saudades dessa época','lindo demais','salve do Brasil'])[1 + floor(random() * 20)::int] AS texto,
       CASE WHEN g.seq <= v.n_on
            THEN v.dataH + v.duracao * (g.seq::double precision / (v.n_on + 1))
            ELSE v.dataH + v.duracao
                 + least(interval '60 days', greatest(interval '0', v.limite - v.dataH - v.duracao))
                   * ((g.seq - v.n_on)::double precision / (v.n_c - v.n_on + 1))
       END AS dataH,
       g.seq <= v.n_on AS coment_on
-- Ordem fixa entre cargas (não a dos UUIDs, que são aleatórios): os
-- sorteios de autor e texto caem sempre nos mesmos comentários.
FROM (SELECT * FROM tmp_video_coment ORDER BY dataH, k_canal, n_video) v
JOIN tmp_qtd_conta qc ON qc.nro_plataforma = v.nro_plataforma
CROSS JOIN LATERAL generate_series(1, v.n_c) AS g(seq)
CROSS JOIN LATERAL (SELECT pg_temp.potencia(qc.n, 2.5) AS rk WHERE g.seq > 0) x
-- mesma busca pela chave única (ver Inscricao): plano estável em 5 mi de linhas
CROSS JOIN LATERAL (SELECT r.id_usuario FROM tmp_rank_conta r
                    WHERE r.nro_plataforma = v.nro_plataforma AND r.rk = x.rk) rc;
ANALYZE tmp_comentario;

INSERT INTO steam_do_bedo.Comentario (id_video, seq, id_usuario, texto, dataH, coment_on)
SELECT id_video, seq, id_usuario, texto, dataH, coment_on
FROM tmp_comentario
ORDER BY id_video, seq;
ANALYZE steam_do_bedo.comentario;

-- ---------------------------------------------------------------------
-- Doacao: 5% dos comentários online e 1% dos offline (~2% no total;
-- no mundo real, de 1% a 5%). 5% dos comentários com doação têm uma
-- segunda doação (seq_pg 2): seq_pg contínuo por comentário (T4).
-- Forma de pagamento: online favorece o mecanismo da plataforma
-- (Super Chat): 55% mecanismo, 20% cartão, 17% PayPal, 8% BitCoin;
-- offline: 30%, 30%, 28% e 12%.
-- Valor: sorteado em USD (lognormal, mediana por forma: mecanismo 4,
-- cartão 10, PayPal 12, BitCoin 40), convertido para a moeda do país de
-- residência do autor (o valor que ele digitaria) e de volta para USD com
-- 2 casas, exatamente como o trigger T11 faria (DEC-026). Mínimo 0,01.
-- Status: lido 70%, recebido 20%, recusado 10% (sorteio em 10 posições).
-- ---------------------------------------------------------------------
CREATE TEMP TABLE tmp_doacao ON COMMIT DROP AS
SELECT c.id_video, c.seq AS seq_comentario, g.seq_pg, c.id_usuario, ca.nro_plataforma, c.dataH,
       f.forma, cv.fator_conver,
       greatest(0.01, round(round(usd.base::numeric / cv.fator_conver, 2) * cv.fator_conver, 2)) AS valor,
       (ARRAY['lido','lido','lido','lido','lido','lido','lido','recebido','recebido','recusado'])
           [1 + floor(least(0.9999, s.u * 1.0) * 10)::int] AS status
-- Lê tmp_comentario, e não a tabela real: ela está na ordem fixa entre
-- cargas, então o sorteio de quem doa não depende dos UUIDs (DEC-021).
FROM tmp_comentario c
CROSS JOIN LATERAL (SELECT random() AS u WHERE c.seq > 0) sel
JOIN steam_do_bedo.Video v       ON v.id_video = c.id_video
JOIN steam_do_bedo.Canal ca      ON ca.id_canal = v.id_canal
JOIN steam_do_bedo.Usuario us    ON us.id_usuario = c.id_usuario
JOIN steam_do_bedo.Pais pa       ON pa.ddi = us.pais_residencia
JOIN steam_do_bedo.Conversao cv  ON cv.moeda = pa.moeda
-- c.seq na condição torna o sorteio correlacionado (um por comentário)
CROSS JOIN LATERAL generate_series(1, CASE WHEN random() < 0.05 AND c.seq > 0 THEN 2 ELSE 1 END) AS g(seq_pg)
CROSS JOIN LATERAL (SELECT random() AS r, random() AS u WHERE g.seq_pg > 0) s
CROSS JOIN LATERAL (
    SELECT CASE WHEN c.coment_on THEN
                    CASE WHEN s.r < 0.55 THEN 'mecanismoplat' WHEN s.r < 0.75 THEN 'cartaocredito'
                         WHEN s.r < 0.92 THEN 'paypal' ELSE 'bitcoin' END
                ELSE
                    CASE WHEN s.r < 0.30 THEN 'mecanismoplat' WHEN s.r < 0.60 THEN 'cartaocredito'
                         WHEN s.r < 0.88 THEN 'paypal' ELSE 'bitcoin' END
           END AS forma
) f
CROSS JOIN LATERAL (
    SELECT least(2000, exp(ln(CASE f.forma WHEN 'mecanismoplat' THEN 4 WHEN 'cartaocredito' THEN 10
                                          WHEN 'paypal' THEN 12 ELSE 40 END)
                           + 1.0 * pg_temp.normal())) AS base
) usd
WHERE sel.u < CASE WHEN c.coment_on THEN 0.05 ELSE 0.01 END;
ANALYZE tmp_doacao;

INSERT INTO steam_do_bedo.Doacao (id_video, seq_comentario, seq_pg, valor, status)
SELECT id_video, seq_comentario, seq_pg, valor, status
FROM tmp_doacao
ORDER BY id_video, seq_comentario, seq_pg;

-- Especializações: cada doação entra em exatamente uma forma (T6).
-- TxID e IdPayPal derivam da chave da doação (únicos, DEC-025).
INSERT INTO steam_do_bedo.BitCoin (id_video, seq_comentario, seq_doacao, TxID)
SELECT id_video, seq_comentario, seq_pg,
       md5('btc:' || id_video || ':' || seq_comentario || ':' || seq_pg)
       || md5('tx:' || id_video || ':' || seq_comentario || ':' || seq_pg)
FROM tmp_doacao WHERE forma = 'bitcoin'
ORDER BY id_video, seq_comentario, seq_pg;

INSERT INTO steam_do_bedo.PayPal (id_video, seq_comentario, seq_doacao, IdPayPal)
SELECT id_video, seq_comentario, seq_pg,
       'PAYID-' || upper(substr(md5('pp:' || id_video || ':' || seq_comentario || ':' || seq_pg), 1, 24))
FROM tmp_doacao WHERE forma = 'paypal'
ORDER BY id_video, seq_comentario, seq_pg;

-- Número de cartão fictício (prefixo da bandeira + dígitos), não um
-- cartão real; ver o cuidado sobre PCI no ddl.sql.
INSERT INTO steam_do_bedo.CartaoCredito (id_video, seq_comentario, seq_doacao, nro, bandeira)
SELECT id_video, seq_comentario, seq_pg,
       b.prefixo || lpad((abs(hashtext(id_video::text || seq_comentario || seq_pg)) % 1000000000000000)::text, 15, '0'),
       b.bandeira
FROM tmp_doacao
CROSS JOIN LATERAL (
    SELECT (ARRAY['Visa','Visa','Visa','Mastercard','Mastercard','Elo','American Express','Hipercard'])[i] AS bandeira,
           (ARRAY['4','4','4','5','5','6','3','6'])[i] AS prefixo
    FROM (SELECT 1 + floor(random() * 8)::int AS i WHERE seq_pg > 0) z
) b
WHERE forma = 'cartaocredito'
ORDER BY id_video, seq_comentario, seq_pg;

-- seq_plataforma contínuo por (usuário, plataforma), em ordem
-- cronológica das doações (T5). O autor sempre tem conta na plataforma,
-- porque os comentários saem das contas da plataforma do vídeo.
INSERT INTO steam_do_bedo.MecanismoPlat (id_video, seq_comentario, seq_doacao, seq_plataforma)
SELECT id_video, seq_comentario, seq_pg,
       row_number() OVER (PARTITION BY id_usuario, nro_plataforma
                          ORDER BY dataH, id_video, seq_comentario, seq_pg)
FROM tmp_doacao
WHERE forma = 'mecanismoplat'
ORDER BY id_video, seq_comentario, seq_pg;

-- ---------------------------------------------------------------------
-- Conferência de sanidade (substitui a checagem de 1.000 a 10.000 do v2).
-- Cada regra que os triggers vão impor dali em diante é conferida sobre a
-- carga inteira. Qualquer falha aborta a transação: nada fica gravado.
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_falhas text[] := '{}';
    v_qtd    bigint;
    v_pct    numeric;
BEGIN
    -- volumes mínimos (as tabelas que dependem de sorteio têm dados)
    IF NOT EXISTS (SELECT 1 FROM steam_do_bedo.bitcoin)       THEN v_falhas := v_falhas || 'BitCoin vazia'::text; END IF;
    IF NOT EXISTS (SELECT 1 FROM steam_do_bedo.paypal)        THEN v_falhas := v_falhas || 'PayPal vazia'::text; END IF;
    IF NOT EXISTS (SELECT 1 FROM steam_do_bedo.cartaocredito) THEN v_falhas := v_falhas || 'CartaoCredito vazia'::text; END IF;
    IF NOT EXISTS (SELECT 1 FROM steam_do_bedo.mecanismoplat) THEN v_falhas := v_falhas || 'MecanismoPlat vazia'::text; END IF;
    IF NOT EXISTS (SELECT 1 FROM steam_do_bedo.participa)     THEN v_falhas := v_falhas || 'Participa vazia'::text; END IF;
    IF NOT EXISTS (SELECT 1 FROM steam_do_bedo.patrocinio)    THEN v_falhas := v_falhas || 'Patrocinio vazia'::text; END IF;
    IF NOT EXISTS (SELECT 1 FROM steam_do_bedo.inscricao)     THEN v_falhas := v_falhas || 'Inscricao vazia'::text; END IF;

    -- derivados (T1 e T2)
    SELECT count(*) INTO v_qtd FROM steam_do_bedo.canal c
    WHERE c.qtd_visualizacoes <> (SELECT coalesce(sum(v.visu_total), 0) FROM steam_do_bedo.video v WHERE v.id_canal = c.id_canal);
    IF v_qtd > 0 THEN v_falhas := v_falhas || format('%s canais com qtd_visualizacoes errada', v_qtd); END IF;
    SELECT count(*) INTO v_qtd FROM steam_do_bedo.plataforma p
    WHERE p.qtd_users <> (SELECT count(*) FROM steam_do_bedo.plataformausuario pu WHERE pu.nro_plataforma = p.nro);
    IF v_qtd > 0 THEN v_falhas := v_falhas || format('%s plataformas com qtd_users errada', v_qtd); END IF;

    -- seq contínuo (T3, T4, T5)
    SELECT count(*) INTO v_qtd FROM (
        SELECT id_video FROM steam_do_bedo.comentario GROUP BY id_video HAVING max(seq) <> count(*)) x;
    IF v_qtd > 0 THEN v_falhas := v_falhas || format('%s vídeos com seq de comentário com buraco', v_qtd); END IF;
    SELECT count(*) INTO v_qtd FROM (
        SELECT 1 FROM steam_do_bedo.doacao GROUP BY id_video, seq_comentario HAVING max(seq_pg) <> count(*)) x;
    IF v_qtd > 0 THEN v_falhas := v_falhas || format('%s comentários com seq_pg com buraco', v_qtd); END IF;
    SELECT count(*) INTO v_qtd FROM (
        SELECT 1 FROM steam_do_bedo.mecanismoplat m
        JOIN steam_do_bedo.comentario c ON c.id_video = m.id_video AND c.seq = m.seq_comentario
        JOIN steam_do_bedo.video v ON v.id_video = m.id_video
        JOIN steam_do_bedo.canal ca ON ca.id_canal = v.id_canal
        GROUP BY c.id_usuario, ca.nro_plataforma
        HAVING max(m.seq_plataforma) <> count(*) OR count(DISTINCT m.seq_plataforma) <> count(*)) x;
    IF v_qtd > 0 THEN v_falhas := v_falhas || format('%s pares (usuário, plataforma) com seq_plataforma com buraco', v_qtd); END IF;

    -- especialização disjunta e total (T6)
    SELECT count(*) INTO v_qtd FROM steam_do_bedo.doacao d
    WHERE (SELECT count(*) FROM (
              SELECT 1 FROM steam_do_bedo.bitcoin b WHERE (b.id_video, b.seq_comentario, b.seq_doacao) = (d.id_video, d.seq_comentario, d.seq_pg)
              UNION ALL SELECT 1 FROM steam_do_bedo.paypal b WHERE (b.id_video, b.seq_comentario, b.seq_doacao) = (d.id_video, d.seq_comentario, d.seq_pg)
              UNION ALL SELECT 1 FROM steam_do_bedo.cartaocredito b WHERE (b.id_video, b.seq_comentario, b.seq_doacao) = (d.id_video, d.seq_comentario, d.seq_pg)
              UNION ALL SELECT 1 FROM steam_do_bedo.mecanismoplat b WHERE (b.id_video, b.seq_comentario, b.seq_doacao) = (d.id_video, d.seq_comentario, d.seq_pg)
          ) f) <> 1;
    IF v_qtd > 0 THEN v_falhas := v_falhas || format('%s doações sem forma ou com mais de uma', v_qtd); END IF;

    -- datas (T7), inclusive o limite das plataformas encerradas
    SELECT count(*) INTO v_qtd FROM steam_do_bedo.comentario c JOIN steam_do_bedo.video v USING (id_video)
    WHERE c.dataH < v.dataH;
    IF v_qtd > 0 THEN v_falhas := v_falhas || format('%s comentários antes do vídeo', v_qtd); END IF;
    SELECT count(*) INTO v_qtd FROM steam_do_bedo.video v JOIN steam_do_bedo.canal c USING (id_canal)
    WHERE v.dataH < c.data;
    IF v_qtd > 0 THEN v_falhas := v_falhas || format('%s vídeos antes do canal', v_qtd); END IF;
    SELECT count(*) INTO v_qtd FROM steam_do_bedo.canal c JOIN steam_do_bedo.plataforma p ON p.nro = c.nro_plataforma
    WHERE (c.data AT TIME ZONE 'UTC')::date < p.data_fund;
    IF v_qtd > 0 THEN v_falhas := v_falhas || format('%s canais antes da plataforma', v_qtd); END IF;
    SELECT count(*) INTO v_qtd FROM steam_do_bedo.comentario c
    JOIN steam_do_bedo.video v USING (id_video) JOIN steam_do_bedo.canal ca USING (id_canal)
    JOIN tmp_plat p ON p.nro = ca.nro_plataforma
    WHERE p.fim IS NOT NULL AND c.dataH > p.fim;
    IF v_qtd > 0 THEN v_falhas := v_falhas || format('%s comentários depois do fim da plataforma', v_qtd); END IF;

    -- níveis (T8)
    SELECT count(*) INTO v_qtd FROM (
        SELECT 1 FROM steam_do_bedo.nivelcanal GROUP BY id_canal HAVING count(*) > 5) x;
    IF v_qtd > 0 THEN v_falhas := v_falhas || format('%s canais com mais de 5 níveis', v_qtd); END IF;

    -- streamer (T9) e conta (T10)
    SELECT count(*) INTO v_qtd FROM steam_do_bedo.canal c
    WHERE NOT EXISTS (SELECT 1 FROM steam_do_bedo.streamerpais s WHERE s.id_streamer = c.id_streamer);
    IF v_qtd > 0 THEN v_falhas := v_falhas || format('%s canais de quem não é streamer', v_qtd); END IF;
    SELECT count(*) INTO v_qtd FROM steam_do_bedo.participa pa
    WHERE NOT EXISTS (SELECT 1 FROM steam_do_bedo.streamerpais s WHERE s.id_streamer = pa.id_streamer);
    IF v_qtd > 0 THEN v_falhas := v_falhas || format('%s participações de quem não é streamer', v_qtd); END IF;
    SELECT count(*) INTO v_qtd FROM steam_do_bedo.canal c
    WHERE NOT EXISTS (SELECT 1 FROM steam_do_bedo.plataformausuario pu
                      WHERE pu.nro_plataforma = c.nro_plataforma AND pu.id_usuario = c.id_streamer);
    IF v_qtd > 0 THEN v_falhas := v_falhas || format('%s canais sem conta do dono na plataforma', v_qtd); END IF;

    -- proporção de comentários com doação (DEC-031: 1% a 5%)
    SELECT 100.0 * (SELECT count(DISTINCT (id_video, seq_comentario)) FROM steam_do_bedo.doacao)
                 / nullif((SELECT count(*) FROM steam_do_bedo.comentario), 0)
    INTO v_pct;
    IF v_pct IS NULL OR v_pct NOT BETWEEN 1 AND 5 THEN
        v_falhas := v_falhas || format('%s%% dos comentários com doação (esperado 1%% a 5%%)', round(v_pct, 2));
    END IF;

    IF cardinality(v_falhas) > 0 THEN
        RAISE EXCEPTION 'seed abortado na conferência: %', array_to_string(v_falhas, '; ');
    END IF;
    RAISE NOTICE 'seed: conferência de sanidade OK (% dos comentários com doação)', round(v_pct, 2) || '%';
END
$$;

COMMIT;

\timing off

-- Estatísticas e visibility map atualizados para as consultas e os
-- índices. Fora da transação, por exigência do VACUUM.
VACUUM (ANALYZE) steam_do_bedo.conversao, steam_do_bedo.pais, steam_do_bedo.empresa,
    steam_do_bedo.empresapais, steam_do_bedo.plataforma, steam_do_bedo.usuario,
    steam_do_bedo.plataformausuario, steam_do_bedo.streamerpais, steam_do_bedo.canal,
    steam_do_bedo.nivelcanal, steam_do_bedo.inscricao, steam_do_bedo.patrocinio,
    steam_do_bedo.video, steam_do_bedo.participa, steam_do_bedo.comentario,
    steam_do_bedo.doacao, steam_do_bedo.bitcoin, steam_do_bedo.paypal,
    steam_do_bedo.cartaocredito, steam_do_bedo.mecanismoplat;

-- Volume final por tabela (evidência para o decisions.md)
SELECT t.tabela, t.tuplas
FROM (
              SELECT 1 AS o, 'Conversao' AS tabela, count(*) AS tuplas FROM steam_do_bedo.conversao
    UNION ALL SELECT 2, 'Pais', count(*) FROM steam_do_bedo.pais
    UNION ALL SELECT 3, 'Empresa', count(*) FROM steam_do_bedo.empresa
    UNION ALL SELECT 4, 'EmpresaPais', count(*) FROM steam_do_bedo.empresapais
    UNION ALL SELECT 5, 'Plataforma', count(*) FROM steam_do_bedo.plataforma
    UNION ALL SELECT 6, 'Usuario', count(*) FROM steam_do_bedo.usuario
    UNION ALL SELECT 7, 'PlataformaUsuario', count(*) FROM steam_do_bedo.plataformausuario
    UNION ALL SELECT 8, 'StreamerPais', count(*) FROM steam_do_bedo.streamerpais
    UNION ALL SELECT 9, 'Canal', count(*) FROM steam_do_bedo.canal
    UNION ALL SELECT 10, 'NivelCanal', count(*) FROM steam_do_bedo.nivelcanal
    UNION ALL SELECT 11, 'Inscricao', count(*) FROM steam_do_bedo.inscricao
    UNION ALL SELECT 12, 'Patrocinio', count(*) FROM steam_do_bedo.patrocinio
    UNION ALL SELECT 13, 'Video', count(*) FROM steam_do_bedo.video
    UNION ALL SELECT 14, 'Participa', count(*) FROM steam_do_bedo.participa
    UNION ALL SELECT 15, 'Comentario', count(*) FROM steam_do_bedo.comentario
    UNION ALL SELECT 16, 'Doacao', count(*) FROM steam_do_bedo.doacao
    UNION ALL SELECT 17, 'BitCoin', count(*) FROM steam_do_bedo.bitcoin
    UNION ALL SELECT 18, 'PayPal', count(*) FROM steam_do_bedo.paypal
    UNION ALL SELECT 19, 'CartaoCredito', count(*) FROM steam_do_bedo.cartaocredito
    UNION ALL SELECT 20, 'MecanismoPlat', count(*) FROM steam_do_bedo.mecanismoplat
) t
ORDER BY t.o;
