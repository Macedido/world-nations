# 🌍 World Nations

Simulador geopolítico multiplayer em tempo real, no navegador. Cada jogador desenha seu país no mapa-múndi e cuida da economia, política, população, tecnologia, diplomacia, espionagem e guerra. O mundo continua rodando mesmo com todos offline.

- **Site estático** (HTML + React + Leaflet): roda no GitHub Pages, sem build. O mundo é inventado: oceano e relevo são gerados no navegador, e cada país desenhado vira terra de verdade (floresta, montanha, deserto, pântano ou planície).
- **Supabase** (login, PostgreSQL + PostGIS, Realtime): **toda** a regra do jogo roda no banco, em funções SQL validadas. O navegador só pede ações; dinheiro, recursos, tropas e batalhas são calculados no servidor.

## Instalação (uns 10 minutos)

1. Crie um projeto grátis em [supabase.com](https://supabase.com).
2. No painel: **Database → Extensions** → ative **pg_cron** (é o que faz o mundo avançar sozinho a cada 10 min).
3. **SQL Editor** → cole todo o conteúdo de `schema.sql` → **Run**. O script pode ser rodado de novo sem problema.
4. **Authentication → URL Configuration**: em *Site URL* coloque o endereço do seu site (ex.: `https://seunome.github.io/world-nations/`) e adicione o mesmo em *Redirect URLs*. Isso faz funcionar a confirmação de e-mail e a recuperação de senha.
5. **Project Settings → API**: copie a *Project URL* e a chave *anon / publishable* para o arquivo `config.js`. Essa chave é pública, pode ir para o GitHub.
6. Envie os arquivos para um repositório no GitHub → **Settings → Pages** → *Deploy from a branch* → `main` / `root`. Pronto.

Para testar no seu computador: `npx serve .` (ou qualquer servidor estático) e abra o endereço mostrado.

> Teste rápido sem esperar 24h: no SQL Editor rode `update matches set prep_ends = now() where code = 'CODIGO';` e depois clique em **Iniciar partida**.

## Como jogar

1. Crie a conta, crie uma sala e passe o **código** para os amigos.
2. Clique em **Desenhar meu país**: clique no mapa para fazer o formato (arraste os pontos para ajustar, botão direito apaga), marque a capital e escolha nome, bandeira, cor, ideologia e governo. O lugar muda o tamanho: **ilha isolada no oceano encolhe**, **litoral ou perto de vizinhos fica normal**, **interior cercado de vizinhos cresce**. A parte do desenho que encostar em outro país é recortada.
3. Depois das 24h de preparação, o anfitrião inicia a partida. Não existe fim.
4. Menus à esquerda: País, Governo, População, Economia, Infraestrutura, Produção, Militar, Tecnologia, Diplomacia, Comércio, Inteligência e Histórico.
5. No mapa: clique numa região para ver detalhes, construir, recrutar, mover tropas ou atacar. Use as camadas (político, militar, recursos, população, econômico, diplomático) e dê zoom até ver cidades, trens, navios, aviões e pessoas.

## O que tem

| Sistema | Destaques |
|---|---|
| Contas | Cadastro, login, recuperação de senha, nome de usuário, histórico de partidas, salvamento automático |
| Partidas | Código de sala, sala de espera, 24h de preparação, anfitrião inicia, relógio mundial, entrada tardia |
| Mapa | Mundo próprio (oceano, costa, relevo e biomas), 7 camadas, frentes de batalha, 4 níveis de zoom: países → regiões → cidades com ruas, casas, prédios, parques, fábricas com fumaça, portos, aeroportos e fazendas → carros, trens, navios, aviões, pedestres e tropas, com dia e noite |
| País e governo | Líder com retrato, partido, ministros com bônus, leis (impostos, alistamento), emergência, eleições, reformas, ideologias e governos personalizados |
| População | 9 grupos sociais simulados (agricultores, operários, engenheiros, cientistas, comerciantes, servidores, soldados, desempregados, dependentes): cada um só existe se houver emprego, tem satisfação própria e se revolta do seu jeito (greve, bloqueio, motim, golpe, fuga de cérebros, fuga de capitais, saques) |
| Migração | Êxodo interno para regiões com cidades e emprego; migração entre países por guerra, fome, miséria, riqueza e estabilidade; fronteiras abertas, controladas ou fechadas |
| Economia | PIB, receita, despesas, dívida e juros, programas sociais e verba de educação; fábricas transformam matéria-prima em máquinas, equipamento militar, veículos, aviões, navios e produtos industriais (você escolhe a divisão) |
| Infraestrutura | 14 construções com custo, tempo e efeito (fazenda, mina, fábrica, usina, estrada, ferrovia, porto, aeroporto, hospital, escola, universidade, base, centro de pesquisa, cidade) |
| Militar e guerra | 11 tipos de unidade, mão de obra, movimento com tempo real, 9 estratégias, terreno, moral, suprimento, apoio aéreo, ocupação, resistência, rendição, paz |
| Tecnologia | Árvore com 60 pesquisas em 11 categorias, doutrinas militares e armas de destruição em massa (com inspeções e reação mundial) |
| Diplomacia | 9 tipos de tratado, compra/cessão de territórios, paz com reparações, ultimatos, sanções, ajuda (inclusive secreta), alianças e organizações com líder, regras e expulsão; aliados entram na guerra automaticamente |
| Comércio | 16 produtos; preço mundial por escassez, ofertas, lances, volume, guerras e choques de mercado; histórico de 7 dias; livro de ofertas e lances entre países (inclusive exclusivos para membros de uma organização); contratos de fornecimento com entrega automática; mercado negro com contrabandistas, golpes e escândalos |
| Inteligência | Agência com 5 níveis, 7 operações (sabotagem, milícias, espionagem industrial...) com chance de sucesso e descoberta, investigação de responsáveis |
| Instabilidade | Protestos, greves, revoltas, rebeldes, separatismo, golpe de Estado e guerra civil |
| Sala | O dono pode apagar a sala e colocar até 12 bots (pacíficos, equilibrados ou agressivos) que constroem, pesquisam, recrutam, negociam e guerreiam sozinhos |
| Eventos | Descobertas, crises, epidemias, desastres, booms, crise mundial; alguns secretos |

## Arquivos

```
index.html      página
style.css       visual estilo jogo de estratégia histórico
config.js       URL e chave do Supabase
js/icons.js     ícones (game-icons.net)
js/core.js      utilidades
js/terrain.js   oceano, costa, relevo e biomas gerados no navegador
js/city.js      cidades, construções e animações no mapa
js/map.js       mapa, camadas e editor de fronteiras
js/panels.js    menus do jogo
js/app.js       login, salas e tela do jogo
schema.sql      banco completo (tabelas, segurança, regras, motor do tempo)
sql/            o mesmo schema dividido em 3 partes, para ler/editar
```

## Segurança

RLS ligado em todas as tabelas e nenhuma escrita direta: o navegador só chama funções (`build`, `attack`, `market`...) que conferem dono, custo, recursos, requisitos e limite de ações por minuto, e registram tudo em `logs`. Funções internas (com `_`) não podem ser chamadas pelo site. Informações de outros países (tesouro, estoque) só aparecem com espionagem bem-sucedida.

Créditos: ícones de [game-icons.net](https://game-icons.net) (Lorc, Delapouite e outros, licença CC BY 3.0).

Já tem a versão anterior instalada? Só rode o `schema.sql` novo: ele adiciona as colunas e tabelas que faltam sem apagar nada.

Para mudar o equilíbrio do jogo, edite a função `defs()` em `sql/01_base.sql` (custos, tempos, bônus) e rode o SQL de novo.
