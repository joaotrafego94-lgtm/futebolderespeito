-- ============================================================
--  FUTEBOL DE RESPEITO — esquema da base de dados
--  Cola isto inteiro no SQL Editor do Supabase e clica em Run.
--  Pode rodar de novo sem estragar nada.
--
--  QUEM PODE O QUÊ
--    Qualquer pessoa (sem conta nenhuma): ver o jogo, entrar na
--      lista, e sair da própria vaga.
--    Organizador (com login): abrir o jogo da próxima semana,
--      mudar hora/vagas/valor, confirmar pagamentos, tirar
--      qualquer pessoa da lista e sortear os times.
--
--  Os organizadores logam com email + senha (Supabase Auth) —
--  ver o final deste arquivo pra criar as 2 contas. Jogadores não
--  criam conta nenhuma, é só digitar o nome.
-- ============================================================

-- ------------------------------------------------------------
--  JOGOS
-- ------------------------------------------------------------
create table if not exists games (
  game_date  date primary key,
  kickoff    text         not null default '10:00',
  slots      integer      not null default 15,
  price      numeric(6,2) not null default 0,
  teams      jsonb,
  updated_at timestamptz  not null default now()
);

-- Valor da mensalidade (mensalistas, ver mais abaixo) — editável na tela
-- de Organização, igual price/slots já são.
alter table games add column if not exists price_mensal numeric(6,2) not null default 15;

-- ------------------------------------------------------------
--  JOGADORES
--  A ordem de chegada (created_at) decide quem é confirmado e
--  quem fica de reserva.
-- ------------------------------------------------------------
create table if not exists players (
  id         uuid primary key default gen_random_uuid(),
  game_date  date not null references games (game_date) on delete cascade,
  name       text not null,
  paid       boolean not null default false,
  paid_at    timestamptz,
  created_at timestamptz not null default now()
);

-- Versões anteriores deste arquivo não tinham paid_at. Sem isto,
-- "quem paga primeiro" não tem como ser calculado — paid sozinho
-- só diz SE alguém pagou, não QUANDO.
alter table players add column if not exists paid_at timestamptz;

-- De onde veio a vaga: avulso (pagou só essa semana) ou mensalista
-- (já pagou o mês, só confirmou presença). Sem isto o card de dinheiro
-- arrecadado contaria mensalista como receita da semana, que é errado.
alter table players add column if not exists source text not null default 'avulso';

do $$
begin
  alter table players add constraint players_source_check check (source in ('avulso','mensalista'));
exception when duplicate_object then null;
end $$;

create index if not exists players_game_date_idx on players (game_date, created_at);

-- ------------------------------------------------------------
--  SENHA DA VAGA
--  Quando alguém entra, o celular gera uma senha e guarda. Serve
--  só pra provar, na hora de sair, que quem está saindo é o dono
--  da vaga — ninguém tira a vaga de outra pessoa por engano.
-- ------------------------------------------------------------
create table if not exists player_claims (
  player_id uuid primary key references players (id) on delete cascade,
  token     uuid not null
);

-- ------------------------------------------------------------
--  MENSALISTAS
--  Ao contrário de players (que reseta toda semana junto com o
--  jogo), members sobrevive à troca de game_date — "fulano é
--  mensalista até tal data" precisa persistir mês a mês.
--
--  token: nasce quando a própria pessoa paga a mensalidade pelo
--  Stripe, ou fica null quando o organizador cadastra alguém que
--  pagou por fora — nesse caso a pessoa "reivindica" o nome uma
--  única vez no próprio celular (claim_membership) e a partir daí
--  o reconhecimento semanal é só por token, nunca mais por nome.
-- ------------------------------------------------------------
create table if not exists members (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  name_key    text generated always as (lower(btrim(name))) stored,
  token       uuid unique,
  valid_until date not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create unique index if not exists members_name_key_uidx on members (name_key);

-- Tabelas de versões anteriores deste arquivo que não são mais usadas.
drop function if exists admin_set_paid(uuid, boolean, text);
drop function if exists admin_remove_player(uuid, text);
drop function if exists admin_open_game(date, text, integer, numeric, text);
drop function if exists admin_update_game(date, text, integer, numeric, text);
drop function if exists admin_set_teams(date, jsonb, text);
drop function if exists is_admin(text);
drop table if exists admin_secrets;

-- ============================================================
--  REGRAS DE ACESSO
--  games e players: qualquer um lê. Só quem tem login (os 2
--  organizadores) escreve direto na tabela. Jogadores comuns
--  entram/saem pelas funções abaixo, sem precisar de conta.
--  player_claims: ninguém lê nem escreve de fora.
-- ============================================================
alter table games          enable row level security;
alter table players        enable row level security;
alter table player_claims  enable row level security;
alter table members        enable row level security;

-- Limpa políticas de versões anteriores deste arquivo.
drop policy if exists "games_acesso_publico"          on games;
drop policy if exists "players_acesso_publico"        on players;
drop policy if exists "Acesso público de leitura"     on players;
drop policy if exists "Acesso público de escrita"     on players;
drop policy if exists "Acesso público de atualização" on players;
drop policy if exists "Acesso público de remoção"     on players;
drop policy if exists games_leitura         on games;
drop policy if exists games_organizador     on games;
drop policy if exists players_leitura       on players;
drop policy if exists players_organizador   on players;
drop policy if exists members_leitura       on members;
drop policy if exists members_organizador   on members;

create policy games_leitura     on games   for select using (true);
create policy games_organizador on games   for all to authenticated using (true) with check (true);
create policy players_leitura   on players for select using (true);
create policy players_organizador on players for all to authenticated using (true) with check (true);
create policy members_leitura   on members for select using (true);
create policy members_organizador on members for all to authenticated using (true) with check (true);
-- anon nunca escreve direto em members: só via claim_membership /
-- confirm_presence_by_token (security definer, abaixo) ou pelas Edge
-- Functions de pagamento (que usam a service role e ignoram RLS).

-- ============================================================
--  ENTRAR E SAIR SEM CONTA
--  security definer = a função corre com permissões elevadas,
--  por isso consegue escrever apesar da regra acima. Cada uma faz
--  só uma coisa e valida o que recebe.
-- ============================================================

drop function if exists join_game(date, text, uuid);
drop function if exists leave_game(uuid, uuid);

create function join_game(p_date date, p_name text, p_token uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id   uuid;
  v_nome text := btrim(p_name);
begin
  if v_nome = '' or length(v_nome) > 60 then
    raise exception 'Nome inválido';
  end if;
  if not exists (select 1 from games where game_date = p_date) then
    raise exception 'Não há jogo aberto nessa data';
  end if;

  insert into players (game_date, name, paid) values (p_date, v_nome, false)
  returning id into v_id;

  insert into player_claims (player_id, token) values (v_id, p_token);
  return v_id;
end $$;

create function leave_game(p_id uuid, p_token uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare v_ok boolean;
begin
  select exists (
    select 1 from player_claims where player_id = p_id and token = p_token
  ) into v_ok;
  if v_ok then delete from players where id = p_id; end if;
  return v_ok;
end $$;

revoke all on function join_game(date, text, uuid) from public;
revoke all on function leave_game(uuid, uuid)      from public;
grant execute on function join_game(date, text, uuid) to anon, authenticated;
grant execute on function leave_game(uuid, uuid)      to anon, authenticated;

-- ============================================================
--  MENSALISTAS SEM CONTA
--  Mesma filosofia de join_game/leave_game: security definer,
--  valida tudo no servidor, nunca confia no que o navegador manda.
-- ============================================================

drop function if exists confirm_presence_by_token(date, uuid);
drop function if exists claim_membership(text, uuid);

-- Chamada toda vez que o app abre, se o celular já tem um token de
-- mensalista guardado — confirma a presença da semana sem pagar de
-- novo. Reaproveita a vaga se a pessoa já confirmou essa semana
-- (idempotente), nunca duplica.
create function confirm_presence_by_token(p_date date, p_token uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nome   text;
  v_valido date;
  v_id     uuid;
begin
  select name, valid_until into v_nome, v_valido from members where token = p_token;
  if v_nome is null then
    raise exception 'Mensalidade não encontrada';
  end if;
  if v_valido < current_date then
    raise exception 'Mensalidade vencida';
  end if;
  if not exists (select 1 from games where game_date = p_date) then
    raise exception 'Não há jogo aberto nessa data';
  end if;

  select id into v_id from players
    where game_date = p_date and lower(btrim(name)) = lower(v_nome)
    limit 1;
  if v_id is not null then
    insert into player_claims (player_id, token) values (v_id, p_token)
      on conflict (player_id) do nothing;
    return v_id;
  end if;

  insert into players (game_date, name, paid, paid_at, source)
    values (p_date, v_nome, true, now(), 'mensalista')
    returning id into v_id;
  insert into player_claims (player_id, token) values (v_id, p_token);
  return v_id;
end $$;

-- Só pra quem o organizador cadastrou manualmente (pagou por fora,
-- token ainda null). A pessoa digita o próprio nome uma única vez
-- pra vincular o celular; depois disso o nome nunca mais é usado
-- pra reconhecer ninguém, só o token.
create function claim_membership(p_name text, p_token uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id  uuid;
  v_key text := lower(btrim(p_name));
begin
  select id into v_id from members where name_key = v_key and token is null;
  if v_id is null then
    raise exception 'Não encontramos mensalidade sem aparelho vinculado com esse nome';
  end if;
  update members set token = p_token, updated_at = now() where id = v_id;
  return v_id;
end $$;

revoke all on function confirm_presence_by_token(date, uuid) from public;
revoke all on function claim_membership(text, uuid)          from public;
grant execute on function confirm_presence_by_token(date, uuid) to anon, authenticated;
grant execute on function claim_membership(text, uuid)          to anon, authenticated;

-- ============================================================
--  TEMPO REAL
-- ============================================================
alter table games   replica identity full;
alter table players replica identity full;
alter table members replica identity full;

do $$
begin
  begin alter publication supabase_realtime add table games;
  exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table players;
  exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table members;
  exception when duplicate_object then null; end;
end $$;

-- ============================================================
--  ÚLTIMO PASSO — CRIAR AS CONTAS DOS 2 ORGANIZADORES
--  Isto não é SQL, é feito pelo painel do Supabase:
--
--  1. Vá em Authentication → Users → Add user → Create new user
--  2. Preencha email e senha de cada organizador (uma conta por
--     pessoa) e marque "Auto Confirm User" — assim não precisa
--     confirmar por email
--  3. Repita pro segundo organizador
--
--  As senhas ficam só no Supabase, cifradas — nem olhando o
--  painel dá pra ver a senha de alguém depois de criada.
-- ============================================================
