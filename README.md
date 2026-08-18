# Futebol de Respeito

App para organizar a pelada de domingo: lista de confirmados, reservas automáticas, controle de pagamentos (IBAN / MB Way) e sorteio de três times.

Site estático, sem processo de build. Roda direto no navegador.

**No ar:** https://futebolderespeito.vercel.app

---

## Como funciona

- **Um jogo de cada vez.** O app mostra sempre o próximo jogo com data igual ou posterior a hoje. Todo mundo que abre o link vê o mesmo jogo, a mesma hora e a mesma lista.
- **Cada um entra sozinho.** Quem abre escreve o nome e clica em Entrar. O celular guarda quem é, e a partir daí o app trata a pessoa pelo nome, destaca a linha dela, e deixa ela sair da própria vaga quando quiser.
- **Reservas automáticas.** Quem entra depois de as vagas esgotarem fica em Reservas, por ordem de chegada.
- **Só o organizador confirma pagamento, remove alguém, sorteia os times e abre o jogo da semana.** Todo o resto (entrar, sair da própria vaga, ver a lista) é livre pra qualquer um. Ver a seção **Organizador** abaixo.
- **Uma mensagem pro WhatsApp.** O botão copia a lista já formatada, com confirmados, reservas, times, quanto falta pagar e o IBAN.

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

## Organizador: conta com email e senha, só pros 2

Jogadores nunca criam conta — só os organizadores, e são só eles que ganham a autorização extra (confirmar pagamento, remover alguém, sortear os times, abrir o jogo da semana). Quem tem a conta aparece identificado no topo do app enquanto estiver logado ("Organizador · fulano@email.com"), então dá pra saber quem mexeu no quê.

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
| `IBAN` | Conta que recebe o dinheiro |
| `MBWAY` | Número de MB Way |
| `MAPS_LINK` | Link do Google Maps para o campo |
| `CAMPO` | Texto do botão do mapa |
| `DEFAULTS` | Hora, vagas e valor padrão de um jogo novo |
| `KITS` | Nomes e cores dos três times do sorteio |

Hora, vagas e valor do jogo atual mudam-se dentro do próprio app, na seção **Organização** (só o organizador vê os campos editáveis) — sem tocar no código.

---

## Estrutura

```
index.html           App completo (Preact + htm, sem build)
manifest.json         Instalar no celular como app
icon.svg / icon.png   Ícone
og.png                Imagem do link compartilhado no WhatsApp
supabase/schema.sql   Tabelas, funções e regras de acesso
```

## Deploy

Já está ligado ao Vercel. Cada `git push` para `main` publica em produção.
