# BitLife × The Gamer Life — análise de lacunas

> Status: todos os itens 🆕 abaixo estão implementados e cobertos por testes (`tests/test_bitlife_depth.gd`, `tests/test_features.gd`), exceto onde marcado ⏭.

Objetivo: igualar a **profundidade** do BitLife sistema por sistema (sem copiar textos, nomes, telas ou valores) e manter nossas camadas extras (Sistema/The Gamer, dungeons, NPCs com memória, economia conectada, consequências atrasadas).

Legenda: ✅ já tínhamos · 🆕 implementado nesta rodada · ➕ nosso diferencial (BitLife não tem) · ⏭ fora de escopo (motivo)

Fontes: wiki da comunidade do BitLife e guias (Level Winner, Gamezebo, Pro Game Guides, Prima Games, Game Rant, Pocket Gamer, Destructoid) — lista completa no fim.

---

## 1. Personagem e atributos

| BitLife | Nós |
|---|---|
| 4 atributos visíveis: Felicidade, Saúde, Inteligência, Aparência | ✅ Saúde, Felicidade, Estresse, Aparência, Disciplina, Reputação + ➕ 7 atributos do Sistema sem teto |
| Ocultos: Atletismo, Disciplina, Fertilidade, **Carma**, **Força de vontade** | ✅ 17 ocultos (fertilidade, talentos, longevidade…) · 🆕 **Carma** (boas/más ações → sorte, longevidade, eventos) · 🆕 **Força de vontade** (vícios, tentação, traição) |
| Traços de NPC: petulância, religiosidade, profissionalismo, loucura, generosidade | ✅ 19 traços · 🆕 generosidade, loucura, religiosidade, profissionalismo como ocultos de NPC que mudam decisões (pedir dinheiro, aceitar pedidos, trair, trabalho) |
| Talentos especiais | ✅ talentos ocultos aceleram skills |
| Signo do zodíaco (compatibilidade) | 🆕 mês de nascimento → signo → bônus/penalidade de compatibilidade |
| Identidade / orientação | ✅ orientação sexual; 🆕 evento de "sair do armário" |
| God Mode (editar tudo) | ✅ painel DEV (não é monetizado) |

## 2. Infância e família

| BitLife | Nós |
|---|---|
| Pais, padrastos, irmãos, meio-irmãos, avós | ✅ |
| Interações: conversar, elogiar, presentear, discutir, insultar, pedir dinheiro, passar tempo | ✅ + memórias persistentes ➕ |
| Pedir coisas aos pais (dinheiro, carro, viagem) | ✅ dinheiro · 🆕 pedir carro (16+), pedir viagem em família |
| Fugir de casa | 🆕 atividade com consequências (rua, abrigo, crime, volta) |
| Herança de família no sótão (minijogo) | 🆕 relíquias no início da vida (evento do sótão) com bônus (ex.: dado da sorte melhora loteria/cassino), passam para herdeiros |
| Animais de estimação | ✅ + ➕ familiares domados |

## 3. Escola

| BitLife | Nós |
|---|---|
| Notas (estudar mais, matar aula) | ✅ |
| **Popularidade** | 🆕 atributo escolar |
| **Panelinhas** (com requisito de popularidade) | 🆕 8 grupos com requisitos e efeitos |
| **Extracurriculares** com ranking até capitão | 🆕 clubes/times com posto (membro → titular → capitão), aumentam popularidade e chance de bolsa |
| Interagir com professor/diretor | 🆕 pedir ajuda, bajular, pedir carta de recomendação; ida à diretoria (evento) |
| Colar na prova, bullying (fazer e sofrer) | ✅ eventos · 🆕 praticar bullying em colegas |
| Faculdade, pós (medicina, direito, negócios, odonto, farmácia, veterinária, enfermagem) | ✅ + 🆕 cursos que faltavam (farmácia, veterinária, enfermagem, odontologia) |
| Bolsa, pais pagam, empréstimo estudantil | ✅ |
| Fraternidades | 🆕 panelinha universitária |

## 4. Trabalho

| BitLife | Nós |
|---|---|
| Centenas de empregos com requisitos | ✅ 53 (dados, escalável) |
| **Entrevista com perguntas** | 🆕 2 perguntas sorteadas por candidatura, respostas ligadas a atributos |
| Trabalhar mais, pedir aumento, demitir-se, aposentar | ✅ |
| **Horas por semana** | 🆕 meio período / normal / hora extra (salário, estresse, desempenho, tempo livre) |
| Colegas e chefe: elogiar, pegadinha, competir, flertar | ✅ elogiar/flertar · 🆕 pegadinha, competir por promoção |
| Processar o empregador | 🆕 processos (ver §8) |
| Bicos/freelance/meio período adolescente | ✅ |
| Aposentadoria/pensão | ✅ |

## 5. Carreiras especiais (pacotes pagos no BitLife: 10)

| BitLife | Nós |
|---|---|
| Músico | ✅ |
| Atleta | ✅ |
| Empresário | ✅ |
| Político | ✅ |
| Criador de conteúdo / redes | ✅ + 🆕 conquistas de verificação (100 mil) e estrela (350 mil) |
| **Ator** (figurante → testes → séries/filmes → prêmios) | 🆕 |
| **Astronauta** (curso STEM, academia espacial, missões) | 🆕 |
| **Máfia** (reputação criminal, famílias, ordens, hierarquia) | 🆕 |
| **Modelo** (agência, trabalhos, desfiles) | 🆕 |
| **Ambulante / Street hustler** (artes de rua, pedintes, etc.) | 🆕 |
| Traficante (Dealer) | ⏭ drogas ilícitas: substituído por contrabando de artefatos de mana na Máfia |
| **Militar** (Exército, Marinha, Aeronáutica, Fuzileiros; patentes, missões, desertar) | 🆕 |
| **Realeza** (nascer nobre, reputação real, trono, abdicar) | 🆕 |
| ➕ Caçador/Arcanista/Agente/Mestre de Guilda (Despertos) | ✅ nosso |

## 6. Amor, casamento e fertilidade

| BitLife | Nós |
|---|---|
| Procurar amor, encontros, namoro | ✅ |
| **App de namoro** (escolher entre perfis) | 🆕 3 perfis com aparência, idade, emprego, traços visíveis |
| Pedir em casamento, casar, **fugir para casar**, acordo pré-nupcial | ✅ + 🆕 fugir para casar (barato, família se ofende) |
| Viajar juntos, discutir, trair | ✅ + 🆕 viagem a dois |
| Divórcio com partilha | ✅ |
| **FIV (gêmeos/trigêmeos)**, **barriga de aluguel**, adoção, vasectomia/laqueadura, doação | 🆕 FIV, barriga de aluguel, gêmeos, vasectomia/laqueadura · ✅ adoção |
| Ficar (hookup) | 🆕 marcado como conteúdo adulto |

## 7. Crime

| BitLife | Nós |
|---|---|
| Furto em loja, batedor de carteira, arrombamento, roubo de carro, fraude, assalto | ✅ |
| Delinquência (vandalismo), roubo de encomendas | 🆕 |
| Desvio de dinheiro (exige emprego) | 🆕 |
| **Assalto a banco** (escolher banco, arma, disfarce, fuga) | 🆕 planejamento em 4 etapas, cada escolha muda a chance |
| Assalto a trem | 🆕 (versão: carro-forte) |
| Assassinato (vários métodos) | 🆕 conteúdo adulto, com evidência, investigação e perpétua |
| Máfia | 🆕 carreira especial |
| Investigação posterior | ✅ ➕ (BitLife é mais imediato) |

## 8. Justiça

| BitLife | Nós |
|---|---|
| Julgamento com escolha de advogado | 🆕 defensor público / barato / caro |
| Recurso com escritórios de advocacia | ✅ recurso · 🆕 defensor público × escritório barato × de elite (preço, chance, vitória parcial que reduz a pena) |
| **Processos judiciais** (processar alguém) | 🆕 processar empregador, médico, vizinho, ex |
| Multas, condicional | ✅ multas · 🆕 liberdade condicional por bom comportamento |

## 9. Prisão

| BitLife | Nós |
|---|---|
| Malhar, biblioteca, trabalho | ✅ |
| Pátio: elogiar, provocar, insultar, agredir presos | 🆕 interações com presos + reação |
| **Gangues** | 🆕 entrar, proteção, brigas entre gangues, ser expulso |
| Subornar guarda | 🆕 |
| **Motim** (minijogo) | 🆕 motim como ação de risco (gangue ajuda; fuga ou +3 anos) — sem minijogo próprio |
| **Fuga** (minijogo em grade) | 🆕 minijogo real na interface (guarda anda 2 casas por turno) |
| Visitas / pacotes | 🆕 visitas de familiares (vínculo) |
| Condicional por bom comportamento | 🆕 |

## 10. Saúde

| BitLife | Nós |
|---|---|
| ~100 doenças | ✅ 18 · 🆕 +22 (total 40) (resfriado, acne, apendicite, artrite, bronquite, catapora, enxaqueca, pedra no rim, gota, insônia, obesidade, pneumonia, intoxicação alimentar, fratura, bulimia, bipolaridade, TOC, Alzheimer, ISTs [adulto], hérnia, catarata, osteoporose) |
| Médico ocidental × alternativo | 🆕 médico, curandeiro alternativo (barato, pouco eficaz), pronto-socorro |
| Psiquiatra, reabilitação | ✅ terapia/reabilitação · 🆕 psiquiatra (medicação) |
| Cirurgia plástica (várias, pode dar errado) | 🆕 7 procedimentos com risco |
| Salão & Spa | 🆕 cabelo, unhas, massagem, tratamento facial |
| Depressão ao zerar felicidade | ✅ |

## 11. Atividades e lazer

| BitLife | Nós |
|---|---|
| Mente & Corpo: academia, meditar, biblioteca, dieta, caminhada, artes marciais, jardinagem, yoga | ✅ parcial · 🆕 biblioteca, caminhada, jardinagem, yoga, dieta (tipos), **peso** |
| Vida noturna / baladas | 🆕 balada com evento de 3 caminhos (dançar, camarote VIP, ir embora) |
| Cassino (blackjack), loteria, corrida de cavalos | ✅ cassino/loteria · 🆕 blackjack (minijogo), corrida de cavalos com odds |
| Férias, peregrinação | 🆕 férias (destinos), peregrinação (carma) |
| Licenças: motorista, barco, piloto | 🆕 exigidas para comprar veículos |
| Emigrar (com aprovação) | ✅ + 🆕 pedido de visto com chance (patrimônio, emprego, reputação, ficha) |
| Redes sociais | ✅ |

## 12. Patrimônio

| BitLife | Nós |
|---|---|
| Casas, carros, joias, instrumentos, aviões, barcos | ✅ + 🆕 joias (charme) e instrumentos (aprendizado de skills) |
| Reformar, alugar, despejar | ✅ alugar · 🆕 reformar |
| Relíquias de família | 🆕 |
| Testamento | 🆕 cônjuge / filhos iguais / filho favorito / caridade (carma) |

## 13. Meta

| BitLife | Nós |
|---|---|
| **Fitas (ribbons)** no túmulo (~40) | 🆕 24 fitas calculadas na morte, coleção entre vidas |
| Conquistas | ✅ 22 · 🆕 +30 |
| Desafios semanais / cenários | ✅ desafios |
| **Máquina do tempo** (premium) | 🆕 "Ponto de Salvamento" do Sistema: voltar até 5 anos ao morrer, custa Pontos de Alma |
| Continuar como filho | ✅ + ➕ herança do Sistema |

---

## O que continua sendo diferencial nosso (BitLife não tem)
- Sistema de jogo completo (níveis, 7 atributos sem teto, skills que evoluem e se fundem, títulos, missões, ranks de evolução).
- Dungeons, monstros, drops, devorar habilidades, familiares nomeados.
- NPCs com memória que esmaece conforme a personalidade.
- Consequências agendadas anos depois (crimes investigados, empréstimos, traições).
- Economia mundial conectada (ciclos, inflação, mercados, fendas) que afeta empregos, imóveis e empresas.
- Chances visíveis nas escolhas.

## Fontes
- BitLife Wiki (Fandom): Activities, Crime, Prison/Activities, Relationships, Stats, Careers, Assets, Heirloom, Will/Testament, Plastic Surgery, Ribbons, God Mode, Diseases, Education, Social Media, Mind & Body, Salon & Spa.
- Level Winner: guias das versões 1.21 (prisão), 1.23 (escola), 1.28 (amigos), 1.29 (crime), 1.33 (God Mode), redes sociais.
- Gamezebo: guias 1.21, 1.23, heirlooms, schools list.
- Pro Game Guides: special careers, schools, promoção, redes sociais, riot, heirlooms, discipline.
- Prima Games, Game Rant, Pocket Gamer, Destructoid, Gfinity, Charlie INTEL.

## Números atuais do conteúdo

| Conteúdo | Quantidade |
|---|---|
| Eventos | 119 (com cadeias e consequências agendadas) |
| Empregos | 58 + 12 carreiras especiais |
| Atividades | 91 |
| Interações sociais | 38 |
| Doenças/condições | 40 |
| Habilidades do Sistema | 51 |
| Conquistas | 52 · Fitas | 24 · Desafios | 9 |
| Cursos (escola → pós) | 25 |
| Crimes | 16 |

## Balanceamento verificado por simulação (vidas completas com bot)
- Jogador casual: morre com ~64–70 anos; causas: velhice, doenças crônicas acumuladas, câncer, pneumonia.
- Jogador focado no Sistema: nível ~18 aos 18 anos, ~75 aos 40, 200+ ao morrer; 10% morrem em dungeons.
- Bug encontrado e corrigido pela simulação: o peso subia rápido demais e deixava quase todos obesos aos 30.
