# Futebol de Respeito

App para organizar a pelada de domingo: lista de confirmados, fila de pagamento, reservas automáticas e sorteio de três times.

Site estático, sem processo de build. Roda direto no navegador.

**No ar:** https://futebolderespeito.vercel.app

---

## Como funciona

- **Um jogo de cada vez.** O app mostra sempre o próximo jogo com data igual ou posterior a hoje. Todo mundo que abre o link vê o mesmo jogo, a mesma hora e a mesma lista.
- **A vaga só conta depois de paga.** Quem entra escreve o nome e paga na hora, pelo Stripe (cartão, MB Way, Klarna, Bancontact — o que estiver ativo na conta). Até o pagamento ser confirmado, a pessoa fica em **Aguardando pagamento**, sem ocupar vaga. Quem paga primeiro entra primeiro — mesmo que tenha escrito o nome depois de outra pessoa. Isso é de propósito: existe pra ninguém segurar a vaga sem pagar.
- **Confirmação automática.** O Stripe avisa o app sozinho quando o pagamento é aprovado — ninguém precisa clicar em nada pra isso acontecer. O toggle manual (organizador) continua existindo como reserva, pra quando o Stripe falhar ou alguém pagar por fora excepcionalmente.
- **Reservas automáticas.** Quem paga depois de as vagas esgotarem fica em Reservas, por ordem de pagamento.
- **Aviso de prazo.** Quem ainda não pagou vê um aviso vermelho com a contagem até sexta-feira (2 dias antes do jogo).
- **Só o organizador remove alguém, sorteia os times e abre o jogo da semana.** Ver a seção **Organizador** abaixo.
- **Uma mensagem pro WhatsApp.** O botão copia a lista já formatada, com confirmados, reservas, quem ainda está pagando, e os times.

---

## Ativar a lista compartilhada (Supabase)

Sem isto o app funciona, mas guarda tudo só no celular de quem abriu — cada pessoa vê a própria lista. Com o Supabase ligado, todo mundo vê e edita a mesma, em tempo real.

1. Crie um projeto grátis em [supabase.com](https://supabase.com)
2. Vá em **SQL Editor**, cole o conteúdo de `supabase/schema.sql` e rode. Cria as tabelas, as regras de acesso e as funções que o app usa.
3. Vá em **Project Settings → API** e copie o `Project URL` e a chave **anon public** (ou `publishable`, nos projetos mais novos)
4. Abra `index.html` e preencha, logo depois do comentário CONFIGURAÇÃO:
   ```js
   const SUPABASE_URL = "COLOCAR_AQUI";
   const SUPABASE_ANON_KEY = "COLOCAR_AQUI";
   ```
5. `git push` — o Vercel publica sozinho

A chave `anon`/`publishable` é pública por natureza: vai dentro do HTML e qualquer pessoa consegue ler. A segurança está nas regras e funções do `schema.sql`, não nessa chave.

---

## Ativar o pagamento automático (Stripe)

Sem isto o app funciona, mas ninguém consegue pagar pelo app — o botão "Pagar com Stripe" só aparece quando o Supabase está ligado, e falha (com aviso na tela, sem travar nada) se as funções abaixo não estiverem publicadas.

**O que é preciso:**

1. Uma conta Stripe (quem já tem um link de pagamento do Stripe já tem conta).
2. Pegar a **chave secreta** — painel do Stripe → **Desenvolvedores → Chaves de API** → "Chave secreta" (começa com `sk_test_` pra testar, ou `sk_live_` pra valer).
3. No painel do Supabase → **Edge Functions**, criar duas funções (o painel deixa colar o código direto num editor, sem precisar instalar nada):
   - `stripe-create-session` — cola o conteúdo de `supabase/functions/stripe-create-session/index.ts`
   - `stripe-verify-session` — cola o conteúdo de `supabase/functions/stripe-verify-session/index.ts`
4. Em cada uma das duas funções, na aba **Secrets**, adicionar só `STRIPE_SECRET_KEY` com a chave do passo 2. **Não** adicionar `SUPABASE_SERVICE_ROLE_KEY` nem `SUPABASE_URL` — essas duas já existem automaticamente em toda Edge Function; o Supabase nem deixa criar um secret com nome começado por `SUPABASE_`, é reservado.
5. Clicar em **Deploy** nas duas.

A chave secreta nunca vai dentro do código das funções — só nesse separador **Secrets**. O código lê o nome (`Deno.env.get("STRIPE_SECRET_KEY")`), nunca o valor.

**Testar antes de valer:** usa a chave `sk_test_...` primeiro, e paga com um [cartão de teste do Stripe](https://stripe.com/docs/testing) (nenhum dinheiro de verdade se mexe). Só depois de ver o pagamento confirmar sozinho no app, troca a chave pela `sk_live_...`.

O valor cobrado vem sempre do campo **Valor por jogador** do jogo daquela semana — nunca fica preso a um número fixo. Ninguém no navegador consegue mudar esse valor: as duas funções sempre confirmam o preço direto no banco antes de cobrar ou de aceitar como pago.

---

## Organizador: conta com email e senha, só pros 2

Jogadores nunca criam conta — só os organizadores, e são só eles que ganham a autorização extra (remover alguém, sortear os times, abrir o jogo da semana, e confirmar pagamento manualmente se o Stripe falhar). Quem tem a conta aparece identificado no topo do app enquanto estiver logado ("Organizador · fulano@email.com"), então dá pra saber quem mexeu no quê.

**Criar as 2 contas** (depois de rodar o `schema.sql`, uma única vez, pelo painel — não é SQL):

1. No Supabase, vá em **Authentication → Users → Add user → Create new user**
2. Preencha o email e uma senha forte de um organizador, e marque **Auto Confirm User** (assim não precisa confirmar por email)
3. Repita pro segundo organizador

**Usar:** no rodapé do app tem um link discreto, "Área do organizador". Entra com email e senha, e pronto — a sessão dura semanas nesse celular, não precisa logar de novo toda vez. Pra sair, usa o botão "Sair" que aparece no topo quando o modo organizador está ativo.

**Tirar o acesso de alguém:** no painel, **Authentication → Users**, abre a conta da pessoa e clica em **Delete user** (ou só troca a senha, se for temporário). Vale na próxima ação que a pessoa tentar fazer.

**Esqueceu a senha:** no mesmo painel, abre a conta e usa **Reset password**, ou apaga e cria de novo.

---

## Dados do grupo

No topo do `<script type="module">` em `index.html`:

| Constante | O que é |
|---|---|
| `MAPS_LINK` | Link do Google Maps para o campo |
| `CAMPO` | Texto do botão do mapa |
| `DEFAULTS` | Hora, vagas e valor padrão de um jogo novo |
| `KITS` | Nomes e cores dos três times do sorteio |

Hora, vagas e valor do jogo atual mudam-se dentro do próprio app, na seção **Organização** (só o organizador vê os campos editáveis) — sem tocar no código.

---

## Estrutura

```
index.html                          App completo (Preact + htm, sem build)
manifest.json                       Instalar no celular como app
icon.svg / icon.png                 Ícone
og.png                              Imagem do link compartilhado no WhatsApp
supabase/schema.sql                 Tabelas, funções e regras de acesso
supabase/functions/stripe-create-session   Cria a cobrança no Stripe
supabase/functions/stripe-verify-session   Confirma o pagamento e libera a vaga
```

## Deploy

Já está ligado ao Vercel. Cada `git push` para `main` publica em produção.
