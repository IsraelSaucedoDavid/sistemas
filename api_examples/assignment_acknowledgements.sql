-- ============================================================
-- ACTA Y FIRMA DE ENTREGA POR ASIGNACION
-- ============================================================

create table if not exists sistema.assignment_acknowledgements (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null unique
    references sistema.assignments(id) on delete cascade,
  signer_name text not null,
  signer_email text null,
  accepted_terms boolean not null default false,
  signature_path text not null,
  pdf_path text null,
  email_status text null,
  email_error text null,
  email_sent_at timestamptz null,
  signed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid null default auth.uid()
);

alter table sistema.assignment_acknowledgements
  add column if not exists pdf_path text null,
  add column if not exists email_status text null,
  add column if not exists email_error text null,
  add column if not exists email_sent_at timestamptz null;

create index if not exists idx_assignment_ack_assignment_id
  on sistema.assignment_acknowledgements (assignment_id);

create index if not exists idx_assignment_ack_signed_at
  on sistema.assignment_acknowledgements (signed_at desc);

grant usage on schema sistema to authenticated, anon;
grant select, insert, update, delete on sistema.assignment_acknowledgements to authenticated;
grant select on sistema.assignment_acknowledgements to anon;

alter table sistema.assignment_acknowledgements enable row level security;

drop policy if exists "assignment_ack_select_auth" on sistema.assignment_acknowledgements;
drop policy if exists "assignment_ack_insert_auth" on sistema.assignment_acknowledgements;
drop policy if exists "assignment_ack_update_auth" on sistema.assignment_acknowledgements;
drop policy if exists "assignment_ack_delete_auth" on sistema.assignment_acknowledgements;

create policy "assignment_ack_select_auth"
  on sistema.assignment_acknowledgements
  for select to authenticated
  using (true);

create policy "assignment_ack_insert_auth"
  on sistema.assignment_acknowledgements
  for insert to authenticated
  with check (true);

create policy "assignment_ack_update_auth"
  on sistema.assignment_acknowledgements
  for update to authenticated
  using (true)
  with check (true);

create policy "assignment_ack_delete_auth"
  on sistema.assignment_acknowledgements
  for delete to authenticated
  using (true);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'assignment-signatures',
  'assignment-signatures',
  false,
  5242880,
  array['image/png']
)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'assignment-documents',
  'assignment-documents',
  false,
  10485760,
  array['application/pdf']
)
on conflict (id) do nothing;

drop policy if exists "assignment_signatures_read_auth" on storage.objects;
drop policy if exists "assignment_signatures_insert_auth" on storage.objects;
drop policy if exists "assignment_signatures_update_auth" on storage.objects;
drop policy if exists "assignment_signatures_delete_auth" on storage.objects;

create policy "assignment_signatures_read_auth"
on storage.objects
for select to authenticated
using (bucket_id = 'assignment-signatures');

create policy "assignment_signatures_insert_auth"
on storage.objects
for insert to authenticated
with check (bucket_id = 'assignment-signatures');

create policy "assignment_signatures_update_auth"
on storage.objects
for update to authenticated
using (bucket_id = 'assignment-signatures')
with check (bucket_id = 'assignment-signatures');

create policy "assignment_signatures_delete_auth"
on storage.objects
for delete to authenticated
using (bucket_id = 'assignment-signatures');

drop policy if exists "assignment_documents_read_auth" on storage.objects;
drop policy if exists "assignment_documents_insert_auth" on storage.objects;
drop policy if exists "assignment_documents_update_auth" on storage.objects;
drop policy if exists "assignment_documents_delete_auth" on storage.objects;

create policy "assignment_documents_read_auth"
on storage.objects
for select to authenticated
using (bucket_id = 'assignment-documents');

create policy "assignment_documents_insert_auth"
on storage.objects
for insert to authenticated
with check (bucket_id = 'assignment-documents');

create policy "assignment_documents_update_auth"
on storage.objects
for update to authenticated
using (bucket_id = 'assignment-documents')
with check (bucket_id = 'assignment-documents');

create policy "assignment_documents_delete_auth"
on storage.objects
for delete to authenticated
using (bucket_id = 'assignment-documents');

create or replace function sistema.set_assignment_ack_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_assignment_ack_updated_at on sistema.assignment_acknowledgements;
create trigger trg_assignment_ack_updated_at
before update on sistema.assignment_acknowledgements
for each row execute function sistema.set_assignment_ack_updated_at();

