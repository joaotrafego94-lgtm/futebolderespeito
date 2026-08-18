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

## Organizador: sem conta, sem senha de email

Em vez de cadastro, os organizadores usam um **código secreto** — o servidor confere na hora de cada ação; a tela nunca decide sozinha quem pode o quê.

**Configurar os códigos** (depois de rodar o `schema.sql`, uma única vez, no SQL Editor):

```sql
insert into admin_secrets (label, hash) values
  ('joao',  crypt('TROQUE-PELO-CODIGO-DO-JOAO', gen_salt('bf'))),
  ('socio', crypt('TROQUE-PELO-CODIGO-DO-SOCIO', gen_salt('bf')));
```

Troque os dois textos entre aspas pelos códigos que só vocês dois vão saber (frase, palavra, o que for — quanto mais comprido e menos óbvio, melhor). O banco guarda só o hash: nem olhando a tabela dá pra descobrir o código de alguém.

**Usar:** no rodapé do app tem um link discreto, "Área do organizador". Digita o código lá, e pronto — fica lembrado nesse celular, não precisa repetir toda semana. Pra sair do modo organizador, usa o botão "Sair" que aparece no topo quando ele está ativo.

**Revogar o acesso de alguém:**
```sql
delete from admin_secrets where label = 'socio';
```
O código antigo para de funcionar na próxima ação que essa pessoa tentar — o app percebe sozinho e volta a tratar o celular dela como o de um jogador comum.

**Se um código vazar ou for esquecido**, é só rodar o `insert` de novo com um valor novo pro mesmo `label` (ou apagar e inserir outra vez).

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
