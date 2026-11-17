import Testing
@testable import UnigridsCore

@Suite("Japanese script")
struct JapaneseScriptTests {
    @Test("kanji, kana and the repeat mark are Japanese script; Latin and Norwegian are not")
    func detects() {
        #expect(JapaneseScript.contains("表銀座"))
        #expect(JapaneseScript.contains("Kamikochi かみこうち"))
        #expect(JapaneseScript.contains("ヒュッテ"))
        #expect(JapaneseScript.contains("佐々木"))
        #expect(!JapaneseScript.contains("Besseggen"))
        #expect(!JapaneseScript.contains("Øvre Dividal"))
        #expect(!JapaneseScript.contains("Kujū"))
    }
}
