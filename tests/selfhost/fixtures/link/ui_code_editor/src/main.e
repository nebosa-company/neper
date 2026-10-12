// `e.ui.code_editor` engine: hand-written scenarios (typing and undo, grapheme deletion, atomic refusals, dirty
// tracking, history eviction, search, languages and tokens, sticky columns, multi-caret typing) and then a 520-step
// generated script (scripts/gen_ui_code_editor_test.py, an independent flat-text model) replayed through the
// engine with a digest compared after EVERY step: document bytes, selections, dirty/undo/redo state and the whole
// token stream. A hand-written check exits with 201 + its number; a script step exits with 1 + (step % 200).

use e.mem
use e.os
use e.ui.code_editor as ce

// BEGIN GENERATED (scripts/gen_ui_code_editor_test.py)
fn script() -> str { ret "M\x1F0\x1EC\x1ED\x1ET\x1F\xC3\xA9t\xC3\xA9\x1ET\x1F  )x\x1ES\x1F7\x1F9\x1EG\x1ET\x1Flete\xCC\x81foo\x0A\x1ET\x1F(\x0A\x1EM\x1F6\x1F14\x1F18\x1EN\x1EB\x1EC\x1EU\x1EX\x1F2\x1F3\x1F\x0A\x1ES\x1F17\x1F2\x1EK\x1F5\x1F1\x1EZ\x1EB\x1EX\x1F0\x1F0\x1F\xC3\xBC\x1F0\x1F3\x1F\x1EU\x1ER\x1ET\x1Fa_b\x0A\x1EB\x1ET\x1F*/  \x1ET\x1F)3.14a_b\x1ET\x1Ftpl`let\x1EZ\x1ET\x1F\"str\"\x1ET\x1F\xC3\xA9t\xC3\xA9\x1ET\x1F{3.14\xC3\xA9t\xC3\xA9\x1EK\x1F3\x1F1\x1EC\x1ER\x1ET\x1F// note3.14\x0A\x1EI\x1EU\x1ET\x1Fvalue\x1ED\x1EC\x1EI\x1ET\x1Freturn\x0A\x1EF\x1ET\x1Ftpl``tpl*/\x0A\x1ET\x1F}\x1ET\x1F/*/*(\x1EI\x1EX\x1F4\x1F6\x1F{\x0A\x1F15\x1F5\x1FXY\x1F29\x1F1\x1F\xC3\xBC\x1EB\x1EK\x1F4\x1F0\x1EK\x1F4\x1F1\x1EX\x1F2\x1F3\x1F\x1F8\x1F0\x1F\x1F24\x1F2\x1FXY\x1EK\x1F9\x1F1\x1ES\x1F38\x1F31\x1EU\x1EN\x1ET\x1Ffooreturn\"str\"\x1EG\x1ED\x1ED\x1ET\x1F3.143.14\x1ET\x1F// note\xC3\xA9t\xC3\xA9\x0A\x1ET\x1F`tpl\x1EI\x1ET\x1F/*\x0A\x1EM\x1F84\x1F88\x1F93\x1EN\x1EI\x1ET\x1Fxlet\xE4\xB8\x96\xE7\x95\x8C\x1EK\x1F5\x1F0\x1ET\x1F)foo\xE4\xB8\x96\xE7\x95\x8C\x0A\x1EU\x1EU\x1ET\x1Ffoo\x1ER\x1EK\x1F1\x1F0\x1EU\x1ER\x1ET\x1F\xE4\xB8\x96\xE7\x95\x8Cfoo// note\x1ET\x1F}let\x1ER\x1ER\x1EI\x1ET\x1Ffoofoofoo\x1EB\x1ES\x1F186\x1F84\x1ER\x1EK\x1F10\x1F1\x1EM\x1F132\x1EZ\x1EX\x1F9\x1F4\x1F\x1EX\x1F7\x1F5\x1F\x1EX\x1F15\x1F2\x1F\x1F28\x1F2\x1FXY\x1F49\x1F1\x1F\xC3\xBC\x1ET\x1Fa_b\xC3\xA9t\xC3\xA9\x1EB\x1EU\x1ES\x1F170\x1F64\x1ET\x1F// note3.143.14\x1EI\x1EU\x1EB\x1ET\x1F\xE4\xB8\x96\xE7\x95\x8C\x1ET\x1Ffoo'c'value\x0A\x1EX\x1F6\x1F6\x1F{\x0A\x1F24\x1F5\x1F\xC3\xBC\x1EX\x1F10\x1F5\x1F\xC3\xBC\x1F29\x1F2\x1F\x1F32\x1F2\x1F\xC3\xBC\x1ET\x1F  'c'}\x1EG\x1EI\x1ET\x1Freturn*/\xC3\xA9t\xC3\xA9\x0A\x1EO\x1F1\x1EB\x1EO\x1F0\x1ET\x1Fif\xC3\xA9t\xC3\xA9if\x1EG\x1EC\x1ER\x1ET\x1F3.143.14\xE4\xB8\x96\xE7\x95\x8C\x1EK\x1F1\x1F1\x1EN\x1EK\x1F1\x1F0\x1EB\x1EF\x1EO\x1F1\x1EN\x1EK\x1F3\x1F1\x1EK\x1F4\x1F0\x1ES\x1F184\x1F99\x1ET\x1F\xC3\xA9t\xC3\xA93.14\x1ET\x1F{}\x1EX\x1F14\x1F2\x1FXY\x1F19\x1F5\x1F\x1EB\x1EB\x1ER\x1ET\x1F{tpl`\x1EK\x1F1\x1F1\x1EX\x1F1\x1F3\x1F\x0A\x1EN\x1ES\x1F98\x1F35\x1EX\x1F6\x1F6\x1F\x1ES\x1F102\x1F4\x1ET\x1Ftpl`a_breturn\x1EN\x1EK\x1F10\x1F1\x1EI\x1EW\x1Fx\x1FZ\x1F1\x1F1\x1EK\x1F3\x1F1\x1EU\x1EW\x1Fe\x1FZ\x1F1\x1F0\x1EN\x1EN\x1EF\x1EI\x1EX\x1F13\x1F4\x1F\x1EX\x1F19\x1F1\x1F\x1EN\x1ET\x1F*/{}\x0A\x1ET\x1Fvaluefoo{\x1ES\x1F17\x1F15\x1EX\x1F4\x1F2\x1F{\x0A\x1F21\x1F4\x1F\x0A\x1ET\x1F// note\x1EF\x1ET\x1Fletx3.14\x0A\x1ET\x1F`tpltpl`\x09\x1EC\x1EX\x1F15\x1F5\x1F\xC3\xBC\x1ET\x1F('c'  \x0A\x1EN\x1ES\x1F2\x1F48\x1EC\x1ES\x1F67\x1F78\x1ET\x1F3.14){\x1EN\x1EB\x1EN\x1ED\x1EI\x1ET\x1F\x09\x1EU\x1ET\x1F(tpl`\x1ET\x1F3.14\x1ET\x1Freturn\x1EF\x1ER\x1ET\x1F// note{\x1ET\x1F*/\x1ET\x1F3.14\x1ER\x1ER\x1ET\x1Fe\xCC\x81)tpl`\x1EW\x1Fif\x1FZ\x1F0\x1F1\x1ET\x1Fx\x1ED\x1EX\x1F15\x1F1\x1FXY\x1F21\x1F0\x1FXY\x1F26\x1F6\x1FXY\x1EF\x1EW\x1Fx\x1F\x1F0\x1F1\x1ET\x1Ftpl`\x1ES\x1F65\x1F45\x1ES\x1F26\x1F76\x1ER\x1ET\x1F  x3.14\x0A\x1EM\x1F24\x1F47\x1F51\x1ED\x1ET\x1Fe\xCC\x81\x1EU\x1ET\x1F)*/}\x1EX\x1F10\x1F6\x1F\x0A\x1F24\x1F0\x1FXY\x1F36\x1F1\x1F\x0A\x1EN\x1EW\x1Flet\x1F\x0A\x1F0\x1F1\x1EB\x1EK\x1F3\x1F0\x1EU\x1EU\x1EX\x1F0\x1F2\x1F\xC3\xBC\x1ET\x1F'c'\x1EW\x1Flet\x1Fqq\x1F0\x1F1\x1EI\x1ET\x1Ffoo*/e\xCC\x81\x1EC\x1EB\x1EK\x1F2\x1F1\x1EI\x1ET\x1F(\x0A\x1EB\x1EB\x1EM\x1F6\x1F25\x1F64\x1F97\x1EC\x1ER\x1ET\x1F'c'\x1EU\x1EN\x1EN\x1EX\x1F16\x1F4\x1F\x1F40\x1F3\x1F\x1EN\x1ED\x1EW\x1Fif\x1F\x1F1\x1F0\x1ER\x1EX\x1F15\x1F4\x1F\xC3\xBC\x1ED\x1ET\x1F\xE4\xB8\x96\xE7\x95\x8C// note\x1ES\x1F153\x1F79\x1ER\x1EN\x1EF\x1EX\x1F8\x1F4\x1F\x0A\x1F21\x1F0\x1F\x1F28\x1F4\x1F\x1EC\x1ET\x1Fa_b*/\x0A\x1EU\x1EK\x1F9\x1F0\x1EI\x1EK\x1F6\x1F0\x1EB\x1ES\x1F92\x1F61\x1EB\x1EZ\x1EB\x1ET\x1Fif\x09\xC3\xA9t\xC3\xA9\x0A\x1EB\x1ED\x1EK\x1F2\x1F0\x1EC\x1ES\x1F58\x1F15\x1EB\x1ET\x1Fe\xCC\x81return\x0A\x1EM\x1F53\x1F58\x1ED\x1EF\x1EC\x1EI\x1EW\x1Fe\x1Fqq\x1F0\x1F1\x1EK\x1F3\x1F0\x1EX\x1F16\x1F2\x1F\xC3\xBC\x1EC\x1ER\x1EF\x1EF\x1ED\x1EW\x1FAB\x1FZ\x1F1\x1F0\x1ET\x1Fe\xCC\x81\x1ET\x1Fx)x\x0A\x1EF\x1ES\x1F3\x1F79\x1ET\x1F\"str\"\x1ET\x1Fa_b\x0A\x1EB\x1EC\x1ER\x1EX\x1F5\x1F1\x1F\x0A\x1F8\x1F1\x1FXY\x1ET\x1F\xC3\xA9t\xC3\xA9\x1EC\x1EO\x1F0\x1EM\x1F4\x1F8\x1F11\x1F12\x1ET\x1F(tpl``tpl\x1EK\x1F3\x1F1\x1EG\x1ER\x1EI\x1ET\x1Ftpl`foo\x1ES\x1F18\x1F18\x1EX\x1F14\x1F2\x1F\x1F16\x1F1\x1FXY\x1F17\x1F1\x1F{\x0A\x1EK\x1F6\x1F1\x1ET\x1F/*\x1EU\x1ER\x1ET\x1F  \xC3\xA9t\xC3\xA9\x1EW\x1Flet\x1F\x0A\x1F1\x1F1\x1EU\x1EB\x1ES\x1F16\x1F7\x1ET\x1F/*let\x1ES\x1F9\x1F6\x1ET\x1F}/**/\x1EI\x1EI\x1ET\x1Ffoo\x1EF\x1ET\x1Fe\xCC\x81\x0A\x1ET\x1F`tpllet)\x1ES\x1F4\x1F37\x1EN\x1EU\x1EN\x1ET\x1Ffoo'c'\x1EU\x1ET\x1F)\x1ET\x1F)// note\"str\"\x1EX\x1F10\x1F6\x1F{\x0A\x1F28\x1F2\x1F\x0A\x1F31\x1F0\x1F{\x0A\x1EX\x1F2\x1F5\x1F\xC3\xBC\x1F8\x1F3\x1F\x0A\x1F11\x1F6\x1F{\x0A\x1ET\x1F{)\x0A\x1ER\x1EK\x1F1\x1F0\x1ES\x1F13\x1F4\x1EB\x1EK\x1F3\x1F1\x1EW\x1Ffoo\x1Fqq\x1F0\x1F1\x1ES\x1F8\x1F4\x1EF\x1ET\x1F`tpl\x09\x0A\x1EC\x1ET\x1Fx\x1ET\x1F\xE4\xB8\x96\xE7\x95\x8Cxtpl`\x0A\x1ET\x1F3.14}\x0A\x1EK\x1F10\x1F0\x1EM\x1F17\x1F25\x1ET\x1F){\x1EN\x1EX\x1F15\x1F3\x1F\x0A\x1F35\x1F6\x1F\x1EX\x1F12\x1F0\x1FXY\x1ET\x1Fe\xCC\x81e\xCC\x81\x1ET\x1F\"str\"let\xE4\xB8\x96\xE7\x95\x8C\x1EM\x1F53\x1F91\x1ED\x1ET\x1Fvaluetpl`\x0A\x1EN\x1ET\x1F\x09('c'\x1ET\x1F}\x1ET\x1Freturn\x1ET\x1F'c'(\x1ET\x1F  \xC3\xA9t\xC3\xA9\x0A\x1EK\x1F5\x1F0\x1ET\x1F3.14a_b\x0A\x1EM\x1F9\x1F139\x1ES\x1F134\x1F126\x1ET\x1Ftpl``tpl\x1EN\x1EU\x1EM\x1F92\x1ET\x1Freturnifa_b\x1EM\x1F167\x1EM\x1F96\x1EK\x1F10\x1F0\x1EU\x1EI\x1ET\x1Flet\x09\x0A\x1ED\x1ET\x1F)*/\x1EK\x1F5\x1F1\x1EZ\x1ES\x1F142\x1F170\x1ET\x1F3.143.14\x1ET\x1F`tpl'c'\x1EK\x1F6\x1F1\x1ER\x1ET\x1Freturn\x1ET\x1F)  value\x0A\x1ES\x1F9\x1F118\x1EI\x1EK\x1F2\x1F0\x1EB\x1ET\x1Fif\x1EO\x1F0\x1EU\x1ES\x1F130\x1F35\x1EC\x1EB\x1EO\x1F0\x1EW\x1Fe\x1F\x0A\x1F1\x1F1\x1EC\x1ET\x1F*/(  \x1EB\x1EG\x1ED\x1EN\x1ET\x1Ftpl`3.14\x1EG\x1EM\x1F96\x1EB\x1EX\x1F9\x1F6\x1F\x1F34\x1F5\x1FXY\x1EB\x1EO\x1F1\x1EN\x1EB\x1ER\x1ED\x1EX\x1F4\x1F4\x1FXY\x1F24\x1F5\x1FXY\x1F47\x1F0\x1FXY\x1EO\x1F0\x1ET\x1F\xE4\xB8\x96\xE7\x95\x8C\x1EK\x1F6\x1F1\x1ET\x1F'c'\xC3\xA9t\xC3\xA9\x1EM\x1F30\x1F72\x1EN\x1EN\x1EN\x1ET\x1F'c'value\x09\x1EU\x1ED\x1ET\x1Flet\x1ER\x1EB\x1EZ\x1EI\x1ER\x1ET\x1F(\x1ET\x1Fx*/\x0A\x1EG\x1ET\x1Fa_b\x09\x1ED\x1EI\x1EC\x1EZ\x1ET\x1F3.14\x1ET\x1Fe\xCC\x81\x1EI\x1ES\x1F44\x1F86\x1EN\x1ET\x1F\"str\"}\x1ET\x1Fx\x09a_b\x1ES\x1F127\x1F153\x1ET\x1F/*// note\x1EW\x1Fa\x1F\x0A\x1F1\x1F1\x1EM\x1F29\x1F30\x1F111\x1F134\x1EU\x1EN\x1EN\x1ES\x1F107\x1F6\x1EU\x1ET\x1F\x09(\x1EK\x1F9\x1F1\x1EZ\x1EU\x1EI\x1ET\x1Fif\x1EB\x1EX\x1F1\x1F3\x1F\x1F20\x1F1\x1F\xC3\xBC\x1EU\x1EG\x1ES\x1F60\x1F17\x1EK\x1F6\x1F1\x1EI\x1ET\x1F)\x1EI\x1ET\x1Fif\x1ET\x1F{\x1EM\x1F75\x1EB\x1EK\x1F5\x1F0\x1EU\x1ET\x1F\xC3\xA9t\xC3\xA9\x1EN\x1ES\x1F36\x1F91\x1EW\x1Fa\x1FZ\x1F0\x1F1\x1ET\x1Ftpl``tpl\x1ET\x1F3.143.14\x1EW\x1Fx\x1FZ\x1F1\x1F1\x1EX\x1F5\x1F5\x1F\xC3\xBC\x1ET\x1F)\"str\"3.14\x1ET\x1Fif`tpl\x09\x1EF\x1ES\x1F182\x1F34\x1EU\x1EK\x1F10\x1F1\x1ET\x1F\"str\"\x1ET\x1F  3.14'c'\x0A\x1EB\x1EX\x1F9\x1F6\x1F\x0A\x1F26\x1F6\x1F\xC3\xBC\x1F35\x1F4\x1F\xC3\xBC\x1EB\x1EU\x1ET\x1F\"str\"'c'return\x1ET\x1Ffoo\xC3\xA9t\xC3\xA9\x1ET\x1Fxlet(\x1EN\x1EB\x1ES\x1F205\x1F145\x1ET\x1F`tpl\x1ET\x1Fvalue\x1EN\x1ET\x1Freturn\x1ET\x1F\xC3\xA9t\xC3\xA9}*/\x0A\x1EX\x1F5\x1F0\x1F\xC3\xBC\x1EO\x1F1\x1EU\x1EG\x1EX\x1F16\x1F2\x1F\xC3\xBC\x1EC\x1EW\x1Fa\x1FZ\x1F0\x1F0\x1ED\x1ES\x1F120\x1F225\x1EN\x1EO\x1F1\x1EK\x1F4\x1F1\x1EX\x1F7\x1F6\x1F\xC3\xBC\x1F32\x1F3\x1F\x0A\x1F36\x1F1\x1F\xC3\xBC\x1E" }
fn expected() -> str { ret "20b206afd2bc56e420b206afd2bc56e420b206afd2bc56e4804725be308f1aaf317a3454ff083805a5836dc2cb8e523fa5836dc2cb8e523f8cfdf295e8128319c2f114938f0a5702a7ea010c13e6e6e287ff85c0110c5785c25c7bdf1c7b433a867293cd369d25037c2f31087f0bd95fdb744ff28e97505ea95deaf20af14ee98c8a4fe9875ff28faae01ade816c7966f6a1f2774180d7c7cc4b7d31e0628411f6a1f1774180d614cc4b7d31e062841170b98ba4b2fd45ac5e33befa43a49477cfdd58e39d7a6d1aa3ee99c5a7a02c2ac1268e5215195d964afd34d4e914cb7d1ae6cd3421589e95c6ff2595c9dabfb50da8e8d2f9dea972574f0bc87307e3a454b68c3cb33b012954b68c3cb33b0129dafe80397549d2b9aad807978f38727d445be457acf43eede49ee8e105d50900e49ee8e105d50900a3fe5eb3df9da1a944af31e63d3926e54919565edf05684904b9fe325183910b2fb5836249cb9b7e37a412f61c63b87b1024b6f657fe86b7e32790281458e0639efd03f7ecfbc50dcd4ca6007200ee951eb1e02aeb650a431eb1e02aeb650a43a6213e56adbda08fa6213e56adbda08f5d79d61d1bc1d79092241631ca28d6cfa862d6e12383aaf0323baf46f811265d323baf46f811265d323baf46f811265d323baf46f811265d6c23682b810ebe5d68882f46f070ecd656fb8feb27bc1b9efd53a2f597bb38eef67af16c3897f106256f3cda2e26aaf25d385da02bbb072ba9b4543f89381fabe41e3162606b2cc67e5cb50c09aaad264377b0222187a270bb006172f14032ba6cb57aeac79b52636d5e020ff8455fc66d5e020ff8455fc64032ccbdb3702c28090de60e6b1b4af24032ccbdb3702c28d23d729d4b8a6eed75ad7234d501660575ad7234d501660575ad7234d50166052bee2061f879ecc59891442e0dcaa6cd3cc9ce6c403f38de707fe272eb520cd6707fe272eb520cd6707fe272eb520cd6acdda7ae5775f07cc52660440d975855bfccefe38acae129f16eb031092c6c5a2eed8e26d20f579d7b225d6ab0bfbaeb67adaa171534eaa337a65c2bdb49dbb378a2f1cd7ba338917fdaa236baaf7f2cb483d75930f17bb424b680574d77f6503038b24ffaa2a1fc83cb985b2f1c1326ed4c96d028edc895f3a420b6591d6f37007801a8ae781fac4bbd24c6782d8f914bbd24c6782d8f9129f6f0e3017fbf4931548d3ab7e3165831548d3ab7e31658d79a6a4629300b78d79a6a4629300b78d192d0f26df2eed2d192d0f26df2eed2fb1309ce78bed71afb1309ce78bed71a280b901687aba96b49ff759617142a5253c26142691020673e2dbd7d998377b59d7642ebada4fd320347c342c88780b90347c342c88780b956500151ebaca0f0baebc9dbea12b5b156500151ebaca0f0cb14afa0234709c53f3fddbcc978936c0d97877e40f0e570e1b5a0c6650c220ea798d641ca1a9a7151e7f28e978574ae51e7f28e978574aeb9d6a9ae83f170c15ccc808e3b5f1cdc4c83f1d976410b262c2dd9839243ae33b3ea59a2fba8727e10cfb4aebd2f272618c51d37acfdd2fd5ffef8341061c9d0ee7c34d290d5beac58935a692ccf6540b971b734f0b96747b971b734f0b96747bfeb4aa2740b9135f112de913d68914ca1d6ef2206a1b1390abae401b77eff9cb50f54c362cac7420b3cfbc68ccdcacd6d146a8fdd063c58fd3653ddbbd693951a3663139d50a89397f82f7b52a8344090fc59ca3ec7aaca5c6012299faf90d13369a6f05a490b79c08f01a17c488dfd1492c402296577319c4fe35d89b068b25a8c9ac46a1d020d8a09bd153f9190221fa0534bc45e78da60ef7be15206a5f2c66b3ffc2f4f8ffdf7ff838d672227f42c04bde2cd3316c884ece7b4b33e7fbaea06d894ab0dee058cdd46c9c66bf89312672025890a7bb2e3c18a5a359d785e13783dbde597860b7f4a48ba41312c9513783dbde597860b63b913d34cdb37b1950f3a218322a03f7b7fc0edbd16b59d0988e3fb0daa9205c32e898d26802ffbdac70f5db08a4bc2dac70f5db08a4bc2ba7f40f4ffae53415af010ef613dd8eabc999a05c190c6d6bc999a05c190c6d6bc999a05c190c6d6bb1c5017f7e96ee9bb1c5017f7e96ee909a784c37028bbb04cf83ef12670e05e764865af2b04756d9e507681227f4776543a30f51c694219a553a3c81df1d7a50ea29776e15fe84bd6f88db98c65f23fd6f88db98c65f23f098f48d54de2afd70fc6039e0d99933d0fc6039e0d99933d3cba2e5bcf28060d0a0cd6a761fae609bd7f63d2cad0154ad8e4ca6a1c7ada12aff18486bce94719aff18486bce94719d8e4ca6a1c7ada12b954dc89080cc3ef374d01c9c680133d3ed3bf4691eb070ee8b890b41ded38e67fce14d1e3910f777fce14d1e3910f77360aec424a7cd97e451d98dc66289368cd6c1452f80698d061b23a34961f8f1cbddaa9141ec55061c6d5c3278d59733fc09fe8e42bf1cbf85d746453b2a6dfc847aaf4e234977ddc549fe558531cbec7d42d2f1efcd1eb84d42d2f1efcd1eb84b1ca7141bdb9e5c867fc20d83ee02a6c4826270d093e094c8b868aa849b00f503c6c8dcc112df15f484c2fafdaaeef0b47c3c72fb248bdd147c3c72fb248bdd147c3c72fb248bdd1eed666c4b087cef1eed666c4b087cef1551e73d412911114ae5bb2e6286380ffae5bb2e6286380ff32028da9b7a102b26f81c1f712e46f5d8920da6098c40bba0d568357d4407d4ed246648120b54471fe2051741ee001c6fe2051741ee001c6413a97c1f68635752f73df4962da9e63e8f4872ffe3c52160bccd28417ca60ab7324cbee05cf4e7190f9ddaa09f30120a428c1d759b488356df3c60c0b2b76bb9e358048d077a5ef9e358048d077a5ef47b05c82429f558d249d1c43fa67b059533e535684fd340eeac1dc1e8036fa535b10b0a36d7eb7b125236533e2a5363025236533e2a5363089fef764a48b10dda8f4b24d489840c759727142843277025972714284327702aaea3f928db15fc70c9cdc9f7869e220aaea3f928db15fc7aaea3f928db15fc72380ef4c2650a8948e3af997cd94bd758e3af997cd94bd758e3af997cd94bd7524a3c2b58810ea7f3fc0165d680026b63035dd0dbac8221871b437cfd9bf933097d4d2f6a8fd4840c38c6d937a9c378a6580275714a6eea08cd05388c38d0a2a8cd05388c38d0a2a330e3ab1547af96741a174c2f1c90cedece69676ea75ea60ece69676ea75ea60062f7594dc2a1c0f41c8bc61df8efb0248ba044e8864d45e48ba044e8864d45e48ba044e8864d45e667839cd379e27c2d106a791189d9c2644bea95cf50805c2018227a18b10b6c6720aed596a6c8f478c30b9fb907b3f2e8071fb0f594564838c30b9fb907b3f2eeee69c4df5345d3aeee69c4df5345d3a9874c4d7b99eabae8535f767241a83cc2784089169f0c9c5801c10f4646a8a7d030f973095c5c1083e68ef595513c6ffefdbc856123ad0dbd3d5c5ee3574b18746da226da8aacf55939b7f5d501876c52ddc32ab9400873a0b46134dd2d52bcd024f845f363304de2c7066b6d30a03cfec9f339f6ec2c4122c7066b6d30a03cfa0114121931f3d582c589db6d2f5cf63cc91ac618733f89ce6809da943ae606e80eaf6ea88f577e2e716ec36a264ac6c83681133daa7c10383681133daa7c103f2a01be2e399a96da869a1ec44669f7edca26cf55e10042533023df32284ad7933023df32284ad79b798879cd7da14999d3d5d8483f056cb95431d7cf7e9d2b4bafa76b3c56cd4b6aedda6a6ce0fdcf23030088dbeec982483c6386f4f0d0af0dd77906b7b09d4fc3a457d1ecbbad711560169250c9cfda1831e88d94d47dde2f40c9087fa56078f2fb8d280e21ea24d33f1e0fac82b4482913afc41e5ea327e5c78616f2ca2cf985da0207518f7c5f051c169b010f6f7ce1842ee0a25d4ce16ffdc1ab82ba561e83b6f39593745de04d4d4b65b48d091f4b5c2af224953cec8d3d175e6b57fb238d3d175e6b57fb238b0468a42482a05c208570df3cb7994d822a13dd8436952a99d429cef4153311073f2176a90874f9a17e8823d2f9599b85a26dd6a3f4b333027c65f0d2d7b0e1649e22ac0447832164d5f0f48df8dc94027c65f0d2d7b0e165a26dd6a3f4b33304c9277dc734f8afcdb93826dff613697db93826dff613697774978aeec8d6921770bd83f7b3f00d4e3ccfd1d750d8225fdd28404cbd7407455a782769806a8786c592e91a127eee69ca8888dab61d3b49ca8888dab61d3b4d6e7005882ec1844a555ceefd840c2152be13a05ef176b40eb56406651476588c62bea13f212714184f6a66bc947059dbe4634bf7a753e92be4634bf7a753e921f6ac189d341cdf99f2e4c0e988e6ed6d3d7788b3ff4e4667514f22befc62e257514f22befc62e254081b16a77ae2bea12fc4e787c10d31a2fe8c22f2d3cd9255248da3caedb5bfd5248da3caedb5bfd5084d8cfcc4473157c4d01aa99c35cc399233745f4052ea199233745f4052ea17623affb5f1faa1b7e68c044a4033df2263aa025e3080ba204a6066a61a1e0a004a6066a61a1e0a04cfa3c4ea482fe8304a6066a61a1e0a004a6066a61a1e0a004a6066a61a1e0a007e271dc1e47200107e271dc1e4720015e657c7b1beba76f815164ef40da82e5df0940e07f293f7652f652461e8883d37419cde7b91afdb7272ee2e4c1b8c0159a1008abb38b48e70fc9a0fb2f500f1661eadb2477fe3af361eadb2477fe3af31c1097950dfbcc021c1097950dfbcc02c34b9bb08f80be960445bef4e0c14fa1d0709c79e0aeefd2d0709c79e0aeefd20cea269bf1dcc47aa3373a9c95cf8996a3373a9c95cf89969245f1cdc23f4ec69245f1cdc23f4ec6b8bb8967cf80bca26f752b3d0b0a07119b464bcb580e94e6f6b4d52bcd39a2f1ed294b27f38fca39dbb50cbb9ad3c175dc1ce649c9249476b83a9b7f34eaea5fa6a0effa13996c62f88fb1afe1f729ef5412d12e69903f6333a626e49df695ab33a626e49df695ab79d561bffb1adab683df725949b90f6f4270998b900ee59af0a5ca4dd3dd588d92837fd88a6d2672c22312858dc3d7c684a34e5d8992439c56ba6c0ba10e229230df10fd6a2cd33bc22312858dc3d7c686ff7deebb50efd671dff2e248210347c3f34beb252c3817e522ea3be6b6a69a077236e6399f5797077236e6399f5797d5e8dda5bb36ce02cf5272fb4db9becd792fe82f16b686f5c7451919ec386077c8f076d9750acb3bf42c2226a1e6c27ff309e7abf980c43a2513ecdb28ea70523ab0fdd852061624662fb579b151cec2592795162349e3d674faa8e830eccd9cfb8e7ab069166ecede77801fe90035b7fb8e7ab069166ece6d21659db1846e4e04573953dc864bbda7f0346fcdf2db478e51747d65e30854b9dc5f196f5f0a2ce7233f30cb63af582b916be90aea5c2cd3240f9edb04fe1ea0953870d1758d302cc4323707dfd9fa4a2779887f60daf31ca5a58eebea1680fdd0f527fff3f36d80ef93ec677f966cbcd5c3f4366e0f80454c952982019ba4e435cc4968e4a1659bc10263e1994e5f4857b8611f03dfdac8a64c9b57ae239d6da175a8c90f5ec8567ae9da502750b16d94bb29f3ab1af065c08ed3b86d8865645798b62dcd2e0ddc958413e42230a7547f36304bbf01d099018e47b438e21999018e47b438e219e940443a2a144d94e940443a2a144d942a5535c2b0c0783f2a5535c2b0c0783fbcdd2a4dfd261832bcdd2a4dfd26183279bb1a7d003a61c7b2b4b587828b74b6b2b4b587828b74b66af22e973c33026525e0c8efd6914d7a" }
const OPS: usize = 520usize
// END GENERATED

fn mix(h: u64, v: u32) -> u64 { ret (h ^ u64(v)) *% 1099511628211u64 }

fn digest(e: *ce.Editor, result: u32) -> u64 {
    var h = 14695981039346656037u64
    h = mix(h, result)
    h = mix(h, u32(ce.len(e)))
    var i = 0usize
    while i < ce.len(e) {
        h = mix(h, u32(ce.byte_at(e, i)))
        i += 1usize
    }
    h = mix(h, u32(e.nsel))
    var s = 0usize
    while s < e.nsel {
        h = mix(h, u32(e.sels[s].anchor))
        h = mix(h, u32(e.sels[s].head))
        s += 1usize
    }
    h = mix(h, u32(e.primary))
    var d = 0u32
    if ce.is_dirty(e) { d = 1u32 }
    h = mix(h, d)
    h = mix(h, u32(e.undo.nent))
    h = mix(h, u32(e.redo.nent))
    var toks: [512]ce.Token = zero
    var ln = 0usize
    while ln < ce.line_count(e) {
        let n = ce.tokens(e, ln, toks[..])
        var t = 0usize
        while t < n && t < 512usize {
            h = mix(h, u32(toks[t].start))
            h = mix(h, u32(toks[t].end))
            h = mix(h, toks[t].kind)
            t += 1usize
        }
        ln += 1usize
    }
    ret h
}

fn parse_int(s: str, a: usize, b: usize) -> usize {
    var v = 0usize
    var i = a
    while i < b {
        v = v * 10usize + usize(s[i] - 48u8)
        i += 1usize
    }
    ret v
}

fn hex_u64(s: str, at: usize) -> u64 {
    var v = 0u64
    var i = 0usize
    while i < 16usize {
        let c = s[at + i]
        var d = 0u64
        if c >= 97u8 { d = u64(c - 87u8) } else { d = u64(c - 48u8) }
        v = v * 16u64 + d
        i += 1usize
    }
    ret v
}

fn text_is(e: *const ce.Editor, want: str) -> bool {
    if ce.len(e) != want.len { ret false }
    var i = 0usize
    while i < want.len {
        if ce.byte_at(e, i) != want[i] { ret false }
        i += 1usize
    }
    ret true
}

fn load_text(e: *ce.Editor, s: str) -> bool { ret ce.load(e, s) == ok }

fn main(a: *mem.Arena, args: []str) -> err {
    let (e0, oe) = ce.open(a, 400usize, 40usize, 8usize, 12usize, 40usize, 260usize)
    if oe != ok { os.exit(250i32) }
    var ed = e0
    ce.set_language(&ed, ce.lang_javascript())

    // 1: typing, undo and redo.
    if ce.type_text(&ed, "hel") != ok || ce.type_text(&ed, "lo") != ok { os.exit(201i32) }
    if !text_is(&ed, "hello") || ed.sels[0usize].head != 5usize || ed.undo.nent != 1usize { os.exit(201i32) }
    if ce.undo(&ed) != ok || !text_is(&ed, "") || ed.sels[0usize].head != 0usize || ce.can_undo(&ed) { os.exit(201i32) }
    if ce.redo(&ed) != ok || !text_is(&ed, "hello") || ed.sels[0usize].head != 5usize || ce.can_redo(&ed) { os.exit(201i32) }
    ce.break_group(&ed)
    if ce.type_text(&ed, "!") != ok || ed.undo.nent != 2usize { os.exit(201i32) }

    // 2: backspace removes a whole grapheme (a base plus its combining mark, a multibyte scalar).
    if !load_text(&ed, "ae\xCC\x81\xC3\xA9") { os.exit(202i32) }
    var r2 = [1]ce.Range{ ce.caret(6usize) }
    if ce.set_selection(&ed, r2[..], 0usize) != ok { os.exit(202i32) }
    if ce.delete_char(&ed, false) != ok || !text_is(&ed, "ae\xCC\x81") { os.exit(202i32) }
    if ce.delete_char(&ed, false) != ok || !text_is(&ed, "a") { os.exit(202i32) }
    if ce.undo(&ed) != ok || !text_is(&ed, "ae\xCC\x81\xC3\xA9") { os.exit(202i32) }

    // 3: refusals leave everything as it was.
    if !load_text(&ed, "abc\n\xC3\xA9") { os.exit(203i32) }
    let id_before = ed.content_id
    let rev_before = ed.revision
    var bad: [1]ce.Edit = zero
    bad[0usize] = ce.Edit { at: 5usize, remove: 0usize, text_off: 0usize, text_len: 1usize }
    if ce.apply_edits(&ed, bad[..], "x") != ce.NotBoundary { os.exit(203i32) }
    bad[0usize] = ce.Edit { at: 0usize, remove: 0usize, text_off: 0usize, text_len: 1usize }
    if ce.apply_edits(&ed, bad[..], "\xC3") != ce.Invalid { os.exit(203i32) }
    bad[0usize] = ce.Edit { at: 2usize, remove: 9usize, text_off: 0usize, text_len: 0usize }
    if ce.apply_edits(&ed, bad[..], "") != ce.BadEdits { os.exit(203i32) }
    var two: [2]ce.Edit = zero
    two[0usize] = ce.Edit { at: 0usize, remove: 3usize, text_off: 0usize, text_len: 0usize }
    two[1usize] = ce.Edit { at: 1usize, remove: 0usize, text_off: 0usize, text_len: 0usize }
    if ce.apply_edits(&ed, two[..], "") != ce.BadEdits { os.exit(203i32) }
    if !text_is(&ed, "abc\n\xC3\xA9") || ed.content_id != id_before || ed.revision != rev_before || ce.can_undo(&ed) { os.exit(203i32) }
    var big: [450]u8 = zero
    var bi = 0usize
    while bi < 450usize {
        big[bi] = 120u8
        bi += 1usize
    }
    bad[0usize] = ce.Edit { at: 0usize, remove: 0usize, text_off: 0usize, text_len: 450usize }
    if ce.apply_edits(&ed, bad[..], big[..]) != ce.TooLarge { os.exit(203i32) }
    if !text_is(&ed, "abc\n\xC3\xA9") || ce.can_undo(&ed) { os.exit(203i32) }

    // 4: dirty follows the saved point across undo and redo.
    if !load_text(&ed, "x") || ce.is_dirty(&ed) { os.exit(204i32) }
    if ce.type_text(&ed, "y") != ok || !ce.is_dirty(&ed) { os.exit(204i32) }
    ce.mark_saved(&ed)
    if ce.is_dirty(&ed) { os.exit(204i32) }
    ce.break_group(&ed)
    if ce.type_text(&ed, "z") != ok || !ce.is_dirty(&ed) { os.exit(204i32) }
    if ce.undo(&ed) != ok || ce.is_dirty(&ed) { os.exit(204i32) }
    if ce.undo(&ed) != ok || !ce.is_dirty(&ed) { os.exit(204i32) }
    if ce.redo(&ed) != ok || ce.is_dirty(&ed) { os.exit(204i32) }

    // 5: more groups than the history holds evict the oldest and keep the rest undoable.
    if !load_text(&ed, "") { os.exit(205i32) }
    var g = 0usize
    while g < 20usize {
        ce.break_group(&ed)
        if ce.type_text(&ed, "a") != ok { os.exit(205i32) }
        g += 1usize
    }
    if ed.undo.nent != 12usize || ce.len(&ed) != 20usize { os.exit(205i32) }
    var undone = 0usize
    while ce.can_undo(&ed) {
        if ce.undo(&ed) != ok { os.exit(205i32) }
        undone += 1usize
    }
    if undone != 12usize || ce.len(&ed) != 8usize { os.exit(205i32) }

    // 6: search: forward, backward, whole word, case, counting and one-transaction replace.
    if !load_text(&ed, "Foo foo food\nfoo") { os.exit(206i32) }
    let ci = ce.SearchOpts { case_sensitive: false, whole_word: false }
    let cs = ce.SearchOpts { case_sensitive: true, whole_word: false }
    let ww = ce.SearchOpts { case_sensitive: true, whole_word: true }
    let (p1, f1) = ce.find(&ed, "foo", 0usize, true, cs)
    if !f1 || p1 != 4usize { os.exit(206i32) }
    let (p2, f2) = ce.find(&ed, "foo", 4usize, false, ci)
    if !f2 || p2 != 0usize { os.exit(206i32) }
    let (n1, _) = ce.count_matches(&ed, "foo", ci, 100usize)
    let (n2, _) = ce.count_matches(&ed, "foo", ww, 100usize)
    let (n3, capped) = ce.count_matches(&ed, "foo", ci, 2usize)
    if n1 != 4usize || n2 != 2usize || n3 != 2usize || !capped { os.exit(206i32) }
    let (rn, re) = ce.replace_all(&ed, "foo", "ba", ww)
    if re != ok || rn != 2usize || !text_is(&ed, "Foo ba food\nba") || ed.undo.nent != 1usize { os.exit(206i32) }
    if ce.undo(&ed) != ok || !text_is(&ed, "Foo foo food\nfoo") { os.exit(206i32) }

    // 7: languages and tokens.
    var toks: [16]ce.Token = zero
    ce.set_language(&ed, ce.lang_for_suffix("JS"))
    if !load_text(&ed, "let x = 12 // c") { os.exit(207i32) }
    let nt = ce.tokens(&ed, 0usize, toks[..])
    if nt != 5usize || toks[0usize].kind != ce.TOK_KEYWORD || toks[1usize].kind != ce.TOK_IDENT || toks[2usize].kind != ce.TOK_OPERATOR || toks[3usize].kind != ce.TOK_NUMBER || toks[4usize].kind != ce.TOK_COMMENT || toks[4usize].start != 11usize { os.exit(207i32) }
    ce.set_language(&ed, ce.lang_for_suffix("e"))
    if !load_text(&ed, "fn main() -> err { ret ok }") { os.exit(207i32) }
    if ce.tokens(&ed, 0usize, toks[..]) != 11usize || toks[0usize].kind != ce.TOK_KEYWORD || toks[5usize].kind != ce.TOK_OPERATOR { os.exit(207i32) }
    ce.set_language(&ed, ce.lang_javascript())
    if !load_text(&ed, "a /* x\ny */ b\nc") { os.exit(207i32) }
    if ce.tokens(&ed, 1usize, toks[..]) != 2usize || toks[0usize].kind != ce.TOK_COMMENT || toks[1usize].kind != ce.TOK_IDENT { os.exit(207i32) }
    // breaking the opener turns line 1 back into code without touching line 1's text
    var one: [1]ce.Edit = zero
    one[0usize] = ce.Edit { at: 2usize, remove: 2usize, text_off: 0usize, text_len: 0usize }
    if ce.apply_edits(&ed, one[..], "") != ok { os.exit(207i32) }
    if ce.tokens(&ed, 1usize, toks[..]) != 4usize || toks[0usize].kind != ce.TOK_IDENT { os.exit(207i32) }
    if ce.undo(&ed) != ok || ce.tokens(&ed, 1usize, toks[..]) != 2usize || toks[0usize].kind != ce.TOK_COMMENT { os.exit(207i32) }

    // 8: vertical motion keeps its goal column across a short line.
    if !load_text(&ed, "abcdef\nab\nabcdef") { os.exit(208i32) }
    var r8 = [1]ce.Range{ ce.caret(5usize) }
    if ce.set_selection(&ed, r8[..], 0usize) != ok { os.exit(208i32) }
    if ce.move_selection(&ed, ce.MOVE_DOWN, false) != ok || ed.sels[0usize].head != 9usize { os.exit(208i32) }
    if ce.move_selection(&ed, ce.MOVE_DOWN, false) != ok || ed.sels[0usize].head != 15usize { os.exit(208i32) }
    if ce.move_selection(&ed, ce.MOVE_LEFT, false) != ok || ed.sels[0usize].head != 14usize { os.exit(208i32) }

    // 9: three carets type once and undo once; Enter between braces opens an indented middle line.
    if !load_text(&ed, "a\nb\nc") { os.exit(209i32) }
    var r9 = [3]ce.Range{ ce.caret(1usize), ce.caret(3usize), ce.caret(5usize) }
    if ce.set_selection(&ed, r9[..], 0usize) != ok { os.exit(209i32) }
    if ce.type_text(&ed, "x") != ok || !text_is(&ed, "ax\nbx\ncx") || ed.nsel != 3usize { os.exit(209i32) }
    if ce.undo(&ed) != ok || !text_is(&ed, "a\nb\nc") { os.exit(209i32) }
    if !load_text(&ed, "  {}") { os.exit(209i32) }
    var r9b = [1]ce.Range{ ce.caret(3usize) }
    if ce.set_selection(&ed, r9b[..], 0usize) != ok || ce.newline_indent(&ed) != ok { os.exit(209i32) }
    if !text_is(&ed, "  {\n      \n  }") || ed.sels[0usize].head != 10usize { os.exit(209i32) }

    // 10: indent, dedent and comment toggle are one transaction over the selected lines.
    ce.set_language(&ed, ce.lang_neper())
    if !load_text(&ed, "a\n\nb") { os.exit(210i32) }
    var r10 = [1]ce.Range{ ce.Range { anchor: 0usize, head: 4usize, goal: ce.NO_GOAL } }
    if ce.set_selection(&ed, r10[..], 0usize) != ok { os.exit(210i32) }
    if ce.indent_lines(&ed, false) != ok || !text_is(&ed, "    a\n\n    b") || ed.undo.nent != 1usize { os.exit(210i32) }
    if ce.toggle_comment(&ed) != ok || !text_is(&ed, "    // a\n\n    // b") { os.exit(210i32) }
    if ce.toggle_comment(&ed) != ok || !text_is(&ed, "    a\n\n    b") { os.exit(210i32) }
    if ce.indent_lines(&ed, true) != ok || !text_is(&ed, "a\n\nb") { os.exit(210i32) }

    // 11: the generated script against the flat model, a digest after every step.
    let (f0, fe) = ce.open(a, 400usize, 40usize, 8usize, 12usize, 40usize, 260usize)
    if fe != ok { os.exit(250i32) }
    var m = f0
    ce.set_language(&m, ce.lang_javascript())
    let sc = script()
    let want = expected()
    var pos = 0usize
    var step = 0usize
    var xe: [8]ce.Edit = zero
    var xt: [256]u8 = zero
    var rg: [8]ce.Range = zero
    while pos < sc.len {
        var q = pos
        while sc[q] != 30u8 { q += 1usize }
        let op = sc[pos]
        var fs: [16]usize = zero
        var fe_: [16]usize = zero
        var nf = 0usize
        var k = pos + 1usize
        while k < q {
            if sc[k] == 31u8 {
                fs[nf] = k + 1usize
                if nf > 0usize { fe_[nf - 1usize] = k }
                nf += 1usize
            }
            k += 1usize
        }
        if nf > 0usize { fe_[nf - 1usize] = q }
        var res = ok
        if op == 84u8 {
            res = ce.type_text(&m, sc[fs[0usize]..fe_[0usize]])
        } else if op == 66u8 {
            res = ce.delete_char(&m, false)
        } else if op == 70u8 {
            res = ce.delete_char(&m, true)
        } else if op == 85u8 {
            res = ce.undo(&m)
        } else if op == 82u8 {
            res = ce.redo(&m)
        } else if op == 83u8 {
            rg[0usize] = ce.Range { anchor: parse_int(sc, fs[0usize], fe_[0usize]), head: parse_int(sc, fs[1usize], fe_[1usize]), goal: ce.NO_GOAL }
            res = ce.set_selection(&m, rg[0usize..1usize], 0usize)
        } else if op == 77u8 {
            var c = 0usize
            while c < nf && c < 8usize {
                rg[c] = ce.caret(parse_int(sc, fs[c], fe_[c]))
                c += 1usize
            }
            res = ce.set_selection(&m, rg[0usize..nf], 0usize)
        } else if op == 88u8 {
            var c = 0usize
            var tl = 0usize
            while c * 3usize < nf {
                let at = parse_int(sc, fs[c * 3usize], fe_[c * 3usize])
                let rem = parse_int(sc, fs[c * 3usize + 1usize], fe_[c * 3usize + 1usize])
                let tb = fs[c * 3usize + 2usize]
                let te = fe_[c * 3usize + 2usize]
                var j = tb
                while j < te {
                    xt[tl + (j - tb)] = sc[j]
                    j += 1usize
                }
                xe[c] = ce.Edit { at: at, remove: rem, text_off: tl, text_len: te - tb }
                tl += te - tb
                c += 1usize
            }
            res = ce.apply_edits(&m, xe[0usize..c], xt[0usize..tl])
        } else if op == 78u8 {
            res = ce.newline_indent(&m)
        } else if op == 73u8 {
            res = ce.indent_lines(&m, false)
        } else if op == 68u8 {
            res = ce.indent_lines(&m, true)
        } else if op == 67u8 {
            res = ce.toggle_comment(&m)
        } else if op == 71u8 {
            ce.break_group(&m)
        } else if op == 87u8 {
            let cs_ = parse_int(sc, fs[2usize], fe_[2usize]) == 1usize
            let ww_ = parse_int(sc, fs[3usize], fe_[3usize]) == 1usize
            let (_, wr) = ce.replace_all(&m, sc[fs[0usize]..fe_[0usize]], sc[fs[1usize]..fe_[1usize]], ce.SearchOpts { case_sensitive: cs_, whole_word: ww_ })
            res = wr
        } else if op == 75u8 {
            res = ce.move_selection(&m, u32(parse_int(sc, fs[0usize], fe_[0usize])), parse_int(sc, fs[1usize], fe_[1usize]) == 1usize)
        } else if op == 90u8 {
            ce.mark_saved(&m)
        } else if op == 79u8 {
            m.use_tabs = parse_int(sc, fs[0usize], fe_[0usize]) == 1usize
        }
        var result = 0u32
        if res != ok { result = 1u32 }
        if digest(&m, result) != hex_u64(want, step * 16usize) { os.exit(i32(1usize + step % 200usize)) }
        step += 1usize
        pos = q + 1usize
    }
    if step != OPS { os.exit(251i32) }
    ret ok
}
