-- ============================================================================
-- bootstrap.sql  -  Rulebricks: external-database prerequisites for Supabase
--
-- Prepares an EXTERNAL managed Postgres (AWS RDS / Aurora, Azure Flexible Server,
-- GCP Cloud SQL, ...) to run the chart's Supabase services with the bundled
-- supabase/postgres disabled (supabase.db.enabled=false). Normally invoked by the
-- db-bootstrap-job.yaml Helm hook; can also be run by hand with psql.
--
-- Replaces the init scripts baked into the supabase/postgres image. Creates ONLY
-- what the trimmed "auth + app-db + realtime" profile needs. Installs NO
-- Supabase-custom extensions (pgsodium / vault / pg_graphql / pg_net / wrappers).
--
-- Idempotent - safe to re-run on every upgrade. Runs with rds_superuser-level
-- privileges (NOT true superuser); on RDS, run as the master user (named postgres).
-- Validated on PostgreSQL 16 (RDS 16.9 and Azure Flexible Server 16).
--
-- Required psql variables (pass with -v name=value):
--   authenticator_password       password for the PostgREST login role
--   auth_admin_password          password for the GoTrue login role
--   replication_admin_password   password for the Realtime/replication login role
--   admin_password               password for supabase_admin (Studio/postgres-meta)
--   storage_admin_password       password for supabase_storage_admin (Storage API)
--   app_role                     role that runs your APP migrations (default: postgres)
-- ============================================================================

\set ON_ERROR_STOP on
\if :{?app_role}
\else
  \set app_role postgres
\endif

-- ---------------------------------------------------------------------------
-- Roles
-- ---------------------------------------------------------------------------

-- PostgREST-exposed roles (no login; authenticator switches into them)
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN NOINHERIT;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN NOINHERIT;
  END IF;
END $$;

-- service_role bypasses RLS for trusted backend calls. BYPASSRLS needs an elevated
-- role; rds_superuser can set it on most providers. Fall back + warn if not allowed
-- (then grant it later with a superuser-equivalent role).
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'service_role') THEN
    BEGIN
      CREATE ROLE service_role NOLOGIN NOINHERIT BYPASSRLS;
    EXCEPTION WHEN insufficient_privilege THEN
      CREATE ROLE service_role NOLOGIN NOINHERIT;
      RAISE WARNING 'service_role created WITHOUT BYPASSRLS - grant it with: ALTER ROLE service_role BYPASSRLS;';
    END;
  END IF;
END $$;

-- authenticator: the login role PostgREST connects as
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticator') THEN
    CREATE ROLE authenticator LOGIN NOINHERIT;
  END IF;
END $$;
ALTER ROLE authenticator WITH PASSWORD :'authenticator_password';
GRANT anon, authenticated, service_role TO authenticator;

-- supabase_auth_admin: GoTrue connects as this; owns + self-migrates the auth schema
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'supabase_auth_admin') THEN
    CREATE ROLE supabase_auth_admin LOGIN NOINHERIT CREATEROLE;
  END IF;
END $$;
ALTER ROLE supabase_auth_admin WITH PASSWORD :'auth_admin_password';

-- supabase_replication_admin: Realtime connects as this to read the WAL
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'supabase_replication_admin') THEN
    CREATE ROLE supabase_replication_admin LOGIN NOINHERIT;
  END IF;
END $$;
ALTER ROLE supabase_replication_admin WITH PASSWORD :'replication_admin_password';

-- Replication capability for the Realtime role. The mechanism is provider-specific
-- and we auto-detect by probing for each provider's group role:
--   * AWS RDS / Aurora : the REPLICATION attribute is NOT grantable; you get it via
--                        membership in rds_replication.
--   * Azure Flexible    : grant membership in azure_pg_admin AND set the REPLICATION
--                        attribute (ALTER ROLE ... REPLICATION).
--   * GCP Cloud SQL      : grant membership in cloudsqlsuperuser AND set REPLICATION
--                        (requires cloudsql.logical_decoding=on / enable_pglogical=on).
--   * Self-managed/local : set the REPLICATION attribute directly (needs superuser).
-- Each ALTER ROLE ... REPLICATION is wrapped so a failure warns instead of aborting.
DO $$
DECLARE
  provider text;
BEGIN
  IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'rds_replication') THEN
    provider := 'aws_rds';
    -- RDS gives replication via rds_replication membership (the attr isn't settable).
    -- Role is NOINHERIT, so grant WITH INHERIT TRUE (PG16+) or it can't use slots.
    EXECUTE 'GRANT rds_replication TO supabase_replication_admin WITH INHERIT TRUE';
  ELSIF EXISTS (SELECT FROM pg_roles WHERE rolname = 'azure_pg_admin') THEN
    provider := 'azure_flexible_server';
    EXECUTE 'GRANT azure_pg_admin TO supabase_replication_admin';
    BEGIN
      EXECUTE 'ALTER ROLE supabase_replication_admin WITH REPLICATION';
    EXCEPTION WHEN insufficient_privilege THEN
      RAISE WARNING 'Azure: could not set REPLICATION - run as the server admin (azure_pg_admin member).';
    END;
  ELSIF EXISTS (SELECT FROM pg_roles WHERE rolname = 'cloudsqlsuperuser') THEN
    provider := 'gcp_cloud_sql';
    EXECUTE 'GRANT cloudsqlsuperuser TO supabase_replication_admin';
    BEGIN
      EXECUTE 'ALTER ROLE supabase_replication_admin WITH REPLICATION';
    EXCEPTION WHEN insufficient_privilege THEN
      RAISE WARNING 'GCP: could not set REPLICATION - ensure cloudsql.logical_decoding=on and run as cloudsqlsuperuser.';
    END;
  ELSE
    provider := 'self_managed';
    BEGIN
      EXECUTE 'ALTER ROLE supabase_replication_admin WITH REPLICATION';
    EXCEPTION WHEN insufficient_privilege THEN
      RAISE WARNING 'Could not set REPLICATION on supabase_replication_admin - set it with a superuser-equivalent role.';
    END;
  END IF;
  RAISE NOTICE 'Replication configured for provider: %', provider;
END $$;

-- supabase_admin: the login role Supabase Studio's introspection backend
-- (postgres-meta) connects as. On the bundled supabase/postgres image this is a
-- superuser; on managed Postgres we cannot create one, so we grant it the
-- provider's admin/superuser group where available (same probe as the
-- replication role) plus the app roles, so Studio can see every schema. Without
-- it Studio fails with "password authentication failed for user supabase_admin"
-- and cannot load schemas or tables. The grant is best-effort (warns, not fatal).
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'supabase_admin') THEN
    CREATE ROLE supabase_admin LOGIN CREATEROLE CREATEDB;
  END IF;
END $$;
ALTER ROLE supabase_admin WITH PASSWORD :'admin_password';
GRANT anon, authenticated, service_role, authenticator,
      supabase_auth_admin, supabase_replication_admin TO supabase_admin;
DO $$
BEGIN
  IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'rds_superuser') THEN
    BEGIN EXECUTE 'GRANT rds_superuser TO supabase_admin';
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'Could not grant rds_superuser to supabase_admin: %', SQLERRM; END;
  ELSIF EXISTS (SELECT FROM pg_roles WHERE rolname = 'azure_pg_admin') THEN
    BEGIN EXECUTE 'GRANT azure_pg_admin TO supabase_admin';
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'Could not grant azure_pg_admin to supabase_admin: %', SQLERRM; END;
  ELSIF EXISTS (SELECT FROM pg_roles WHERE rolname = 'cloudsqlsuperuser') THEN
    BEGIN EXECUTE 'GRANT cloudsqlsuperuser TO supabase_admin';
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'Could not grant cloudsqlsuperuser to supabase_admin: %', SQLERRM; END;
  END IF;
END $$;

-- supabase_storage_admin: the Storage API connects as this and owns the storage
-- schema. Created even when Storage is not deployed so it can be enabled later
-- with no manual DB work (mirrors the bundled image).
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'supabase_storage_admin') THEN
    CREATE ROLE supabase_storage_admin LOGIN NOINHERIT CREATEROLE;
  END IF;
END $$;
ALTER ROLE supabase_storage_admin WITH PASSWORD :'storage_admin_password';

-- ---------------------------------------------------------------------------
-- Schemas
-- ---------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS realtime;
CREATE SCHEMA IF NOT EXISTS "_realtime";   -- Realtime v2.76+ requires this; not auto-created
CREATE SCHEMA IF NOT EXISTS extensions;
-- storage / graphql_public exist on the bundled image (created by the Storage
-- service and pg_graphql). PostgREST is configured to expose
-- public,storage,graphql_public and fails its ENTIRE schema cache (PGRST002 ->
-- every REST query 500s) if any is missing, so create them here even when
-- Storage / pg_graphql are absent on managed Postgres. They stay empty until
-- those components populate them.
CREATE SCHEMA IF NOT EXISTS storage;
CREATE SCHEMA IF NOT EXISTS graphql_public;

-- Hand auth to GoTrue's admin role (requires membership in the target role)
GRANT supabase_auth_admin TO CURRENT_USER;
ALTER SCHEMA auth OWNER TO supabase_auth_admin;

-- Realtime connects as supabase_replication_admin and runs its own Ecto
-- migrations into the _realtime schema (it issues `SET search_path TO _realtime`
-- on connect). On the bundled supabase/postgres image a superuser owns these
-- schemas; on an external DB the bootstrap runner (master) owns them, so the
-- replication role can't create its migration tables and Realtime crashloops
-- with "3F000 no schema has been selected to create in". Hand _realtime to it and
-- grant CREATE on realtime (where app migrations later add tables to the
-- supabase_realtime publication). Idempotent.
ALTER SCHEMA "_realtime" OWNER TO supabase_replication_admin;
GRANT ALL ON SCHEMA realtime TO supabase_replication_admin;

GRANT USAGE ON SCHEMA extensions TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA auth TO anon, authenticated, service_role;

-- Storage schema is owned by its admin role (Storage self-migrates it when the
-- service is deployed); the exposed roles need USAGE so PostgREST can introspect.
ALTER SCHEMA storage OWNER TO supabase_storage_admin;
GRANT USAGE ON SCHEMA storage TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA graphql_public TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- auth.* helper functions used by RLS policies.
-- IMPORTANT: these are created by the supabase/postgres image init scripts, NOT
-- by GoTrue. On an external DB they will not exist unless created here. Your
-- policies call auth.uid(), so this block is mandatory.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT COALESCE(
    nullif(current_setting('request.jwt.claim', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')
  )::jsonb
$$;

CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT COALESCE(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (auth.jwt() ->> 'sub')
  )::uuid
$$;

CREATE OR REPLACE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS $$
  SELECT COALESCE(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (auth.jwt() ->> 'role')
  )
$$;

CREATE OR REPLACE FUNCTION auth.email() RETURNS text LANGUAGE sql STABLE AS $$
  SELECT COALESCE(
    nullif(current_setting('request.jwt.claim.email', true), ''),
    (auth.jwt() ->> 'email')
  )
$$;

GRANT EXECUTE ON FUNCTION auth.jwt(), auth.uid(), auth.role(), auth.email()
  TO anon, authenticated, service_role;

-- GoTrue connects as supabase_auth_admin and its init migration re-creates
-- auth.uid()/auth.role() via CREATE OR REPLACE, which requires OWNERSHIP. These
-- functions were just created by the bootstrap runner (master), so GoTrue's
-- migration would fail with "must be owner of function uid". Hand them to
-- supabase_auth_admin (CURRENT_USER is a member of it, granted above) so GoTrue
-- can self-migrate. Idempotent: re-running leaves ownership unchanged.
ALTER FUNCTION auth.jwt()   OWNER TO supabase_auth_admin;
ALTER FUNCTION auth.uid()   OWNER TO supabase_auth_admin;
ALTER FUNCTION auth.role()  OWNER TO supabase_auth_admin;
ALTER FUNCTION auth.email() OWNER TO supabase_auth_admin;

-- ---------------------------------------------------------------------------
-- Extensions  (on the stock RDS allowlist, but NOT enabled by default on every
-- provider). Azure Flexible Server requires uuid-ossp/pgcrypto to be present in
-- the azure.extensions server parameter first, else CREATE EXTENSION raises
-- "not allow-listed for users" and - with ON_ERROR_STOP on - aborts the whole
-- bootstrap before the publication/grants below ever run. Make each best-effort
-- so bootstrap stays portable; gen_random_uuid() is built into PG13+ core, and
-- if the app needs uuid_generate_*() the operator allow-lists uuid-ossp.
-- ---------------------------------------------------------------------------
DO $$ BEGIN
  CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'uuid-ossp not created (%, SQLSTATE %) - on Azure add UUID-OSSP to the azure.extensions server parameter if your app needs uuid_generate_*().', SQLERRM, SQLSTATE;
END $$;
DO $$ BEGIN
  CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'pgcrypto not created (%, SQLSTATE %) - gen_random_uuid() is in PG13+ core; allow-list pgcrypto only if other pgcrypto functions are needed.', SQLERRM, SQLSTATE;
END $$;

-- pg_stat_statements is observability only (not required by the app). It needs
-- shared_preload_libraries (RDS parameter group) AND superuser/rds_superuser to
-- create. Resilient so bootstrap stays portable across providers.
DO $$ BEGIN
  BEGIN
    CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
  EXCEPTION WHEN insufficient_privilege OR undefined_file OR feature_not_supported THEN
    -- feature_not_supported (0A000) is how Azure Flexible Server reports a
    -- not-allow-listed extension; without it ON_ERROR_STOP aborts bootstrap here.
    RAISE WARNING 'pg_stat_statements not created (needs superuser-equivalent + shared_preload_libraries, or allow-listing on Azure) - skipping; not required by the app.';
  END;
END $$;
-- pg_cron must be created in the DB named by cron.database_name. Uncomment if used:
-- CREATE EXTENSION IF NOT EXISTS pg_cron;

-- ---------------------------------------------------------------------------
-- Realtime publication  (your app migration ADDs tables to it later)
-- ---------------------------------------------------------------------------
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    CREATE PUBLICATION supabase_realtime;  -- empty publication
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Privilege bridge: let the app-migration role create triggers on auth.users
-- (auth.users is owned by supabase_auth_admin once GoTrue migrates).
-- ---------------------------------------------------------------------------
SELECT set_config('bootstrap.app_role', :'app_role', false);
DO $$
DECLARE r text := nullif(current_setting('bootstrap.app_role', true), '');
BEGIN
  IF r IS NOT NULL AND EXISTS (SELECT FROM pg_roles WHERE rolname = r) THEN
    EXECUTE format('GRANT supabase_auth_admin TO %I', r);
    EXECUTE format('ALTER PUBLICATION supabase_realtime OWNER TO %I', r);
    -- Since PG15, only the owner of "public" can create objects in it. Your app
    -- migrations need CREATE here. On RDS the master user owns public and can grant
    -- this; if bootstrap runs as a role that can't, grant it manually as the owner.
    BEGIN
      EXECUTE format('GRANT CREATE, USAGE ON SCHEMA public TO %I', r);
    EXCEPTION WHEN insufficient_privilege THEN
      RAISE WARNING 'Could not GRANT CREATE ON SCHEMA public TO % - run this as the database owner/master.', r;
    END;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Public schema usage for exposed roles (your app migration handles the rest:
-- table grants, default privileges, RLS, policies).
-- ---------------------------------------------------------------------------
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

\echo 'bootstrap.sql complete'
