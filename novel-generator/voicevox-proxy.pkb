create or replace package body ebaj_voicevox_proxy
as

/**
* 2つのWAVファイルをマージするプロシージャ。
*
* OpenAI o3-mini-highに書いてもらった。
*
* function int_to_le_rawのコメントが日本語なのは、WAVをマージするプロシージャを
* 書いてもらったときのプロンプトは英語で、CHR型の代わりにRAWを使ってと修正を依頼した
* ときのプロンプトが日本語だったから。
*/
PROCEDURE merge_wav_files (
   p_file1  IN  BLOB,  -- First WAV file (with standard 44-byte header)
   p_file2  IN  BLOB,  -- Second WAV file (with standard 44-byte header)
   p_merged OUT BLOB   -- Output: merged WAV file as a BLOB
)
IS
   -------------------------------------------------------------------------
   -- Local variables.
   -------------------------------------------------------------------------
   v_header         RAW(44);   -- Original header from the first file.
   v_new_header     RAW(44);   -- Modified header for the merged file.
   v_data_len1      INTEGER;   -- Audio data length in file1 (in bytes).
   v_data_len2      INTEGER;   -- Audio data length in file2 (in bytes).
   v_new_data_len   INTEGER;   -- Combined data length.
   v_total_file_sz  INTEGER;   -- New overall file size field value.

   -------------------------------------------------------------------------
   -- Helper function: Convert an integer into a 4-byte little-endian RAW.
   --
   -- WAV file header fields (e.g. overall file size and data length)
   -- are stored as 4-byte little-endian integers.
   -------------------------------------------------------------------------
   FUNCTION int_to_le_raw(p_int IN INTEGER) RETURN RAW IS
      l_byte1 RAW(1);
      l_byte2 RAW(1);
      l_byte3 RAW(1);
      l_byte4 RAW(1);
      l_result RAW(4);
   BEGIN
      -- 下位バイトから順に、16進数2桁の文字列に変換してからRAWに変換
      l_byte1 := hextoraw(LPAD(TO_CHAR(MOD(p_int, 256), 'FMXX'), 2, '0'));
      l_byte2 := hextoraw(LPAD(TO_CHAR(MOD(TRUNC(p_int/256), 256), 'FMXX'), 2, '0'));
      l_byte3 := hextoraw(LPAD(TO_CHAR(MOD(TRUNC(p_int/256/256), 256), 'FMXX'), 2, '0'));
      l_byte4 := hextoraw(LPAD(TO_CHAR(MOD(TRUNC(p_int/256/256/256), 256), 'FMXX'), 2, '0'));

      -- 4つのRAWを連結（リトルエンディアン：最下位バイトが先頭）
      l_result := utl_raw.concat(utl_raw.concat(l_byte1, l_byte2),
                                 utl_raw.concat(l_byte3, l_byte4));
      RETURN l_result;
END;
BEGIN
   -- Check that each WAV file is at least 44 bytes long.
   IF DBMS_LOB.getlength(p_file1) < 44 OR DBMS_LOB.getlength(p_file2) < 44 THEN
      raise_application_error(-20001, 'One of the WAV files is too short to be valid.');
   END IF;

   -------------------------------------------------------------------------
   -- Extract the header from the first WAV file.
   -- In a standard PCM WAV file the header is 44 bytes:
   --
   --   Bytes  1-4: "RIFF"
   --   Bytes  5-8: Overall file size (file size - 8) [little-endian]
   --   Bytes  9-12: "WAVE"
   --   Bytes 13-16: "fmt "
   --   Bytes 17-40: Format information (subchunk size, audio format,
   --                number of channels, sample rate, byte rate, etc.)
   --   Bytes 37-40: "data" (the literal string)
   --   Bytes 41-44: Data chunk size [little-endian]
   -------------------------------------------------------------------------
   v_header := DBMS_LOB.SUBSTR(p_file1, 44, 1);

   -- Compute the length of the audio (data) portion in each file.
   v_data_len1 := DBMS_LOB.getlength(p_file1) - 44;
   v_data_len2 := DBMS_LOB.getlength(p_file2) - 44;
   v_new_data_len := v_data_len1 + v_data_len2;

   -- The WAV header “overall file size” (bytes 5-8) equals the final file size minus 8.
   -- For a standard 44-byte header, this value becomes 36 + (data size).
   v_total_file_sz := 36 + v_new_data_len;

   -------------------------------------------------------------------------
   -- Build the new header:
   --
   --   • Keep the first 4 bytes (i.e. "RIFF") unchanged.
   --   • Replace bytes 5-8 with the new overall file size (as a little-endian RAW).
   --   • Keep bytes 9-40 unchanged.
   --   • Replace bytes 41-44 with the new data length (as a little-endian RAW).
   -------------------------------------------------------------------------
   v_new_header :=
      UTL_RAW.SUBSTR(v_header, 1, 4) ||              -- "RIFF"
      int_to_le_raw(v_total_file_sz) ||              -- new overall file size (bytes 5-8)
      UTL_RAW.SUBSTR(v_header, 9, 32) ||             -- bytes 9-40 (unchanged header parts)
      int_to_le_raw(v_new_data_len);                 -- new data chunk size (bytes 41-44)

   -------------------------------------------------------------------------
   -- Create a temporary LOB to hold the merged file.
   -------------------------------------------------------------------------
   DBMS_LOB.CREATETEMPORARY(p_merged, TRUE, DBMS_LOB.CALL);

   -------------------------------------------------------------------------
   -- Write the new header to the merged file.
   -------------------------------------------------------------------------
   DBMS_LOB.WRITEAPPEND(p_merged, UTL_RAW.LENGTH(v_new_header), v_new_header);

   -------------------------------------------------------------------------
   -- Append the audio data from the first file.
   -- We copy from position 45 (i.e. skipping the 44-byte header) for v_data_len1 bytes.
   -------------------------------------------------------------------------
   DBMS_LOB.COPY(
      dest_lob    => p_merged,
      src_lob     => p_file1,
      amount      => v_data_len1,
      dest_offset => DBMS_LOB.getlength(p_merged) + 1,  -- should be 45 after header write
      src_offset  => 45
   );

   -------------------------------------------------------------------------
   -- Append the audio data from the second file (again, skipping its header).
   -------------------------------------------------------------------------
   DBMS_LOB.COPY(
      dest_lob    => p_merged,
      src_lob     => p_file2,
      amount      => v_data_len2,
      dest_offset => DBMS_LOB.getlength(p_merged) + 1,
      src_offset  => 45
   );

EXCEPTION
   WHEN OTHERS THEN
      -- In case of error, free the temporary LOB if needed.
      IF DBMS_LOB.ISTEMPORARY(p_merged) = 1 THEN
         DBMS_LOB.FREETEMPORARY(p_merged);
      END IF;
      RAISE;
END merge_wav_files;

/**
* VOICEVOXの/audio_queryを呼び出す。
*/
function audio_query(
    p_text      in clob
    ,p_base_url in varchar2
    ,p_speaker  in number
)
return clob
as
    l_response clob;
    l_url      clob;
    e_api_call_failed exception;
begin
    l_url := p_base_url || '/audio_query?text=' || utl_url.escape(p_text, false, 'AL32UTF8') || '&speaker=' || p_speaker;
    apex_web_service.clear_request_headers();
    apex_web_service.set_request_headers('accept', 'application/json', p_reset => false);
    l_response := apex_web_service.make_rest_request(
        p_url => l_url
        ,p_http_method => 'POST'
        ,p_body => ''
    );
    if apex_web_service.g_status_code <> 200 then
        raise e_api_call_failed;
    end if;
    return l_response;
end audio_query;

/**
* VOICEVOXのsynthesisを呼び出す。
*/
function synthesis(
    p_query     in clob
    ,p_base_url in varchar2
    ,p_speaker  in number
)
return blob
as
    l_query clob;
    l_blob blob;
    l_url varchar2(400);
    e_api_call_failed exception;
begin
    l_url := p_base_url || '/synthesis?speaker=' || p_speaker;
    apex_web_service.clear_request_headers();
    apex_web_service.set_request_headers('Content-Type', 'application/json', p_reset => false);
    apex_web_service.set_request_headers('accept', 'audio/wav', p_reset => false);
    l_blob := apex_web_service.make_rest_request_b(
        p_url => l_url
        ,p_http_method => 'POST'
        ,p_body => p_query
    );
    if apex_web_service.g_status_code <> 200 then
        raise e_api_call_failed;
    end if;
    return l_blob;
end synthesis;

/**
* 生成されたWAVを確認するためのファンクション。呼び出さない。
*
    動作確認用の表
    -----
    create table checkwav (
        id       number generated by default on null as identity
                constraint checkwav_id_pk primary key,
        idx      number,
        text     clob,
        query    clob,
        wav      blob
    );
*/
procedure log_wav(
    p_idx in number
    ,p_text in clob
    ,p_query in clob
    ,p_wav   in blob
)
as
    pragma autonomous_transaction;
begin
    -- insert into checkwav(idx, text, query, wav) values(p_idx, p_text, p_query, p_wav);
    commit;
end log_wav;

/**
* VOICEVOXのaudio_queryとsynthesisを呼び出す。
*
* 長文をVOICEVOXに送ると、synthesisででエラーが発生する。
* なので、改行ごとにテキストを送信し、WAVファイルに変換している。
* もし、改行で区切られていず、長い文字列が渡されるとやはりエラーとなるが、
* これといった対応はしていない。
*
* 句読点で区切っても良いが、元々の文章に改行を入れた方が良いと思う。
*
* WAVファイルに変換した後、今度はそれをマージして、ひとつのWAVファイルにしている。
* それを呼び出し元に戻している。
*/
function audio_query_and_synthesis(
    p_text      in clob
    ,p_base_url in varchar2
    ,p_speaker  in number
)
return blob
as
    l_query clob;           -- チャンクごとのaudio_queryの結果
    l_wav0  blob;           -- すべてのWAV
    l_wav   blob;           -- チャンクごとのWAV
    l_text  clob;           -- 音声にするテキスト - すべて
    l_text0 varchar2(4000); -- 音声にするテキスト、改行で分割
    l_text_array apex_t_varchar2;
begin
    /* 改行で分割 */
    l_text_array := apex_string.split(p_text);
    l_wav0 := null;
    for i in 1..l_text_array.count
    loop
        l_text0 := l_text_array(i);
        if length(l_text0) > 0 then
            l_query := audio_query(l_text0, p_base_url, p_speaker);
            l_wav   := synthesis(l_query, p_base_url, p_speaker);
            log_wav(i, l_text0, l_query, l_wav);
            if l_wav0 is null then
                l_wav0 := l_wav;
            else
                merge_wav_files(l_wav0, l_wav, l_wav0);
                -- l_wav0 := l_wav;
            end if;
        end if;
    end loop;
    return l_wav0;
end audio_query_and_synthesis;

end ebaj_voicevox_proxy;
/