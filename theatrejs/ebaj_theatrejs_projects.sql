create table ebaj_theatrejs_projects (
    project_id       varchar2(200 char) not null
                     constraint ebaj_theatrejs_projects_project_id_pk primary key,
    project_state    clob check (project_state is json)
);