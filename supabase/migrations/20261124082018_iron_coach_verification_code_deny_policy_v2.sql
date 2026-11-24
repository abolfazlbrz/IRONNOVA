-- Explicit deny policy documents that verification-code hashes are never client-readable.
drop policy if exists iron_coach_verification_codes_deny_clients_v2 on public.iron_coach_verification_codes_v2;
create policy iron_coach_verification_codes_deny_clients_v2
on public.iron_coach_verification_codes_v2
for all to authenticated
using (false)
with check (false);
