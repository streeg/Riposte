# Checklist de lançamento - Riposte 1.0.0

## 1. Regras das permissões do Graded Defense (mod 951)
- [x] Modificar e lançar melhorias: permitido
- [x] Subir em outro lugar: permitido, com crédito (kudos no README, na página e no LICENSE)
- [ ] **Donation Points: DESLIGAR** para o Riposte. As permissões dele proíbem ganhar DP com mods que usam os assets dele.
- [ ] Não vender, nem usar em mod pago

## 2. Mídia
- [x] `media/circle-approach.jpg`: anel se aproximando
- [x] `media/circle-perfect.jpg`: anel na janela perfeita
- [x] `media/learning-new-attack.jpg`: primeira vez de um ataque ("NEW ATTACK · LEARNING TIMING")
- [ ] Subir as 3 imagens na aba Images do Nexus; primeira imagem da página: `circle-perfect.jpg`
- [ ] Legenda da imagem de aprendizado: "First time an attack plays: Riposte learns its timing. From then on the ring is shown."
- [ ] (Opcional, mas aumenta muito o download) GIF ou vídeo de 10-20 s com um GRAZE. Win+Alt+R grava com a Xbox Game Bar.

## 3. Página do Nexus
- [ ] Título: **Riposte - Timing Circle and Grace Period**
- [ ] Resumo: "A timing circle for every enemy hit, and a grace period that turns near-miss dodges and parries into reduced damage."
- [ ] Descrição: colar `nexus/description.bbcode`
- [ ] Categoria: Gameplay
- [ ] Tags: Gameplay, User Interface, Quality of Life, **AI-Generated Content** (obrigatório)
- [ ] Requisitos: RE-UE4SS (link externo: https://github.com/UE4SS-RE/RE-UE4SS/releases)
- [ ] Versão: 1.0.0
- [ ] Permissões: Modification e Upload liberados com crédito (combina com MIT); Donation Points desligado

## 4. Arquivos (rodar `python build.py`, eles saem em `dist/`)
| Arquivo | Categoria | Descrição curta |
|---|---|---|
| Riposte-1.0.0.zip | Main | Standard: early 0.25 s, late 0.20 s, max 90 % |
| Riposte-Preset-Forgiving-1.0.0.zip | Optional | Bigger grace windows, for tough bosses |
| Riposte-Preset-Strict-1.0.0.zip | Optional | Small grace windows, close to vanilla |
| Riposte-Preset-TrainerOnly-1.0.0.zip | Optional | Circle only, vanilla damage rules |
| Riposte-Preset-GraceOnly-1.0.0.zip | Optional | Grace period only, no circle |

## 5. Teste final numa instalação limpa
- [ ] Remover/desativar o GradedDefense
- [ ] Extrair `Riposte-1.0.0.zip` na pasta do jogo e abrir
- [ ] UE4SS.log mostra "[Riposte] v1.0.0 loaded" e os 8 "hooked", sem "error in"
- [ ] Uma luta: círculo, GRAZE, Ctrl+F8 mostra "TIMING RESET"
- [ ] Aplicar um preset por cima e conferir que o jogo abre
