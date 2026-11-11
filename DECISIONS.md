# Registro de Decisões de Projeto

## Objetivo

Documentar as decisões de projeto tomadas ao longo da evolução do mesmo

Cada decisão tem um identificador `DEC-NNN`, atribuído em ordem sequencial e
nunca reutilizado. Decisões que afetam o `ddl.sql` são referenciadas lá por um
comentário `-- DEC-NNN`.

A partir da DEC-005, cada decisão traz a linha **Aplicada no DDL: sim/não**.
`não` significa que o `ddl.sql` ainda não reflete a decisão; ela só passa a
`sim` quando o grupo pedir a alteração do DDL.

Números ausentes na sequência pertencem a decisões descartadas e não são reutilizados.

---

## DEC-001 · Procedure do item 6: gasto mensal por usuário em USD

`sp_obter_qtd_canais_e_gasto_mensal_por_usuario(p_nick_usuario)` retorna, por
usuário, em quantos canais ele é membro e quanto desembolsa por mês, em moeda
local e em dólares (USD).

### Como funciona

- Une `usuario`, `inscricao`, `nivelcanal`, `pais` e `conversao`.
- `NivelCanal` é o catálogo de níveis de assinatura de cada canal (nome do
  nível, `valor`, `gif`). `Inscricao` liga o usuário a um nível de um canal, e
  o `valor` mensal vem de `NivelCanal.valor`.
- Retorna `qtd_canais`, `moeda`, `vr_mensal_moeda_local` e `vr_mensal_usd`.
- A conversão é `valor * Conversao.fator_conver`, onde o fator é de moeda para USD.
- Ordena por `vr_mensal_usd` decrescente. O filtro por usuário é opcional.

### Premissas

1. **Moeda do valor (interpretação nossa, não explícita no minimundo):** o
   minimundo diz que o patrocínio tem valor "em dólares americanos", mas não
   informa a moeda do valor do nível de membro (nem da doação). Ele diz apenas
   que cada usuário tem um país de residência, que cada país tem uma moeda e que
   cada moeda tem um fator "para conversão do valor da moeda estrangeira para
   dólares americanos". Como o usuário é a única entidade da inscrição ligada a
   um país, interpretamos que `NivelCanal.valor` está na moeda do país de
   residência do usuário (`Usuario.pais_residencia` -> `Pais.moeda`) e o
   convertemos para USD. Leituras alternativas, que mudariam a conversão: o valor
   já estar em USD (como o patrocínio) ou estar na moeda do canal/streamer.
2. **Usuário sem país de residência (escolha nossa):** o minimundo não diz se o
   país de residência é obrigatório e a DDL aceita nulo. Nesse caso o usuário é
   tratado como USD (fator 1), para não sumir do resultado.
3. **Periodicidade (prevista no minimundo):** o minimundo diz que o membro
   contribui com um valor mensal conforme o nível e que o sistema não armazena
   o histórico de membros. Logo, "por mês" é o valor mensal atual das
   inscrições vigentes, e não um histórico mês a mês.

---

## DEC-002 · Procedure do item 9: top-k canais por aportes de membros em USD

`sp_obter_top_k_canais_por_aportes_de_membros(p_k)` retorna os `p_k` canais que
mais recebem aportes de membros, com a quantidade de membros e o valor total
mensal em dólares (USD).

### Como funciona

- Une `inscricao`, `nivelcanal`, `usuario`, `pais` e `conversao` e agrupa por
  canal (`nome_canal`, `nro_plataforma`).
- O aporte de cada membro é o `NivelCanal.valor` do nível em que está inscrito,
  convertido para USD por `Conversao.fator_conver`.
- Retorna `qtd_membros` e `vr_total_aportes` (já em USD), ordenados por
  `vr_total_aportes` decrescente, com desempate por `nome_canal`, limitados a
  `p_k` linhas.

### Premissas

1. **Reaproveita as premissas do item 6:** o valor do nível é tratado como
   mensal e na moeda do país de residência do membro, e membro sem país de
   residência é tratado como USD (fator 1). Veja a seção do item 6, que traz a
   justificativa e o que o minimundo diz ou não diz. Se a premissa de moeda
   mudar, os itens 6 e 9 devem mudar juntos.
2. **Conversão antes de somar (escolha nossa):** a conversão é feita por membro,
   antes da soma por canal. Sem ela, a soma misturaria moedas diferentes e o
   ranking entre canais não seria comparável.
3. **Vigência (prevista no minimundo):** o sistema não armazena o histórico de
   membros, então só as inscrições vigentes entram no cálculo.
4. **Valor de `p_k` (escolha nossa):** com `p_k` nulo o `LIMIT` do PostgreSQL não
   limita e a função devolve todos os canais.

---

## DEC-003 · Procedure do item 10: top-k canais por doações recebidas

`sp_obter_top_k_canais_por_doacoes_recebidas(p_k)` retorna os `p_k` canais que
mais receberam doações, somando todos os vídeos do canal.

### Premissas

1. **Doações recusadas ficam de fora (escolha nossa):** o minimundo define o status
   da doação como `recusado`, `recebido` ou `lido`. Doação recusada não foi
   recebida, então só entram `recebido` e `lido`. É o mesmo critério dos itens 4 e 7.
2. **Sem conversão de moeda:** o minimundo não informa a moeda do valor da doação,
   então o valor é somado como está. Se a doação for em moeda local, a soma mistura
   moedas (ponto em aberto, igual ao dos itens 4 e 7).
3. **Sem join com `video` e `comentario`:** `Doacao` já carrega a chave do canal e
   do vídeo, então agrupar por canal já cobre "todos os vídeos".
4. **Só canais com doação aparecem**, e `p_k` nulo devolve todos (comportamento do
   `LIMIT` do PostgreSQL).

---

## DEC-004 · Procedure do item 11: top-k canais por faturamento total

`sp_obter_top_k_canais_por_faturamento(p_k)` retorna os `p_k` canais que mais
faturam, com o valor de cada fonte (`vr_patrocinio`, `vr_membros`, `vr_doacoes`) e
o `vr_faturamento_total`, todos em USD.

### Premissas

1. **Fontes de receita:** patrocínio (já em USD segundo o minimundo), membros
   (valor do nível convertido para USD, mesma premissa dos itens 6 e 9) e doações
   recebidas (sem recusadas, mesma regra do item 10).
2. **Doação não é convertida (ponto em aberto):** como o minimundo não diz a moeda
   da doação, ela entra na soma como está. Se for em moeda local, o total do item
   11 mistura moedas.
3. **Combinação por `UNION ALL`:** cada fonte é lida separadamente e só então
   somada por canal. Unir as três tabelas com `JOIN` multiplicaria as linhas de uma
   fonte pelas da outra e inflaria os valores.
4. **Canal sem nenhuma receita não aparece**, e `p_k` nulo devolve todos.
5. **Observação sobre os dados do seed:** o patrocínio domina o faturamento (na
   ordem de 10^5 USD por canal) e o valor de membros é pequeno (dezenas de USD),
   então o ranking é praticamente o do item 8.

---

## DEC-005 · Tipo de `Plataforma.nro` e de `nro_plataforma`: INTEGER

O enunciado diz que a plataforma é "identificada por um número sequencial
único". Escolhemos `INTEGER` (4 bytes) para `Plataforma.nro` e para todas as
colunas `nro_plataforma` que o referenciam, em vez de `BIGINT`.

### Cálculo da capacidade

- `BIGINT`: 2^63 − 1 = 9.223.372.036.854.775.807 (≈ 9,22 × 10^18).
- `INTEGER`: 2^31 − 1 = 2.147.483.647 (≈ 2,15 × 10^9).
- `SMALLINT`: 2^15 − 1 = 32.767.
- Uma coluna `GENERATED ALWAYS AS IDENTITY` começa em 1 e não dá a volta
  (sem `CYCLE`), então todos esses valores são utilizáveis.

### Por que INTEGER

1. **Demanda real é minúscula:** existem dezenas de plataformas de streaming no
   mundo, talvez poucas centenas. Mesmo a escala de 1.000 plataformas do seed v1
   usa ≈ 5 × 10^-5 % da capacidade de `INTEGER`. A população mundial (≈ 8 × 10^9)
   já passa do limite de `INTEGER`, e plataformas não chegam perto disso.
2. **BIGINT é desperdício:** serve para mais que ~10^18 registros. A 10^9
   inserções por segundo, esgotá-lo levaria ≈ 292 anos (9,22 × 10^18 / 10^9 /
   31.536.000 s). Folga desse tamanho não traz benefício aqui.
3. **O custo do tipo se multiplica:** `nro_plataforma` é parte da chave de
   `Canal`, `Video`, `Comentario`, `Doacao` e das 4 tabelas de pagamento, e se
   repete em todos os índices de PK e FK dessas tabelas. Cada linha dessas
   tabelas, e de cada índice, carrega 4 bytes a menos com `INTEGER`.
4. **Por que não SMALLINT:** 32.767 também cobre o mundo real, mas deixa pouca
   margem para uma escala sintética grande (seed v2 parametrizável) e a
   diferença de 2 bytes por coluna tende a ser absorvida pelo alinhamento das
   colunas vizinhas. `INTEGER` é o ponto de equilíbrio.

### Premissas e limites

- A escolha pressupõe que o número de plataformas nunca passa de 2,1 bilhões.
  Se isso deixar de valer, o tipo deve ser revisto.
- O ganho de espaço **não foi medido**; o argumento é por tamanho de tipo e
  repetição na chave. Medir é pendência para a evidência do relatório.
- `Empresa.nro` é tratado separadamente na DEC-008.
- **Efeito das DEC-014, 015 e 017:** com `id_canal` e `id_video`, as tabelas
  filhas deixam de repetir `nro_plataforma`. A coluna passa a existir só em
  `Plataforma.nro`, `Canal.nro_plataforma` e `PlataformaUsuario.nro_plataforma`.
  O argumento 3 acima (custo repetido nas tabelas grandes) vale então apenas para
  o modelo sem surrogates; com elas, o ganho do `INTEGER` é pequeno e a escolha
  vale por consistência de critério.

### Aplicada no DDL: sim
Onde: `Plataforma.nro`, `Canal.nro_plataforma` e `PlataformaUsuario.nro_plataforma` como `INTEGER` no `ddl.sql`.

O `ddl.sql` continua com `BIGINT`. Para aplicar, trocar para `INTEGER`:
`Plataforma.nro`, `Canal.nro_plataforma` e `PlataformaUsuario.nro_plataforma`.
As demais colunas `nro_plataforma` (`Patrocinio`, `NivelCanal`, `Inscricao`,
`Video`, `Participa`, `Comentario`, `Doacao`, `BitCoin`, `PayPal`,
`CartaoCredito`, `MecanismoPlat`) são removidas pela DEC-014, DEC-015 e DEC-017,
e não precisam de troca de tipo.
Uma versão com `ALTER TABLE ... TYPE INTEGER` nas 14 colunas, antes das
surrogates, foi testada em banco descartável (roda sem erro, 50 constraints
mantidas, sequência da identity também vira `integer`) e depois retirada do
arquivo.

---

## DEC-006 · Identidade da plataforma: `UNIQUE (nome, empresa_fund)`

(Revisada: a versão anterior pedia `UNIQUE (nome)`.)

O minimundo identifica a plataforma pelo número sequencial (`nro`, a PK) e não
diz que o nome é único. Decidimos que a **identidade de negócio** da plataforma é
o par **nome + empresa fundadora**: não pode haver duas plataformas com o mesmo
nome e a mesma fundadora.

### Por que `empresa_fund` e não `empresa_resp`

- A empresa fundadora é um fato histórico e não muda. A empresa responsável pode
  mudar (venda, fusão, reestruturação). Colocar `empresa_resp` na constraint
  faria uma troca de responsável parecer uma nova identidade.
- Ambas as colunas são `NOT NULL`, então a constraint não tem a brecha de
  múltiplos NULLs do `UNIQUE`.

### Por que faz sentido

1. Duas linhas com o mesmo nome e a mesma fundadora seriam o mesmo fato
   duplicado, o que o enunciado proíbe ("sem redundância").
2. Permite homônimos de fundadoras diferentes (nomes não são globalmente únicos
   no mundo real), o que `UNIQUE (nome)` proibiria.
3. Barato: `Plataforma` é pequena e estável; o índice B-tree da constraint pesa
   dezenas de kB. Como a coluna `nome` vem primeiro, o mesmo índice atende
   buscas só por nome.
4. Compatível com os dados: no seed v1, 1.000 plataformas, 0 pares
   `(nome, empresa_fund)` repetidos.

### Premissas e limites

- A constraint é **mais fraca** que `UNIQUE (nome)`: aceita duas plataformas com
  o mesmo nome se a fundadora for diferente. É a escolha do grupo.
- Depende da premissa de que `empresa_fund` realmente nunca muda. Se mudar, a
  identidade muda junto.
- `UNIQUE` diferencia maiúsculas de minúsculas (`Twitch` ≠ `twitch`).
- O índice da constraint não entra no limite de 5 índices de apoio, na leitura do
  grupo (PK e UNIQUE tratados como constraints). Ponto a confirmar com o professor.
- O seed v2 precisa gerar pares `(nome, empresa_fund)` distintos.

### Aplicada no DDL: sim
Onde: `Plataforma`, constraint `plataforma_nome_fund_key UNIQUE (nome, empresa_fund)`.

Hoje `Plataforma` não tem nenhuma constraint UNIQUE (conferido em
`pg_constraint`). Para aplicar: `UNIQUE (nome, empresa_fund)` na criação de
`Plataforma` ou `ALTER TABLE steam_do_bedo.Plataforma ADD CONSTRAINT
plataforma_nome_fund_key UNIQUE (nome, empresa_fund);`.

---

## DEC-007 · Data de inscrição do membro nas procedures de membros (itens 6, 9 e 11)

Trecho do minimundo: "Cada membro inscrito contribui com um valor mensal que
depende do seu nível de membro. Existem cinco níveis de membros e os nomes e os
valores de cada nível são definidos para cada canal."

### Validação (verificada no código)

As procedures **não consideram data de inscrição**, e hoje **não conseguem**:

- `Inscricao` tem só `nome_canal`, `nro_plataforma`, `nick_membro` e `nivel`.
  Não existe coluna de data (conferido no `ddl.sql`).
- Os itens 6 (`sp_obter_qtd_canais_e_gasto_mensal_por_usuario`) e 9
  (`sp_obter_top_k_canais_por_aportes_de_membros`) somam `NivelCanal.valor` de
  todas as inscrições existentes. O item 11 repete o mesmo cálculo de membros.
- O valor vem do nível, e o nível é resolvido pela chave
  `(nome_canal, nro_plataforma, nivel)`, o que respeita o trecho "valores de cada
  nível definidos para cada canal".

### Ponto de atenção

O trecho citado **não menciona data**. O texto só pede o valor mensal por nível
e diz que o sistema guarda apenas membros vigentes (sem histórico). Com isso, o
cálculo atual (somar o valor mensal de cada inscrição vigente) está coerente com
o minimundo. A data só passaria a ser exigência se o grupo decidir que ela muda
o resultado, por exemplo: ignorar inscrições com data futura, ou limitar a uma
data de referência.

### Correção proposta (se o grupo adotar)

1. **Esquema:** adicionar a `Inscricao` a coluna
   `data_inscricao DATE NOT NULL DEFAULT CURRENT_DATE`. Os dados do seed v1 e do
   v2 passam a precisar dessa coluna, com data posterior à data do canal
   (`Canal.data`).
2. **Procedures (itens 6, 9 e 11):** acrescentar o parâmetro opcional
   `p_data_ref DATE DEFAULT CURRENT_DATE` e o filtro
   `i.data_inscricao <= p_data_ref` na parte de membros. O valor continua sendo
   o mensal do nível, sem proporcionalizar por dias (não há histórico para isso).
3. **Consistência:** a regra "data da inscrição não anterior ao início do canal"
   envolve outra tabela e não cabe em `CHECK`; seria trigger. "Não maior que
   hoje" também não cabe em `CHECK` (expressão não imutável).
4. **Índices:** nenhum novo. O filtro por data é aplicado depois do JOIN pela
   chave de `Inscricao`, e o orçamento de 5 índices não deve ser gasto aqui sem
   EXPLAIN que mostre ganho.

### Aplicada no DDL: sim
Onde: `Inscricao.data_inscricao DATE NOT NULL DEFAULT CURRENT_DATE`; `p_data_ref` nos itens 6, 9 e 11 do `procedures.sql`.

---

## DEC-008 · Tipo de `Empresa.nro` e das colunas que o referenciam: INTEGER

Segue a lógica da DEC-005, mas com um argumento de capacidade diferente.

### Cálculo da capacidade

- `INTEGER`: 2^31 − 1 = 2.147.483.647 (≈ 2,15 × 10^9).
- `BIGINT`: 2^63 − 1 ≈ 9,22 × 10^18.
- `Empresa` guarda fundadoras, responsáveis e patrocinadoras. Mesmo que o banco
  tentasse catalogar todas as empresas do mundo, a ordem de grandeza é de
  centenas de milhões (estimativa nossa, não verificada em fonte), abaixo de
  2,15 × 10^9 com folga de cerca de uma ordem de grandeza. Para o escopo real
  (empresas ligadas a streamers de jogos), o uso é muito menor.

### Diferença para a DEC-005

- Para plataformas a demanda é de dezenas, e `INTEGER` sobra por muitos ordens
  de grandeza. Para empresas a folga é menor, mas `INTEGER` continua suficiente.
  Por isso **não** se escolhe `SMALLINT` aqui: 32.767 pode ser ultrapassado em
  uma escala sintética grande.
- O ganho de espaço é **menor** que o da DEC-005. `Empresa.nro` é referenciado
  só por `Plataforma` (`empresa_fund`, `empresa_resp`), `EmpresaPais`
  (`nro_empresa`) e `Patrocinio` (`nro_empresa`), todas tabelas pequenas ou
  médias, fora das chaves das tabelas grandes (`Comentario`, `Doacao`). A
  escolha vale mais por consistência de critério do que por economia medida.

### Premissas e limites

- Pressupõe menos de 2,1 bilhões de empresas. Se deixar de valer, rever o tipo.
- O ganho de espaço **não foi medido**.
- Se a DEC-005 mudar de tipo, avaliar esta junto.

### Aplicada no DDL: sim
Onde: `Empresa.nro`, `Plataforma.empresa_fund`/`empresa_resp`, `EmpresaPais.nro_empresa` e `Patrocinio.nro_empresa` como `INTEGER`.

O `ddl.sql` continua com `BIGINT`. Para aplicar, trocar para `INTEGER`:
`Empresa.nro`, `Plataforma.empresa_fund`, `Plataforma.empresa_resp`,
`EmpresaPais.nro_empresa` e `Patrocinio.nro_empresa`. Não foi testado em banco
descartável.

---

## DEC-009 · `Empresa`: não adicionar `UNIQUE (nome, nome_fantasia)`

### Validação

A proposta **não faz sentido como está**:

- `Empresa.nome` já é `UNIQUE`. Se `nome` é único sozinho, qualquer par
  `(nome, nome_fantasia)` também é, então a constraint composta não protege nada
  e só cria um índice a mais.
- `nome_fantasia` é nulável. Em `UNIQUE`, NULLs contam como distintos (a menos
  de `NULLS NOT DISTINCT`, PostgreSQL 15+), então o par com `nome_fantasia`
  nulo nunca violaria a regra.

### Decisão

Manter `UNIQUE (nome)` como está. Se o grupo quiser permitir razões sociais
repetidas com nomes fantasia diferentes, a alternativa é **remover** `UNIQUE
(nome)` e usar o par com `NULLS NOT DISTINCT`. Mas a identidade real da empresa é
o identificador nacional por país (`EmpresaPais`), e não o nome.

Dados do seed v1: 0 pares `(nome, nome_fantasia)` repetidos e 0 nulos em
`nome_fantasia`.

### Aplicada no DDL: não se aplica

Nada a alterar: `UNIQUE (nome)` já existe (`empresa_nome_key`).

---

## DEC-010 · `Conversao`: `nome` é UNIQUE e `moeda` continua como PK

### `UNIQUE (nome)`: sim

Duas moedas com o mesmo nome seriam duplicata. A tabela é pequena e o custo do
índice é desprezível.

### `UNIQUE (moeda, nome)`: não

Como `moeda` é a PK, qualquer conjunto de colunas que a contenha já é único. A
constraint composta nunca seria violada sozinha e cria um índice sem função. A
unicidade útil é `UNIQUE (nome)`, só no nome.

### `moeda` como PK: faz sentido

- É o código ISO 4217 de 3 letras (USD, BRL, EUR): curto, estável, imutável e
  já usado como identificador no mundo real.
- É referenciado por `Pais.moeda`. Uma chave natural de 3 caracteres é mais
  estreita e legível que uma surrogate, e a tabela é pequena (dezenas de linhas
  no mundo real), sem ganho em trocá-la.
- Vários países compartilham a mesma moeda (Euro), o que é uma relação 1:N
  correta: `Pais.moeda` não é único.
- Seed v1: todas as 1.000 moedas casam com `^[A-Z]{3}$` e os 1.000 nomes são
  distintos.

### Aplicada no DDL: sim
Onde: `Conversao`, constraint `conversao_nome_key UNIQUE (nome)`.

`Conversao` hoje só tem a PK em `moeda`. Para aplicar: `UNIQUE (nome)` na criação
ou `ALTER TABLE steam_do_bedo.Conversao ADD CONSTRAINT conversao_nome_key UNIQUE
(nome);`.

---

## DEC-011 · `Usuario`: `email` e `telefone` são UNIQUE (cada um sozinho)

### Decisão

Duas constraints separadas: `UNIQUE (email)` e `UNIQUE (telefone)`. Não é um
`UNIQUE (email, telefone)`, que só barraria o par idêntico e deixaria o mesmo
email com telefones diferentes.

### Validação

- **Email:** identifica a conta na prática. Faz sentido. `NOT NULL` já existe.
- **Telefone:** o minimundo diz que serve para "validação em duas vias". Um
  telefone amarrado a uma conta é coerente com essa finalidade, mas no mundo
  real telefones são compartilhados (família). É regra do grupo, não verdade do
  domínio.
- **Brecha de NULL:** `telefone` é nulável no DDL, e `UNIQUE` aceita vários
  NULLs. Para a regra valer para todos, `telefone` precisa ser `NOT NULL`, o
  que também decorre do texto ("um telefone"). Premissa a confirmar.
- **Maiúsculas e minúsculas:** `UNIQUE (email)` trata `A@x.com` e `a@x.com`
  como diferentes. A alternativa é um índice único sobre `lower(email)`.
- **Custo:** `Usuario` é uma das maiores tabelas no seed v2. São dois índices B-tree
  a mais, cada um atualizado em todo INSERT. Entram como constraints, fora dos 5
  índices de apoio, na leitura do grupo.
- Seed v1: 4.000 usuários, 0 emails repetidos, 0 telefones repetidos, 0 telefones
  nulos.

### Aplicada no DDL: sim
Onde: `Usuario`, constraints `usuario_email_key` e `usuario_telefone_key` (`telefone` segue nulável).

`Usuario` hoje não tem UNIQUE além da PK. Para aplicar: `UNIQUE (email)` e
`UNIQUE (telefone)` na criação, ou dois `ALTER TABLE ... ADD CONSTRAINT`, e
`telefone` como `NOT NULL` se a premissa for aceita.

---

## DEC-014 · `Canal`: surrogate `id_canal` com `UNIQUE (nome, nro_plataforma)`

### Avaliação da chave composta atual

A PK `(nome, nro_plataforma)` é **correta**, mas cara. `nome VARCHAR(255)` e
`nro_plataforma` aparecem em 11 tabelas (`Patrocinio`, `NivelCanal`, `Inscricao`,
`Video`, `Participa`, `Comentario`, `Doacao`, `BitCoin`, `PayPal`,
`CartaoCredito`, `MecanismoPlat`). Em todas elas fazem parte da PK e da FK, e
portanto de cada linha e de cada índice. Nas tabelas grandes (`Comentario`,
`Doacao`) isso pesa.

### Alternativas

1. **Manter a chave composta:** correto, sem mudança, custo de largura mantido.
2. **PK só em `nome`:** o enunciado diz "identificado por seu nome único", mas
   a mesma pessoa pode ter canais de mesmo nome em plataformas diferentes
   ("um ou mais canais associados a cada streamer em diferentes plataformas").
   Seria uma restrição que o domínio não garante. Os 1.287 nomes do seed v1 são
   todos distintos, mas isso é característica do gerador.
3. **Surrogate (escolhida):** `id_canal INTEGER GENERATED ALWAYS AS IDENTITY`
   como PK, e `UNIQUE (nome, nro_plataforma)` para preservar a identidade de
   negócio. As tabelas filhas passam a ter `id_canal` (4 bytes) no lugar de
   `nome_canal` + `nro_plataforma`.

### Por que a surrogate

- Reduz a largura de linha, de PK e de FK nas tabelas filhas.
- A identidade natural continua protegida pelo `UNIQUE`.
- `INTEGER`: coerente com DEC-005 e DEC-008. Estimativa nossa, não verificada:
  mesmo as maiores plataformas têm centenas de milhões de canais, abaixo de
  2,15 × 10^9. A folga é menor que a das plataformas; rever se a escala mudar.

### Custos e limites

- Um índice a mais em `Canal` (o do `UNIQUE`), pequeno frente aos ganhos nas
  filhas.
- As procedures que hoje devolvem `nome_canal` e `nro_plataforma` direto das
  tabelas filhas precisarão de `JOIN` com `Canal` para obter o nome. Esse custo
  precisa ser medido com `EXPLAIN (ANALYZE, BUFFERS)`.
- Exige reescrever o DDL, os seeds e as procedures. **Não foi medido** o ganho
  de espaço nem o custo do `JOIN` extra.
- Interage com a DEC-015 (surrogate em `Video`): o ganho em `Comentario` e
  `Doacao` é maior se as duas forem adotadas juntas. Medição na DEC-017.
- A leitura de "nome único" adotada: único **por plataforma** (como já está no
  DDL).

### Aplicada no DDL: sim
Onde: `Canal` com `canal_pkey (id_canal)` e `canal_nome_plataforma_key`; `Patrocinio`, `NivelCanal`, `Inscricao` e `Video` referenciam `id_canal`.

`Canal` hoje tem `PRIMARY KEY (nome, nro_plataforma)`, e as 11 tabelas filhas o
referenciam.

---

## DEC-015 · `Video`: surrogate `id_video` baseado em `id_canal`

### Validação

Faz sentido. `Video` é referenciado por `Participa`, `Comentario`, `Doacao` e
pelas 4 tabelas de pagamento, e hoje cada uma repete `nome_canal`,
`nro_plataforma`, `titulo` e `dataH` (4 colunas, duas delas largas) em PK e FK.
O enunciado também sugere avaliar identificador artificial para `Video` e
dependentes.

### Decisão

- `id_video BIGINT GENERATED ALWAYS AS IDENTITY` como PK.
- `id_canal` (DEC-014) substitui `nome_canal` + `nro_plataforma`; é FK para `Canal`.
- A identidade de negócio é preservada com `UNIQUE (id_canal, titulo, dataH)`.
  **Sim, faz sentido:** sem isso nada impediria dois vídeos com o mesmo título e
  data/hora no mesmo canal, o que o enunciado proíbe ("identificado por seu
  título e data/hora de postagem").
- `titulo` e `dataH` precisam ser declarados `NOT NULL`: deixam de ser PK, e só a
  PK os tornava obrigatórios.
- Filhas passam a referenciar só `id_video`. `Participa` fica com
  `PK (id_video, nick_streamer)`.
- Tipo `BIGINT` (e não `INTEGER` como em DEC-005, 008 e 014): vídeos são a
  entidade com mais crescimento. Estimativa nossa, não verificada: só as grandes
  plataformas têm bilhões de vídeos, acima do limite de 2,15 × 10^9 do `INTEGER`.

### Custos e limites

- Um índice a mais em `Video` (o do `UNIQUE`). Como `id_canal` vem primeiro, ele
  atende também as buscas "vídeos de um canal" (itens 2 e 3), que hoje usam o
  prefixo da PK composta.
- Exige reescrever DDL, seeds e procedures. Procedures que hoje devolvem
  título ou data direto das filhas passam a precisar de `JOIN` com `Video`.
- Ganho medido em `Comentario`: ver DEC-017.

### Aplicada no DDL: sim
Onde: `Video` com `video_pkey (id_video)` e `video_canal_titulo_datah_key`; `Participa` com `participa_pkey (id_video, nick_streamer)`.

`Video` hoje tem `PRIMARY KEY (nome_canal, nro_plataforma, titulo, dataH)`.

---

## DEC-016 · Constraints `CHECK` para valores numéricos

### Validação

Faz sentido e é barato: `CHECK` não cria índice, então não consome os 5 índices
de apoio, e custa só a avaliação da expressão no INSERT/UPDATE. No seed v1,
nenhuma linha viola nenhuma das regras abaixo.

Uma ressalva: "maior que 0" **não vale para tudo**. Contadores podem ser zero
(canal novo sem visualizações, plataforma sem usuários), então esses recebem
`>= 0`.

### Decisão

| Coluna | Regra | Motivo |
|---|---|---|
| `Conversao.fator_conver` | `> 0` | fator zero ou negativo anula ou inverte a conversão |
| `Patrocinio.valor` | `> 0` | patrocínio vigente com valor zero não existe |
| `NivelCanal.valor` | `> 0` | nível pago |
| `Doacao.valor` | `> 0` | vale também para doação recusada |
| `Comentario.seq` | `> 0` | número sequencial a partir de 1 |
| `Doacao.seq_pg` | `> 0` | idem |
| `Doacao.seq_comentario` | `> 0` | idem |
| `MecanismoPlat.seq_plataforma` | `> 0` | idem |
| `Video.duracao` | `> INTERVAL '0'` | vídeo tem duração (nulo continua permitido) |
| `Plataforma.qtd_users` | `>= 0` | derivado, pode ser zero |
| `Canal.qtd_visualizacoes` | `>= 0` | derivado, pode ser zero |
| `Video.visu_simul`, `Video.visu_total` | `>= 0` | contadores |
| `Video` | `visu_simul <= visu_total` | o pico simultâneo não excede o total (acréscimo do grupo: confirmar) |

- Ids `IDENTITY` não precisam de `CHECK`: começam em 1.
- `CHECK` com coluna nula passa (resultado desconhecido), então as colunas
  nuláveis (`duracao`, `visu_*`) só são validadas quando preenchidas.

### Aplicada no DDL: sim
Onde: 13 `CHECK` nomeados `*_check` (`conversao`, `patrocinio`, `nivelcanal`, `doacao`, `comentario`, `mecanismoplat`, `video`, `plataforma`, `canal`); `visu_simul <= visu_total` não aplicada.

O `ddl.sql` hoje só tem `CHECK` em `Canal.tipo` e `Doacao.status`. Para aplicar:
`CHECK` na criação ou `ALTER TABLE ... ADD CONSTRAINT ... CHECK (...)`.

---

## DEC-017 · `Comentario` com Canal e Video com surrogate: aguenta o crescimento?

### Pergunta

Mesmo com `id_canal` e `id_video`, `Comentario` é a maior tabela e tende a
crescer muito. A chave resultante aguenta?

### Evidência (teste real, banco descartável, apagado depois)

1.000.000 de comentários (50.000 vídeos × 20), inserção em ordem aleatória, mesmos
dados nas 4 variantes, depois `VACUUM ANALYZE`. `nick` ~13 caracteres, título ~36,
nome de canal ~18.

| Variante | PK | Tabela | Índices | Total | Tempo de INSERT |
|---|---|---|---|---|---|
| A (atual) | `(nome_canal, nro_plataforma, titulo, dataH, nick, seq)` | 195 MB | 156 MB | 352 MB | 11,2 s |
| B | `(id_video, nick, seq)` | 135 MB | 62 MB | 196 MB | 7,2 s |
| C | `(id_video, seq)` | 135 MB | 38 MB | 173 MB | 5,3 s |
| D | `id_comentario` identity + `UNIQUE (id_video, seq)` | 142 MB | 59 MB | 201 MB | 6,3 s |

Resultado: a variante C reduz o índice em 76% (156 → 38 MB), o total em 51% e o
tempo de INSERT em 52% frente à atual. B (manter `nick` na PK) perde a maior
parte do ganho. D (id próprio) fica entre B e C, porque o `UNIQUE` recria um
índice.

### Decisão

1. A surrogate em `Canal` e `Video` **resolve a maior parte** do problema, mas
   o ganho completo só aparece **retirando `nick_usuario` da PK**: como `seq` já é
   único por vídeo, `PK (id_video, seq)` identifica o comentário.
   `nick_usuario` fica `NOT NULL` com FK para `Usuario`.
2. `seq` como `INTEGER` (comentários por vídeo cabem com folga em 2,15 × 10^9);
   `id_video` segue `BIGINT` (DEC-015).
3. `Doacao` referencia `(id_video, seq_comentario)` e não repete `nick_usuario`,
   que é determinado pelo comentário. Isso também reduz redundância. As 4
   tabelas de pagamento ficam com chave `(id_video, seq_comentario, seq_doacao)`.
   Logo, `Doacao` fica com `PK (id_video, seq_comentario, seq_pg)` e FK para
   `Comentario (id_video, seq)`.
4. **Se o volume ultrapassar o que um índice B-tree único comporta bem**
   (centenas de milhões de linhas), o passo seguinte é particionar
   `Comentario` por `HASH (id_video)`. A PK `(id_video, seq)` já contém a chave de
   partição, o que o PostgreSQL exige para PK em tabela particionada. Não
   recomendado agora: com 1.000 a 10.000 linhas por tabela não há ganho.
5. O que sobra pesando na linha é `nick_usuario` (texto) e `texto` (vai para TOAST
   quando grande). Surrogate em `Usuario` reduziria o primeiro; não foi medido nem
   decidido.

### Consequência a resolver depois

`seq` é "um número sequencial que depende do vídeo". Gerar `max(seq)+1` por vídeo
tem risco de concorrência: duas inserções simultâneas no mesmo vídeo podem
calcular o mesmo número, e a segunda falha pela PK. Uma `SEQUENCE` global não
serve, porque numera todos os vídeos juntos. A estratégia de geração **não está
decidida**; precisa ser definida antes da etapa de triggers, e até lá o seed
informa `seq` explicitamente.

### Limites da medição

- Dados sintéticos, uma única execução, tabela isolada sem FKs (as FKs
  acrescentam custo a todas as variantes) e sem concorrência.
- Os tempos são relativos entre as variantes; os valores absolutos dependem da
  máquina.
- O ganho em consultas não foi medido (as procedures ainda não foram reescritas).

### Aplicada no DDL: sim
Onde: `comentario_pkey (id_video, seq)`, `doacao_pkey (id_video, seq_comentario, seq_pg)` e PK `(id_video, seq_comentario, seq_doacao)` em `BitCoin`, `PayPal`, `CartaoCredito` e `MecanismoPlat`.

`Comentario` hoje tem PK de 6 colunas
`(nome_canal, nro_plataforma, titulo_video, dataH_video, nick_usuario, seq)`.

