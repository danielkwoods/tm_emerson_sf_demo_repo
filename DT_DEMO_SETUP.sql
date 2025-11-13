create or replace table test_landing_zone (
COLA int,
COLB varchar,
COLc Date,
file_name varchar,
last_updated_timestamp timestamp_ntz(9)
);
create or replace dynamic table test_dt_2
warehouse=compute_wh
target_lag=DOWNSTREAM

as;

select convert_timezone('America/Chicago','UTC','2025-11-02 01:00:00');

with base as (

select *,regexp_substr(file_name,'\\d{8}-\\d{6}') file_substr,to_timestamp(file_substr,'YYYYMMDD-HHMISS') as ts
,convert_timezone('America/Chicago','UTC',to_timestamp(file_substr,'YYYYMMDD-HHMISS')) as file_ts, 
abs(timediff(hour,file_ts,lag(file_ts) over (order by file_ts))) as hour_diff from test_landing_zone


)
select 
conditional_change_event(hour_diff) over (order by file_ts) as change_event,* from base
qualify change_event=0;


  select * from test_dt_2;

select * from test_landing_zone;
  
alter dynamic table test_dt_2 refresh;


copy into test_landing_zone
from @test_stage_2

FILE_FORMAT = ( TYPE = CSV PARSE_HEADER = TRUE error_on_column_count_mismatch=false)

MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
 ON_ERROR='SKIP_FILE'
INCLUDE_METADATA = (
file_name=METADATA$FILENAME, last_updated_timestamp = METADATA$FILE_LAST_MODIFIED
);
select * from test_dt;

create or replace dynamic table test_dt 
warehouse=compute_wh
target_lag=DOWNSTREAM
as
select *
from test_landing_zone
qualify rank() over (partition by file_name order by last_updated_timestamp desc)=1;

 create or replace view test_stage_delete as 
 
SELECT  split_part(file_name,'/',-1) as file_name_to_delete
  FROM TABLE(information_schema.stage_directory_file_registration_history(
  STAGE_NAME=>'TEST_STAGE_2'))
  where operation_status in ('UNREGISTERED','REGISTERED_NEW') and file_name like '%.csv'

    group by file_name having count(1)>1 and datediff(day,max(job_created_time),min(job_created_time))<60
  ;
  create task purge_test_landing_zone
  schedule = '1 hour'
  warehouse= compute_wh
  as 
    delete from test_landing_zone where file_name in (
    select file_name_to_delete from test_stage_delete)
;
  create task load_test_landing_zone
  after= purge_test_landing_zone
  warehouse = compute_wh
  as
  copy into test_landing_zone
from @test_stage_2

FILE_FORMAT = ( TYPE = CSV PARSE_HEADER = TRUE error_on_column_count_mismatch=false)

MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
INCLUDE_METADATA = (
file_name=METADATA$FILENAME, last_updated_timestamp = METADATA$FILE_LAST_MODIFIED
)
;

select * from snowflake.account_usage.copy_history;

select *
from table(information_schema.copy_history(TABLE_NAME=>'TEST_LANDING_ZONE', START_TIME=> DATEADD(hours, -1, CURRENT_TIMESTAMP())))
WHERE STATUS='Load failed';

select * from snowflake.account_usage.table_dml_history;

/*
run DML statement against table -> Log query_id and other metrics
IF DML statement should be reverted then time travel using query id to go back to previous state
Can utilize two different approaches
1 - Insert overwrite table select * from table before(statement=>query_id)
2 - Clone table_recovery from table before(statement=>query_id) -> alter table swap table_recovery -> drop table_recovery
*/

select * from test_landing_zone before(statement=>'01c00f95-0002-42a2-0001-90c20128b2d6');

insert into test_landing_zone
select * exclude(last_updated_timestamp),current_timestamp() from test_landing_zone where $1=5
;
select * from test_landing_zone;

insert overwrite into test_landing_zone
select * from test_landing_zone before(statement=>'01c00f95-0002-42a2-0001-90c20128b2d6');


create table test_recovery clone test_landing_zone before(statement=>'01c00f97-0002-4266-0001-90c20128a29e')
;

select * from test_recovery;

select * from test_landing_zone;

alter table test_landing_zone swap with test_recovery;

show network rules in snowflake.network_security;

desc network rule snowflake.network_security.powerbi_eastus2_azure;

desc schema snowflake.network_security;


select * from snowflake.account_usage.network_rules where name='POWERBI_EASTUS2_AZURE';


select * from information_schema.columns where table_name='TEST_DT_2'