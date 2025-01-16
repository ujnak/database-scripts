create or replace package body ebaj_asp_theatrejs_pkg as
/**
* パッケージ本体
*/
/**
* projectIdを指定してprojectStateを取り出す。
*/
procedure ajax_restore_project_state(
    p_project_id in varchar2
)
as
    l_project_state ebaj_theatrejs_projects.project_state%type;
    l_response      clob;
    l_response_json json_object_t;
    l_export apex_data_export.t_export;
begin
    select project_state into l_project_state from ebaj_theatrejs_projects
    where project_id = p_project_id;
    /* レスポンスの作成 */
    l_response_json := json_object_t();
    l_response_json.put('status', true);
    l_response_json.put('id', p_project_id);
    l_response_json.put('state', l_project_state);
    l_response := l_response_json.to_clob();
    /* レスポンスの出力 */
    l_export.mime_type := 'application/json';
    l_export.as_clob   := true;
    l_export.content_clob := l_response;
    apex_data_export.download( p_export => l_export );
exception
    when no_data_found then
        l_response := json_object(
            'status' value false
            ,'reason' value SQLERRM
        );
        htp.p(l_response);
end ajax_restore_project_state;

/**
 *
 */
procedure ajax_save_project_state(
    p_project_id     in varchar2
    ,p_project_state in clob
)
as
    l_exist number;
    l_response clob;
begin
    begin
        select 1 into l_exist from ebaj_theatrejs_projects
        where project_id = p_project_id;
        /* 保存されているProject IDが無ければ例外ハンドラでINSERTする。 */
        update ebaj_theatrejs_projects set project_state = p_project_state
        where project_id = p_project_id;
    exception
        when no_data_found then
            insert into ebaj_theatrejs_projects(project_id, project_state)
            values(p_project_id, p_project_state);
    end;
    l_response := json_object(
        'status' value true
        ,'message' value 'projectState is saved.'
    );
    htp.p(l_response);
exception
    when others then
        l_response := json_object(
            'status' value false
            ,'reason' value SQLERRM
        );
        htp.p(l_response);
end ajax_save_project_state;

end ebaj_asp_theatrejs_pkg;
/