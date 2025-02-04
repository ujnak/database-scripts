create or replace package ebaj_voicevox_proxy
as

/**
* 2つのWAVファイルをマージするプロシージャ。
* OpenAI o3-mini-highに書いてもらった。
*/
PROCEDURE merge_wav_files (
   p_file1  IN  BLOB,  -- First WAV file (with standard 44-byte header)
   p_file2  IN  BLOB,  -- Second WAV file (with standard 44-byte header)
   p_merged OUT BLOB   -- Output: merged WAV file as a BLOB
);

/**
* VOICEVOXの/audio_queryを呼び出す。
*/
function audio_query(
    p_text      in clob
    ,p_base_url in varchar2
    ,p_speaker  in number
)
return clob;

/**
* VOICEVOXのsynthesisを呼び出す。
*/
function synthesis(
    p_query     in clob
    ,p_base_url in varchar2
    ,p_speaker  in number
)
return blob;

/**
* VOICEVOXのaudio_queryとsynthesisを呼び出す。
*/
function audio_query_and_synthesis(
    p_text      in clob
    ,p_base_url in varchar2
    ,p_speaker  in number
)
return blob;

end ebaj_voicevox_proxy;
/