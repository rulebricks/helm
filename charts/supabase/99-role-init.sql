-- ============================================================================
-- 99-role-init.sql  -  Rulebricks: in-cluster Supabase Postgres role/ownership init
--
-- The bundled supabase/postgres image ships a PRE-SEEDED data directory. On boot
-- Postgres finds an already-initialized PGDATA and therefore SKIPS everything in
-- /docker-entrypoint-initdb.d, so the chart's role-password script (99-roles.sql)
-- never runs and POSTGRES_PASSWORD is never applied to the service login roles.
-- authenticator / supabase_auth_admin / supabase_admin end up with passwords that
-- don't match the chart secret, and supabase-auth / realtime / rest / meta fail
-- SCRAM auth against the DB and crashloop.
--
-- This script is run on every DB pod start by the `db-role-init` sidecar over a
-- loopback (127.0.0.1) connection, which the image's pg_hba.conf trusts
-- (`host all all 127.0.0.1/32 trust`) — so it works even when the roles still
-- have the unknown baked-in passwords. It:
--   1. (re)sets every Supabase service login role's password to the chart secret
--      (the same shared secret.db.password every service connects with), and
--   2. hands the auth.* helper functions to supabase_auth_admin so GoTrue's
--      bundled migration (CREATE OR REPLACE FUNCTION auth.uid() ...) doesn't fail
--      with "must be owner of function uid" — those functions are baked into the
--      image owned by the bootstrap superuser, not by GoTrue's role.
--
-- Idempotent and existence-guarded: safe to run on every boot, and a no-op on a
-- from-scratch initdb where the bundled init scripts already ran.
-- ============================================================================

\set ON_ERROR_STOP on
\set rolepass `echo "$POSTGRES_PASSWORD"`

-- Stash the desired password in a custom GUC so the server-side DO blocks can read
-- it: psql \set variables are client-side only and are invisible inside DO/EXECUTE.
SELECT set_config('role_init.rolepass', :'rolepass', false);

-- 1. Align every Supabase service login role's password with the chart secret. --
DO $$
DECLARE
  pw       text := nullif(current_setting('role_init.rolepass', true), '');
  rolename text;
  -- All Supabase service/login roles. They exist in the baked image regardless of
  -- which services this trimmed profile actually runs; any missing role is skipped.
  roles   text[] := ARRAY[
    'supabase_admin',              -- realtime, meta (also the superuser)
    'authenticator',               -- rest / PostgREST
    'supabase_auth_admin',         -- auth / GoTrue
    'supabase_storage_admin',
    'supabase_functions_admin',
    'supabase_replication_admin',
    'pgbouncer'
  ];
BEGIN
  IF pw IS NULL THEN
    RAISE EXCEPTION '99-role-init: POSTGRES_PASSWORD is empty - refusing to set blank role passwords';
  END IF;
  FOREACH rolename IN ARRAY roles LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = rolename) THEN
      EXECUTE format('ALTER ROLE %I WITH PASSWORD %L', rolename, pw);
    END IF;
  END LOOP;
END $$;

-- 2. Hand the auth.* helpers to supabase_auth_admin so GoTrue can self-migrate. --
-- GoTrue connects as supabase_auth_admin and its init migration re-creates
-- auth.uid()/auth.role()/... via CREATE OR REPLACE, which requires OWNERSHIP.
DO $$
DECLARE
  fn  text;
  fns text[] := ARRAY['auth.uid()', 'auth.jwt()', 'auth.role()', 'auth.email()'];
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_auth_admin') THEN
    RAISE NOTICE '99-role-init: supabase_auth_admin missing - skipping auth ownership init';
    RETURN;
  END IF;
  FOREACH fn IN ARRAY fns LOOP
    -- to_regprocedure() returns NULL (no error) when the function is absent.
    IF to_regprocedure(fn) IS NOT NULL THEN
      EXECUTE format('ALTER FUNCTION %s OWNER TO supabase_auth_admin', fn);
    END IF;
  END LOOP;
END $$;

\echo '99-role-init.sql complete'
