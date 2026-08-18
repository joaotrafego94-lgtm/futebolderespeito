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

create policy games_leitura     on games   for select using (true);
create policy games_organizador on games   for all to authenticated using (true) with check (true);
create policy players_leitura   on players for select using (true);
create policy players_organizador on players for all to authenticated using (true) with check (true);

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
--  TEMPO REAL
-- ============================================================
alter table games   replica identity full;
alter table players replica identity full;

do $$
begin
  begin alter publication supabase_realtime add table games;
  exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table players;
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
