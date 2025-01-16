create or replace package ebaj_asp_theatrejs_pkg as
/**
* アプリケーションSample Theatre.jsに組み込むスクリプト。
* 
* 以下のDDLで作成される表EBAJ_THEATREJS_PROJECTSが操作の対象。
---
create table ebaj_theatrejs_projects (
    project_id       varchar2(200 char) not null
                     constraint ebaj_theatrejs_projects_project_id_pk primary key,
    project_state    clob check (project_state is json)
);
---
*/

/**
* 指定したProject IDのアニメーションをJSONドキュメントとして
* HTTPバッファに出力する。
*/
procedure ajax_restore_project_state(
    p_project_id in varchar2
);

/**
* Theatre.jsのアニメーションをJSONドキュメントとして保存する。
*/
procedure ajax_save_project_state(
    p_project_id     in varchar2
    ,p_project_state in clob
);

end ebaj_asp_theatrejs_pkg;
/