# Futebol de Respeito

App para organizar a pelada de domingo: lista de confirmados, fila de pagamento e sorteio de três times.

Site estático, sem processo de build. Roda direto no navegador.

**No ar:** https://futebolderespeito.vercel.app

---

## Como funciona

- **Um jogo de cada vez.** O app mostra sempre o próximo jogo com data igual ou posterior a hoje. Todo mundo que abre o link vê o mesmo jogo, a mesma hora e a mesma lista.
- **A vaga só conta depois de paga.** Quem entra escreve o nome e paga na hora, pelo Stripe (cartão, MB Way, Klarna, Bancontact — o que estiver ativo na conta). Até o pagamento ser confirmado, a pessoa fica em **Aguardando pagamento**, sem ocupar vaga. Quem paga primeiro entra primeiro — mesmo que tenha escrito o nome depois de outra pessoa. Isso é de propósito: existe pra ninguém segurar a vaga sem pagar.
- **Confirmação automática.** O Stripe avisa o app sozinho quando o pagamento é aprovado — ninguém precisa clicar em nada pra isso acontecer. O toggle manual (organizador) continua existindo como reserva, pra quando o Stripe falhar ou alguém pagar por fora excepcionalmente.
- **Sem lista de espera.** Assim que as vagas esgotam, ninguém mais entra — nem pagando, nem sendo adicionado por um amigo. Só continua na lista quem já estava.
- **Mensalista paga uma vez por mês, não toda semana.** Quem joga sempre pode virar mensalista em vez de avulso — transfere por IBAN, o organizador confirma, e depois disso confirma presença com um toque todo domingo, sem pagar de novo. Ver a aba **Mensalistas** no app e a seção **Mensalistas** abaixo.
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
3. No painel do Supabase → **Edge Functions**, criar três funções (o painel deixa colar o código direto num editor, sem precisar instalar nada):
   - `stripe-create-session` — cola o conteúdo de `supabase/functions/stripe-create-session/index.ts`
   - `stripe-verify-session` — cola o conteúdo de `supabase/functions/stripe-verify-session/index.ts`
   - `stripe-webhook` — cola o conteúdo de `supabase/functions/stripe-webhook/index.ts`
4. Em `stripe-create-session` e `stripe-verify-session`, na aba **Secrets**, adicionar só `STRIPE_SECRET_KEY` com a chave do passo 2. **Não** adicionar `SUPABASE_SERVICE_ROLE_KEY` nem `SUPABASE_URL` — essas duas já existem automaticamente em toda Edge Function; o Supabase nem deixa criar um secret com nome começado por `SUPABASE_`, é reservado.
5. Clicar em **Deploy** nas três.

A chave secreta nunca vai dentro do código das funções — só nesse separador **Secrets**. O código lê o nome (`Deno.env.get("STRIPE_SECRET_KEY")`), nunca o valor.

**Testar antes de valer:** usa a chave `sk_test_...` primeiro, e paga com um [cartão de teste do Stripe](https://stripe.com/docs/testing) (nenhum dinheiro de verdade se mexe). Só depois de ver o pagamento confirmar sozinho no app, troca a chave pela `sk_live_...`.

O valor do avulso é fixo (`DEFAULTS.price` em `index.html`). Ninguém no navegador consegue mudar esse valor: a função sempre confirma o preço direto no banco antes de cobrar.

Isto é só pro pagamento avulso — mensalista não usa o Stripe, paga por transferência (ver seção **Mensalistas** abaixo).

---

## Webhook: confirma o pagamento mesmo se a pessoa não voltar pro site

A `stripe-verify-session` (acima) só confirma quando a pessoa é redirecionada de volta pro app depois de pagar. Se ela fechar a aba do Stripe antes disso — o que acontece de vez em quando, sobretudo no telemóvel — o pagamento passa, mas o app nunca fica a saber, e a pessoa fica presa em "Aguardando pagamento" apesar de ter pago. A função `stripe-webhook` resolve isso: o Stripe avisa-a diretamente, do lado do servidor, assim que aprova o pagamento — não depende do navegador de ninguém.

**Configurar:**

1. Depois de fazer o Deploy de `stripe-webhook` (passo acima), copia o URL dela — algo como `https://SEU-PROJETO.supabase.co/functions/v1/stripe-webhook`
2. **Importante:** essa função tem de ficar acessível sem a verificação normal do Supabase, porque o Stripe não sabe mandar a chave `apikey`. Procura, nas definições dessa função (não no código), uma opção tipo **"Enforce JWT Verification"** ou **"Verify JWT"** e desliga-a — só para `stripe-webhook`, as outras duas continuam como estão. A segurança desta função vem de outro lado: ela confere sozinha, no código, que quem está a chamar é mesmo o Stripe (usando a assinatura que ele manda em cada pedido).
3. No painel do Stripe → **Desenvolvedores → Webhooks → Add endpoint**
4. Cola o URL do passo 1, e em "Events to send" escolhe só `checkout.session.completed`
5. Depois de criar, o Stripe mostra um **Signing secret** (começa com `whsec_...`) — copia
6. Volta ao Supabase, na função `stripe-webhook` → **Secrets**, adiciona `STRIPE_SECRET_KEY` (a mesma das outras) e `STRIPE_WEBHOOK_SECRET` (o `whsec_...` do passo 5)
7. Deploy de novo

**Testar:** no painel do Stripe, dentro do webhook criado, tem um botão "Send test webhook" — manda um evento `checkout.session.completed` de teste e confere se a função responde `200 ok`. O teste de verdade é o mesmo de sempre: pagar com o cartão de teste, mas desta vez fechando a aba do Stripe assim que aparecer "pagamento aprovado", sem esperar o redirecionamento — o nome deve entrar pago mesmo assim, em poucos segundos.

---

## Mensalistas

Além de pagar avulso (um jogo de cada vez, pelo Stripe), dá pra virar mensalista: transfere a mensalidade por IBAN, o organizador confirma na mão, e depois disso confirma presença com um toque todo domingo, sem pagar de novo. Tem uma aba própria no app ("Mensalistas", ao lado de "Jogo").

**Por que não é automático:** transferência bancária não tem como o app confirmar sozinho, ao contrário do Stripe. Por isso é sempre em dois passos — a pessoa reporta que pagou, o organizador confirma depois de ver o dinheiro cair.

**Como funciona, pra quem paga direto:**

1. Na aba **Mensalistas**, escreve o nome e continua.
2. Aparecem os dados do IBAN (beneficiário, número, valor) e um botão **Copiar IBAN**.
3. Depois de transferir de verdade, toca em **Já transferi**. Isso NÃO ativa nada sozinho — só avisa o organizador. A pessoa fica marcada como "pendente".
4. O organizador vê a pessoa na lista de mensalistas (aba Mensalistas → seção do organizador) com a tag **Pendente** e um botão **✓** — confirma assim que ver o dinheiro na conta.
5. Depois de confirmado, toda semana aparece um botão **"Vou jogar esse domingo"** na aba Jogo — um toque, sem pagar de novo, sem digitar nada. **Não entra sozinho**: quem não confirmar não ocupa vaga, pra não travar lugar de quem quer pagar avulso naquela semana.

**De propósito não reconhece só pelo nome.** Se reconhecesse, qualquer um que soubesse o nome de um mensalista digitaria e entraria de graça. O próprio celular guarda uma "senha" (token) no momento em que reporta o pagamento pela primeira vez — daí em diante o reconhecimento é só por esse token, nunca mais por nome.

**Quem paga por fora, na hora, em dinheiro** (o organizador já recebeu, não precisa de IBAN nem de espera): o organizador adiciona o nome direto na aba Mensalistas, já confirmado. A pessoa, na primeira vez que abrir o app, digita o próprio nome na mesma aba e toca em "Sou eu, confirmar neste aparelho" — sem passar pelo IBAN, sem ficar pendente.

**Renovação também é manual e em dois passos**, igual o pagamento inicial: faltando 5 dias pra vencer, a aba Mensalistas mostra os dados do IBAN de novo e um botão de reportar — a mensalidade continua valendo normalmente enquanto isso espera confirmação, ninguém perde a vaga por estar renovando.

**Trocou de celular?** No painel do organizador, o botão ⟲ ao lado do nome libera o vínculo, e a pessoa reporta ou reivindica de novo no aparelho novo.

**Mensalista não soma na receita da semana** (card "de X€ · Y pagaram" na aba Jogo) — já pagou no mês, confirmar presença não é dinheiro novo entrando naquele domingo.

O valor da mensalidade e o IBAN de destino:
- Mensalidade: campo editável na aba Mensalistas (seção do organizador).
- IBAN/beneficiário: constantes `IBAN_MENSALISTA` e `BENEFICIARIO_MENSALISTA` no topo do `<script type="module">` em `index.html` — não fica escondido em nenhuma Edge Function, é só texto que aparece na tela, então não tem problema nenhum estar direto no código.

Não usa Stripe nem Edge Function nenhuma — é tudo Supabase direto (tabela `members` + as funções `reportar_pagamento_mensal`/`confirm_presence_by_token`/`claim_membership` do `schema.sql`).

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
| `DEFAULTS` | Hora, vagas e valor avulso padrão de um jogo novo |
| `KITS` | Nomes e cores dos três times do sorteio |
| `IBAN_MENSALISTA` | IBAN pra onde a mensalidade é transferida |
| `BENEFICIARIO_MENSALISTA` | Nome que aparece como beneficiário na tela |

Hora e vagas mudam-se dentro do próprio app, na seção **Organização** (só o organizador vê os campos editáveis) — sem tocar no código. Mensalidade muda na aba **Mensalistas**. O valor avulso é fixo (`DEFAULTS.price`, só no código).

---

## Estrutura

```
index.html                          App completo (Preact + htm, sem build)
manifest.json                       Instalar no celular como app
icon.svg / icon.png                 Ícone
og.png                              Imagem do link compartilhado no WhatsApp
supabase/schema.sql                 Tabelas, funções e regras de acesso
supabase/functions/stripe-create-session   Cria a cobrança no Stripe
supabase/functions/stripe-verify-session   Confirma quando a pessoa volta pro site
supabase/functions/stripe-webhook          Confirma direto do Stripe, mesmo sem voltar
```

## Deploy

Já está ligado ao Vercel. Cada `git push` para `main` publica em produção.
