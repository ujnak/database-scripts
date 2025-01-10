create or replace type array_jobs is varray(150) of varchar2(100);
/

create or replace procedure debugging_step_into (how_many in integer) IS
 cursor demo_debug is select * from oehr_employees fetch first how_many rows only;
 fullname varchar2(100);
BEGIN
    for counter in demo_debug LOOP
     fullname := counter.first_name || ' ' || counter.last_name;
     dbms_output.put_line(counter.employee_id || ' name is ' || fullname);
     fullname := '';
    end loop;
END debugging_step_into;
/

create or replace procedure debugging_debugger (x in integer) is
 y boolean := true;
 z date := sysdate;
 jobs_a array_jobs;
begin

  select distinct job_title 
  bulk collect into jobs_a
  from oehr_jobs
  order by 1; 

 for i in 1..x LOOP
   DBMS_OUTPUT.PUT_LINE('Job #' || i || ' is ' || jobs_a(i));
 END LOOP;

 DEBUGGING_STEP_INTO(x);
 null; -- placeholder 
end;
/