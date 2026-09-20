///|
priv enum DynamicMessage {
  DOpenMatch(String, String)
  DMoreResults(String)
}

///|
fn dynamic_text(locale : @i18n.Locale, message : DynamicMessage) -> String {
  match (locale, message) {
    (English, DOpenMatch(p0, p1)) => "Open \{p0}:\{p1}"
    (Spanish, DOpenMatch(p0, p1)) => "Abrir \{p0}:\{p1}"
    (SimplifiedChinese, DOpenMatch(p0, p1)) => "打开 \{p0}:\{p1}"
    (TraditionalChinese, DOpenMatch(p0, p1)) => "開啟 \{p0}:\{p1}"
    (Japanese, DOpenMatch(p0, p1)) => "\{p0}:\{p1} を開く"
    (English, DMoreResults(p0)) => "Show \{p0} more results"
    (Spanish, DMoreResults(p0)) => "Mostrar \{p0} resultados más"
    (SimplifiedChinese, DMoreResults(p0)) => "再显示 \{p0} 个结果"
    (TraditionalChinese, DMoreResults(p0)) => "再顯示 \{p0} 個結果"
    (Japanese, DMoreResults(p0)) => "さらに \{p0} 件を表示"
  }
}
