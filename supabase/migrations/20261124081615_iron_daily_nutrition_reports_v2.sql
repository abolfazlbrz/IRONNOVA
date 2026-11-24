-- Generate nutrition reports daily even when a student does not open the app.
create extension if not exists pg_cron with schema pg_catalog;

create or replace function public.iron_generate_daily_nutrition_reports_v2()
returns integer language plpgsql security definer set search_path=''
as $function$
declare
 v_student record;
 v_day text := to_char((now() at time zone 'Asia/Tehran')::date,'YYYY-MM-DD');
 v_entries jsonb;
 v_totals jsonb;
 v_payload jsonb;
 v_text text;
 v_calories numeric;
 v_protein numeric;
 v_carbs numeric;
 v_fat numeric;
 v_fiber numeric;
 v_existing uuid;
 v_count integer:=0;
begin
 for v_student in
  select c.user_id,c.app_data
  from public.iron_track_cloud c
  join public.iron_account_roles_v2 r on r.user_id=c.user_id
  where r.role='student' and r.status='approved'
    and exists(select 1 from public.iron_coach_students_v2 cs
      where cs.student_id=c.user_id and cs.status='approved')
 loop
  select jsonb_agg(e.value order by e.value->>'created_at')
    into v_entries
  from jsonb_array_elements(
    case when jsonb_typeof(v_student.app_data->'foodLogs')='array'
      then v_student.app_data->'foodLogs' else '[]'::jsonb end
  ) as e(value)
  where e.value->>'date'=v_day;
  if v_entries is null or jsonb_array_length(v_entries)=0 then continue; end if;

  select
   coalesce(sum(case when coalesce(e.value->>'calories','') ~ '^[0-9]+(\.[0-9]+)?$' then (e.value->>'calories')::numeric else 0 end),0),
   coalesce(sum(case when coalesce(e.value->>'protein','') ~ '^[0-9]+(\.[0-9]+)?$' then (e.value->>'protein')::numeric else 0 end),0),
   coalesce(sum(case when coalesce(e.value->>'carbs','') ~ '^[0-9]+(\.[0-9]+)?$' then (e.value->>'carbs')::numeric else 0 end),0),
   coalesce(sum(case when coalesce(e.value->>'fat','') ~ '^[0-9]+(\.[0-9]+)?$' then (e.value->>'fat')::numeric else 0 end),0),
   coalesce(sum(case when coalesce(e.value->>'fiber','') ~ '^[0-9]+(\.[0-9]+)?$' then (e.value->>'fiber')::numeric else 0 end),0)
  into v_calories,v_protein,v_carbs,v_fat,v_fiber
  from jsonb_array_elements(v_entries) as e(value);

  v_totals:=jsonb_build_object(
   'calories',round(v_calories),
   'protein',round(v_protein,1),
   'carbs',round(v_carbs,1),
   'fat',round(v_fat,1),
   'fiber',round(v_fiber,1)
  );
  v_text:='گزارش روزانه تغذیه: '||jsonb_array_length(v_entries)||' مورد ثبت‌شده · '
    ||round(v_calories)::text||' کیلوکالری · پروتئین '||round(v_protein,1)::text
    ||' گرم · کربوهیدرات '||round(v_carbs,1)::text||' گرم · چربی '||round(v_fat,1)::text||' گرم';
  v_payload:=jsonb_build_object(
   'report_date',v_day,'text',v_text,'totals',v_totals,'entries',v_entries,
   'generated_by','scheduled_daily_digest'
  );

  select id into v_existing from public.iron_student_logs
  where student_id=v_student.user_id and log_type='nutrition'
    and payload->>'report_date'=v_day
  order by logged_at desc limit 1;
  if v_existing is null then
   insert into public.iron_student_logs(student_id,log_type,payload,logged_at)
   values(v_student.user_id,'nutrition',v_payload,now());
  else
   update public.iron_student_logs set payload=v_payload,logged_at=now()
   where id=v_existing;
  end if;
  v_count:=v_count+1;
 end loop;
 return v_count;
end;
$function$;
revoke all on function public.iron_generate_daily_nutrition_reports_v2() from public,anon,authenticated;

do $$
declare v_job bigint;
begin
 select jobid into v_job from cron.job where jobname='iron-daily-nutrition-digest' limit 1;
 if v_job is not null then perform cron.unschedule(v_job); end if;
end $$;
select cron.schedule(
 'iron-daily-nutrition-digest',
 '30 20 * * *',
 'select public.iron_generate_daily_nutrition_reports_v2();'
);
