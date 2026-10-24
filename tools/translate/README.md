# Zulu translation

English is the source. Every `Text` in the apps imports `package:ubuntu_core/tr_text.dart` (a drop-in `Text` that translates at build time), and hints, tooltips and notifications go through `tr()`.

- `extract.py` (frozen) and `extract2.py` list the user-facing English strings. `order.json` is the frozen list; `zu/NNN.txt` are `index<TAB>Zulu`; `zu/fixes.txt` overrides; `zu/extra.tsv` is `English<TAB>Zulu` for strings found later.
- `gen.py` builds `packages/ubuntu_core/lib/zulu_strings.dart` (exact sentences and `{0}` templates), joins adjacent string literals that are one sentence at run time, and strips em dashes.
- `patch_text.py` and `patch_sinks.py` point new files at the translating `Text` and wrap hints/tooltips. Run them after adding files.
- `Tr.misses` (debug) lists what was shown in Zulu without a translation. `nolifa-delivery/test/zulu_probe_test.dart` and `ubuntu-drop/test/zulu_probe_test.dart` fail if a screen has gaps.

Not translated: the back office (staff, English), seeded demo names, and text that comes from the server (vet notes, dam names).
These translations were written without a first-language speaker. Have a native isiZulu speaker review `zulu_strings.dart` before store release.
